// Undoable edits to graphs (ADR 0007). Each returns its exact inverse, and
// every one reports `.graphChanged` so a listener can refresh graph views.

// MARK: Graphs

/// Creates an empty graph. Its identifier is ``SceneDocument/nextGraphID``
/// at the time it runs.
public struct CreateGraph: DocumentCommand {
    public var name: String
    public var domain: GraphDomain

    public init(name: String, domain: GraphDomain) {
        self.name = name
        self.domain = domain
    }

    public var label: String { "Create Graph" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        guard !name.isEmpty else { throw .invalidGraph("a graph needs a name") }
        guard document.nextGraphID.rawValue < UInt64.max else { throw .invalidGraph("no graph identifiers left") }
        let id = document.allocateGraphID()
        try document.insertGraph(GraphDocument(id: id, name: name, domain: domain), at: nil)
        changes.append(.graphChanged(id))
        return DeleteGraph(id)
    }
}

/// Deletes a graph with all its nodes and connections.
public struct DeleteGraph: DocumentCommand {
    public var id: GraphID

    public init(_ id: GraphID) {
        self.id = id
    }

    public var label: String { "Delete Graph" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        let (graph, index) = try document.removeGraph(id)
        changes.append(.graphChanged(id))
        return RestoreGraph(graph: graph, index: index)
    }
}

/// Puts a deleted graph back exactly. Only produced as an inverse.
struct RestoreGraph: DocumentCommand {
    var graph: GraphDocument
    var index: Int

    var label: String { "Restore Graph" }

    func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        try document.insertGraph(graph, at: index)
        changes.append(.graphChanged(graph.id))
        return DeleteGraph(graph.id)
    }
}

/// Renames a graph.
public struct RenameGraph: DocumentCommand {
    public var id: GraphID
    public var name: String

    public init(_ id: GraphID, to name: String) {
        self.id = id
        self.name = name
    }

    public var label: String { "Rename Graph" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        guard !name.isEmpty else { throw .invalidGraph("a graph needs a name") }
        var old = ""
        try document.updateGraph(id) { graph throws(AuthoringError) in
            old = graph.name
            graph.name = name
        }
        changes.append(.graphChanged(id))
        return RenameGraph(id, to: old)
    }
}

// MARK: Nodes

/// Adds a node with the given signature. Its identifier is the graph's
/// ``GraphDocument/nextNodeID`` at the time it runs.
public struct AddGraphNode: DocumentCommand {
    public var graph: GraphID
    public var definition: String
    public var inputs: [GraphPort]
    public var outputs: [GraphPort]
    public var values: [String: GraphValue]
    public var position: SIMD2<Float>

    public init(
        to graph: GraphID,
        definition: String,
        inputs: [GraphPort],
        outputs: [GraphPort],
        values: [String: GraphValue] = [:],
        position: SIMD2<Float> = .zero
    ) {
        self.graph = graph
        self.definition = definition
        self.inputs = inputs
        self.outputs = outputs
        self.values = values
        self.position = position
    }

    public var label: String { "Add Node" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        var added = GraphNodeID(rawValue: 0)
        try document.updateGraph(graph) { graph throws(AuthoringError) in
            guard graph.nextNodeRaw < UInt64.max else {
                throw .invalidGraph("\(graph.id) has no node identifiers left")
            }
            let id = graph.nextNodeID
            let node = GraphNode(
                id: id, definition: definition, inputs: inputs, outputs: outputs,
                values: values, position: position
            )
            try node.validate()
            graph.nextNodeRaw += 1
            graph.nodes[id] = node
            graph.order.append(id)
            added = id
        }
        changes.append(.graphChanged(graph))
        return RemoveGraphNode(added, from: graph)
    }
}

/// Removes a node and every connection touching it.
public struct RemoveGraphNode: DocumentCommand {
    public var graph: GraphID
    public var node: GraphNodeID

    public init(_ node: GraphNodeID, from graph: GraphID) {
        self.graph = graph
        self.node = node
    }

    public var label: String { "Remove Node" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        var restore: RestoreGraphNode?
        try document.updateGraph(graph) { graph throws(AuthoringError) in
            guard let removed = graph.nodes[node], let index = graph.order.firstIndex(of: node) else {
                throw .missingGraphNode(graph.id, node)
            }
            let touching = graph.connections.filter { $0.from.node == node || $0.to.node == node }
            graph.connections.removeAll { $0.from.node == node || $0.to.node == node }
            graph.nodes[node] = nil
            graph.order.remove(at: index)
            restore = RestoreGraphNode(graph: graph.id, node: removed, index: index, connections: touching)
        }
        changes.append(.graphChanged(graph))
        guard let restore else { throw .missingGraphNode(graph, node) }
        return restore
    }
}

/// Puts a removed node and its connections back. Only produced as an inverse.
struct RestoreGraphNode: DocumentCommand {
    var graph: GraphID
    var node: GraphNode
    var index: Int
    var connections: [GraphConnection]

    var label: String { "Restore Node" }

    func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        try document.updateGraph(graph) { graph throws(AuthoringError) in
            guard graph.nodes[node.id] == nil else { throw .invalidGraph("\(node.id) already exists") }
            guard (0...graph.order.count).contains(index) else {
                throw .invalidIndex(index, count: graph.order.count)
            }
            graph.nodes[node.id] = node
            graph.order.insert(node.id, at: index)
            graph.connections = GraphDocument.canonical(graph.connections + connections)
        }
        changes.append(.graphChanged(graph))
        return RemoveGraphNode(node.id, from: graph)
    }
}

