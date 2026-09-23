public import GamaAuthoring

/// Every output value a graph computed, by port.
public struct GraphResult: Sendable {
    public var outputs: [PortReference: GraphValue]
    /// The inputs each node saw, including resolved connections.
    public var inputs: [PortReference: GraphValue]
}

/// Evaluates graphs against a registry (ADR 0007).
///
/// Evaluation is a pure, synchronous function of the graph (and, for
/// outputs, the document): nodes run in topological order, ties broken by
/// authored order, so the same graph always produces the same values and
/// commands. It is `Sendable`, so a caller can run it off the main actor; the
/// commands it produces still go through ``EditorSession``.
public struct GraphEvaluator: Sendable {
    public let registry: NodeRegistry

    public init(registry: NodeRegistry = .standard) {
        self.registry = registry
    }

    /// Computes every node's outputs, or only those in `nodes` when given.
    public func evaluate(_ graph: GraphDocument, only nodes: Set<GraphNodeID>? = nil) throws(GraphError) -> GraphResult {
        let order = try orderOrThrow(graph).filter { nodes?.contains($0) ?? true }
        var result = GraphResult(outputs: [:], inputs: [:])
        for id in order {
            guard let node = graph.node(id) else { continue }
            let (definition, inputs) = try resolve(node, in: graph, with: result)
            for (name, value) in inputs.values {
                result.inputs[PortReference(id, name)] = value
            }
            let outputs = try definition.compute(inputs)
            for port in node.outputs {
                guard let value = outputs[port.name], value.type == port.type else {
                    throw .failed(id, "did not produce \(port.type) '\(port.name)'")
                }
                guard (try? value.validate()) != nil else {
                    throw .failed(id, "produced a non-finite '\(port.name)'")
                }
                result.outputs[PortReference(id, port.name)] = value
            }
        }
        return result
    }

    /// The scene edits the graph's output nodes produce, in evaluation order.
    /// Only the outputs and the nodes feeding them are evaluated, so a
    /// broken scratch node elsewhere in the graph does not block its outputs.
    public func commands(for graph: GraphDocument, in document: SceneDocument) throws(GraphError) -> [any DocumentCommand] {
        let result = try evaluate(graph, only: upstreamOfOutputs(graph))
        var commands: [any DocumentCommand] = []
        for id in try orderOrThrow(graph) {
            guard let node = graph.node(id), let definition = registry.definition(node.definition),
                  let emit = definition.emit
            else { continue }
            var values: [String: GraphValue] = [:]
            for port in node.inputs {
                values[port.name] = result.inputs[PortReference(id, port.name)]
            }
            commands += try emit(NodeInputs(values: values, node: id), document)
        }
        return commands
    }

    /// Output nodes and every node that feeds one.
    func upstreamOfOutputs(_ graph: GraphDocument) -> Set<GraphNodeID> {
        var needed: Set<GraphNodeID> = []
        var stack = graph.order.filter { registry.definition(graph.node($0)?.definition ?? "")?.isOutput == true }
        while let id = stack.popLast() {
            guard needed.insert(id).inserted else { continue }
            stack += graph.connections.filter { $0.to.node == id }.map(\.from.node)
        }
        return needed
    }

    private func orderOrThrow(_ graph: GraphDocument) throws(GraphError) -> [GraphNodeID] {
        do {
            return try graph.topologicalOrder()
        } catch {
            throw .invalid("\(error)")
        }
    }

    /// The node's definition and its inputs: a connected input takes its
    /// upstream output, an unconnected one its stored value.
    private func resolve(
        _ node: GraphNode, in graph: GraphDocument, with result: GraphResult
    ) throws(GraphError) -> (NodeDefinition, NodeInputs) {
        guard let definition = registry.definition(node.definition) else {
            throw .unknownDefinition(node.id, node.definition)
        }
        guard definition.inputs == node.inputs, definition.outputs == node.outputs else {
            throw .signatureMismatch(node.id, node.definition)
        }
        var values: [String: GraphValue] = [:]
        for port in node.inputs {
            let reference = PortReference(node.id, port.name)
            if let connection = graph.connection(into: reference) {
                guard let upstream = result.outputs[connection.from] else { throw .missingInput(reference) }
                values[port.name] = upstream
            } else if let value = node.values[port.name] {
                values[port.name] = value
            } else if let value = definition.defaults[port.name] {
                // An unconnected input without its own value uses the
                // definition's default, so disconnecting never strands a node.
                values[port.name] = value
            } else {
                throw .missingInput(reference)
            }
        }
        return (definition, NodeInputs(values: values, node: node.id))
    }
}

/// Evaluates a graph against the document it is applied to and applies the
/// resulting scene edits, as one undoable command (ADR 0007).
///
/// Editors put it in the same transaction as a graph edit, so the edit and
/// its effect on the scene undo together. Its inverse is the recorded
/// inverse of each edit, so redo replays exactly what happened rather than
/// re-evaluating. An evaluation failure refuses the whole transaction.
public struct EvaluateGraph: DocumentCommand {
    public var graph: GraphID
    public var evaluator: GraphEvaluator

    public init(_ graph: GraphID, evaluator: GraphEvaluator = GraphEvaluator()) {
        self.graph = graph
        self.evaluator = evaluator
    }

    public var label: String { "Evaluate Graph" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        guard let target = document.graph(graph) else { throw .missingGraph(graph) }
        let commands: [any DocumentCommand]
        do {
            commands = try evaluator.commands(for: target, in: document)
        } catch {
            throw .invalidGraph("\(graph) evaluation failed: \(error)")
        }
        return try CompositeCommand(label, commands).apply(to: &document, changes: &changes)
    }
}
