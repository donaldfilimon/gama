public import GamaAuthoring

/// Why a graph could not be evaluated. Nothing is changed when evaluation
/// fails.
public enum GraphError: Error, Hashable, Sendable, CustomStringConvertible {
    /// A node names a definition the registry does not have.
    case unknownDefinition(GraphNodeID, String)
    /// A node's stored ports differ from its definition's, for example after
    /// the definition changed.
    case signatureMismatch(GraphNodeID, String)
    /// An input has neither a connection nor a value.
    case missingInput(PortReference)
    /// A node's computation failed, for example a division by zero.
    case failed(GraphNodeID, String)
    /// The graph itself is invalid (a cycle).
    case invalid(String)

    public var description: String {
        switch self {
        case .unknownDefinition(let node, let definition): "\(node) uses unknown node type '\(definition)'"
        case .signatureMismatch(let node, let definition): "\(node) no longer matches '\(definition)'"
        case .missingInput(let port): "\(port) has no connection or value"
        case .failed(let node, let message): "\(node): \(message)"
        case .invalid(let message): message
        }
    }
}

/// The input values a node computes from, by input name. Every declared
/// input is present and has its declared type.
public struct NodeInputs: Sendable {
    let values: [String: GraphValue]
    let node: GraphNodeID

    public subscript(name: String) -> GraphValue? { values[name] }

    public func float(_ name: String) throws(GraphError) -> Float {
        guard case .float(let v)? = values[name] else { throw .failed(node, "\(name) is not a float") }
        return v
    }

    public func vector3(_ name: String) throws(GraphError) -> SIMD3<Float> {
        guard case .vector3(let v)? = values[name] else { throw .failed(node, "\(name) is not a vector3") }
        return v
    }

    public func color(_ name: String) throws(GraphError) -> SIMD4<Float> {
        guard case .color(let v)? = values[name] else { throw .failed(node, "\(name) is not a color") }
        return v
    }

    public func entity(_ name: String) throws(GraphError) -> EntityID? {
        guard case .entity(let v)? = values[name] else { throw .failed(node, "\(name) is not an entity") }
        return v
    }

    /// Fails the node with `message`.
    public func fail(_ message: String) -> GraphError { .failed(node, message) }
}

/// What a node type computes (ADR 0007).
///
/// A definition is pure: `compute` maps inputs to outputs. An output
/// definition (a sink) additionally turns its inputs into ordinary
/// ``DocumentCommand``s, which is how a graph reaches the scene through the
/// same command bus as every other surface.
public struct NodeDefinition: Sendable {
    /// Stable name stored in documents, such as `math.add`.
    public let id: String
    /// Display name, such as `Add`.
    public let title: String
    /// Grouping for pickers: Constant, Math, Vector, Color, Output.
    public let category: String
    /// The graph domains that offer this node; empty means every domain.
    public let domains: Set<GraphDomain>
    public let inputs: [GraphPort]
    public let outputs: [GraphPort]
    /// A value for every input, so a freshly added node always evaluates.
    public let defaults: [String: GraphValue]
    let compute: @Sendable (NodeInputs) throws(GraphError) -> [String: GraphValue]
    let emit: (@Sendable (NodeInputs, SceneDocument) throws(GraphError) -> [any DocumentCommand])?

    public init(
        id: String,
        title: String,
        category: String,
        domains: Set<GraphDomain> = [],
        inputs: [GraphPort],
        outputs: [GraphPort],
        defaults: [String: GraphValue],
        compute: @escaping @Sendable (NodeInputs) throws(GraphError) -> [String: GraphValue] = { _ in [:] },
        emit: (@Sendable (NodeInputs, SceneDocument) throws(GraphError) -> [any DocumentCommand])? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.domains = domains
        self.inputs = inputs
        self.outputs = outputs
        self.defaults = defaults
        self.compute = compute
        self.emit = emit
    }

    /// Whether this node writes to the scene.
    public var isOutput: Bool { emit != nil }

    /// Whether a graph of `domain` offers this node.
    public func isOffered(in domain: GraphDomain) -> Bool { domains.isEmpty || domains.contains(domain) }

    /// The command that adds a node of this type, with its defaults.
    public func addCommand(to graph: GraphID, at position: SIMD2<Float> = .zero) -> AddGraphNode {
        AddGraphNode(
            to: graph, definition: id, inputs: inputs, outputs: outputs,
            values: defaults, position: position
        )
    }
}

/// The node types an evaluator knows, by id.
public struct NodeRegistry: Sendable {
    public private(set) var definitions: [NodeDefinition]

    public init(_ definitions: [NodeDefinition]) {
        self.definitions = definitions
    }

    public func definition(_ id: String) -> NodeDefinition? {
        definitions.first { $0.id == id }
    }

    /// Definitions a graph of `domain` offers, in registry order.
    public func offered(in domain: GraphDomain) -> [NodeDefinition] {
        definitions.filter { $0.isOffered(in: domain) }
    }

    /// Adds or replaces a definition, for plugins and tests.
    public mutating func register(_ definition: NodeDefinition) {
        definitions.removeAll { $0.id == definition.id }
        definitions.append(definition)
    }
}