/// Moves a node in the editor. Layout only; evaluation ignores it.
public struct MoveGraphNode: DocumentCommand {
    public var graph: GraphID
    public var node: GraphNodeID
    public var position: SIMD2<Float>

    public init(_ node: GraphNodeID, in graph: GraphID, to position: SIMD2<Float>) {
        self.graph = graph
        self.node = node
        self.position = position
    }

    public var label: String { "Move Node" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        guard position.x.isFinite, position.y.isFinite else { throw .invalidGraph("node position must be finite") }
        var old = SIMD2<Float>.zero
        try document.updateGraph(graph) { graph throws(AuthoringError) in
            guard var current = graph.nodes[node] else { throw .missingGraphNode(graph.id, node) }
            old = current.position
            current.position = position
            graph.nodes[node] = current
        }
        changes.append(.graphChanged(graph))
        return MoveGraphNode(node, in: graph, to: old)
    }
}

/// Sets or clears the constant on a node input.
public struct SetGraphValue: DocumentCommand {
    public var graph: GraphID
    public var node: GraphNodeID
    public var input: String
    /// `nil` clears the constant.
    public var value: GraphValue?

    public init(_ value: GraphValue?, for input: String, of node: GraphNodeID, in graph: GraphID) {
        self.graph = graph
        self.node = node
        self.input = input
        self.value = value
    }

    public var label: String { "Set \(input)" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        var old: GraphValue?
        try document.updateGraph(graph) { graph throws(AuthoringError) in
            guard var current = graph.nodes[node] else { throw .missingGraphNode(graph.id, node) }
            guard let port = current.input(input) else {
                throw .invalidGraph("\(node) has no input '\(input)'")
            }
            if let value {
                guard value.type == port.type else {
                    throw .invalidGraph("\(node).\(input) takes \(port.type), not \(value.type)")
                }
                try value.validate()
            }
            old = current.values[input]
            current.values[input] = value
            graph.nodes[node] = current
        }
        changes.append(.graphChanged(graph))
        return SetGraphValue(old, for: input, of: node, in: graph)
    }
}

// MARK: Connections

/// Connects an output to an input, replacing whatever fed that input.
/// Refused when the ports are missing, the types differ, or the connection
/// would make a cycle.
public struct ConnectPorts: DocumentCommand {
    public var graph: GraphID
    public var from: PortReference
    public var to: PortReference

    public init(_ from: PortReference, to: PortReference, in graph: GraphID) {
        self.graph = graph
        self.from = from
        self.to = to
    }

    public var label: String { "Connect" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        var previous: GraphConnection?
        try document.updateGraph(graph) { graph throws(AuthoringError) in
            guard let source = graph.nodes[from.node] else { throw .missingGraphNode(graph.id, from.node) }
            guard let target = graph.nodes[to.node] else { throw .missingGraphNode(graph.id, to.node) }
            guard let output = source.output(from.port) else {
                throw .invalidGraph("\(from.node) has no output '\(from.port)'")
            }
            guard let input = target.input(to.port) else {
                throw .invalidGraph("\(to.node) has no input '\(to.port)'")
            }
            guard output.type.canConnect(to: input.type) else {
                throw .invalidGraph("\(from) is \(output.type) but \(to) takes \(input.type)")
            }
            previous = graph.connection(into: to)
            graph.connections.removeAll { $0.to == to }
            graph.connections = GraphDocument.canonical(graph.connections + [GraphConnection(from: from, to: to)])
            _ = try graph.topologicalOrder()
        }
        changes.append(.graphChanged(graph))
        if let previous {
            return ConnectPorts(previous.from, to: previous.to, in: graph)
        }
        return DisconnectPorts(to, in: graph)
    }
}

/// Removes the connection feeding an input.
public struct DisconnectPorts: DocumentCommand {
    public var graph: GraphID
    public var input: PortReference

    public init(_ input: PortReference, in graph: GraphID) {
        self.graph = graph
        self.input = input
    }

    public var label: String { "Disconnect" }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        var removed: GraphConnection?
        try document.updateGraph(graph) { graph throws(AuthoringError) in
            guard let existing = graph.connection(into: input) else {
                throw .invalidGraph("\(input) is not connected")
            }
            removed = existing
            graph.connections.removeAll { $0.to == input }
        }
        changes.append(.graphChanged(graph))
        guard let removed else { throw .invalidGraph("\(input) is not connected") }
        return ConnectPorts(removed.from, to: removed.to, in: graph)
    }
}

// MARK: Composition

/// Several commands applied in order as one command, undone in reverse. For
/// producers that compute their edits against the document at apply time,
/// such as graph evaluation; a user-facing multi-step edit is an
/// ``EditorSession/transaction(_:_:)`` instead.
public struct CompositeCommand: DocumentCommand {
    public var label: String
    public var commands: [any DocumentCommand]

    public init(_ label: String, _ commands: [any DocumentCommand]) {
        self.label = label
        self.commands = commands
    }

    public func apply(to document: inout SceneDocument, changes: inout [SceneChange]) throws(AuthoringError) -> any DocumentCommand {
        var inverses: [any DocumentCommand] = []
        for command in commands {
            inverses.append(try command.apply(to: &document, changes: &changes))
        }
        return CompositeCommand(label, inverses.reversed())
    }
}

extension GraphDocument {
    /// Connections in their one canonical order, by target node then input
    /// name, so undoing a disconnect restores an equal document.
    static func canonical(_ connections: [GraphConnection]) -> [GraphConnection] {
        connections.sorted {
            ($0.to.node.rawValue, $0.to.port) < ($1.to.node.rawValue, $1.to.port)
        }
    }
}
