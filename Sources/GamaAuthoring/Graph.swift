/// Typed node graphs as authored document state (ADR 0007).
///
/// A graph is data in the ``SceneDocument``, edited only through
/// ``DocumentCommand``s like everything else, so undo, validation, and
/// persistence cover it. Each node carries its own port signature, so the
/// document can check connection types and cycles without knowing what the
/// nodes compute. Evaluation (turning a graph into scene edits) lives in the
/// `GamaGraph` target.

/// A graph's stable identity within one document.
public struct GraphID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: GraphID, rhs: GraphID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "g\(rawValue)" }
}

/// A node's stable identity within one graph.
public struct GraphNodeID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: GraphNodeID, rhs: GraphNodeID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "n\(rawValue)" }
}

/// What flows along a connection (spec §18).
public enum PortType: Hashable, Codable, Sendable, CustomStringConvertible {
    case float
    case vector2
    case vector3
    case vector4
    case color
    case boolean
    case integer
    case string
    case texture
    case mesh
    case material
    case transform
    case entity
    case execution
    case custom(String)

    /// Every built-in type, for pickers and tests.
    public static let builtIn: [PortType] = [
        .float, .vector2, .vector3, .vector4, .color, .boolean, .integer, .string,
        .texture, .mesh, .material, .transform, .entity, .execution,
    ]

    /// The spelling used in files and the console: `float`, `vector3`,
    /// `custom:<name>`.
    public var description: String {
        switch self {
        case .float: "float"
        case .vector2: "vector2"
        case .vector3: "vector3"
        case .vector4: "vector4"
        case .color: "color"
        case .boolean: "boolean"
        case .integer: "integer"
        case .string: "string"
        case .texture: "texture"
        case .mesh: "mesh"
        case .material: "material"
        case .transform: "transform"
        case .entity: "entity"
        case .execution: "execution"
        case .custom(let name): "custom:\(name)"
        }
    }

    /// Parses ``description``.
    public init?(_ text: String) {
        if text.hasPrefix("custom:") {
            let name = String(text.dropFirst("custom:".count))
            guard !name.isEmpty else { return nil }
            self = .custom(name)
            return
        }
        guard let match = Self.builtIn.first(where: { $0.description == text }) else { return nil }
        self = match
    }

    /// Whether an output of this type may feed an input of `input`'s type.
    /// Types must match exactly: conversions are explicit nodes, so a graph
    /// never changes meaning through an implicit cast.
    public func canConnect(to input: PortType) -> Bool { self == input }
}

/// A constant carried by an unconnected input.
public enum GraphValue: Hashable, Codable, Sendable {
    case float(Float)
    case vector2(SIMD2<Float>)
    case vector3(SIMD3<Float>)
    case vector4(SIMD4<Float>)
    /// Linear RGBA.
    case color(SIMD4<Float>)
    case boolean(Bool)
    case integer(Int64)
    case string(String)
    case transform(Transform)
    /// An entity reference; `nil` means "not set". A reference to an entity
    /// that was later deleted is allowed and evaluates as unset, so deleting
    /// an entity never has to edit graphs.
    case entity(EntityID?)
    case material(Material)

    public var type: PortType {
        switch self {
        case .float: .float
        case .vector2: .vector2
        case .vector3: .vector3
        case .vector4: .vector4
        case .color: .color
        case .boolean: .boolean
        case .integer: .integer
        case .string: .string
        case .transform: .transform
        case .entity: .entity
        case .material: .material
        }
    }

    /// Rejects non-finite numbers, invalid transforms, and invalid materials.
    public func validate() throws(AuthoringError) {
        func finite(_ values: [Float]) throws(AuthoringError) {
            guard values.allSatisfy(\.isFinite) else { throw .invalidGraph("graph values must be finite") }
        }
        switch self {
        case .float(let v): try finite([v])
        case .vector2(let v): try finite([v.x, v.y])
        case .vector3(let v): try finite([v.x, v.y, v.z])
        case .vector4(let v), .color(let v): try finite([v.x, v.y, v.z, v.w])
        case .transform(let t): try t.validate()
        case .material(let m): try m.validate()
        case .boolean, .integer, .string, .entity: break
        }
    }
}

/// A named, typed input or output.
public struct GraphPort: Hashable, Codable, Sendable {
    /// An identifier: letters, digits, and `_`, not starting with a digit,
    /// so it can name a USD attribute and a console argument unchanged.
    public var name: String
    public var type: PortType

    public init(_ name: String, _ type: PortType) {
        self.name = name
        self.type = type
    }

    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              first == "_" || ("a"..."z").contains(first) || ("A"..."Z").contains(first)
        else { return false }
        return name.unicodeScalars.allSatisfy {
            $0 == "_" || ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }
    }
}

/// One node: which definition computes it, its port signature, the constants
/// on its unconnected inputs, and where the editor draws it.
public struct GraphNode: Hashable, Codable, Sendable {
    public let id: GraphNodeID
    /// The evaluator's name for what this node computes, such as `math.add`.
    public var definition: String
    public var inputs: [GraphPort]
    public var outputs: [GraphPort]
    /// Constants for inputs, keyed by input name. An input that is neither
    /// connected nor given a value is an evaluation error, not a document
    /// error, so a graph can be built up one step at a time.
    public internal(set) var values: [String: GraphValue]
    /// Editor layout position; no effect on evaluation.
    public internal(set) var position: SIMD2<Float>

    public init(
        id: GraphNodeID,
        definition: String,
        inputs: [GraphPort],
        outputs: [GraphPort],
        values: [String: GraphValue] = [:],
        position: SIMD2<Float> = .zero
    ) {
        self.id = id
        self.definition = definition
        self.inputs = inputs
        self.outputs = outputs
        self.values = values
        self.position = position
    }

    public func input(_ name: String) -> GraphPort? { inputs.first { $0.name == name } }
    public func output(_ name: String) -> GraphPort? { outputs.first { $0.name == name } }

    func validate() throws(AuthoringError) {
        guard !definition.isEmpty else { throw .invalidGraph("\(id) has no definition") }
        // Inputs and outputs are separate namespaces: a connection always
        // reads an output and writes an input, so a constant node can call
        // both of its ports `value`.
        for (side, ports) in [("inputs", inputs), ("outputs", outputs)] {
            var seen: Set<String> = []
            for port in ports {
                guard GraphPort.isIdentifier(port.name) else {
                    throw .invalidGraph("\(id) port '\(port.name)' is not an identifier")
                }
                if case .custom(let name) = port.type, name.isEmpty {
                    throw .invalidGraph("\(id) port '\(port.name)' has an unnamed custom type")
                }
                guard seen.insert(port.name).inserted else {
                    throw .invalidGraph("\(id) has two \(side) named '\(port.name)'")
                }
            }
        }
        for (name, value) in values {
            guard let port = input(name) else { throw .invalidGraph("\(id) has a value for unknown input '\(name)'") }
            guard value.type == port.type else {
                throw .invalidGraph("\(id).\(name) holds a \(value.type) value for a \(port.type) input")
            }
            try value.validate()
        }
        guard position.x.isFinite, position.y.isFinite else {
            throw .invalidGraph("\(id) position must be finite")
        }
    }
}

/// One end of a connection.
public struct PortReference: Hashable, Codable, Sendable, CustomStringConvertible {
    public var node: GraphNodeID
    public var port: String

    public init(_ node: GraphNodeID, _ port: String) {
        self.node = node
        self.port = port
    }

    public var description: String { "\(node).\(port)" }
}

/// An edge from an output to an input. An input has at most one.
public struct GraphConnection: Hashable, Codable, Sendable {
    public var from: PortReference
    public var to: PortReference

    public init(from: PortReference, to: PortReference) {
        self.from = from
        self.to = to
    }
}

/// What a graph is for (spec §18). The framework is the same for all of them;
/// the domain tells editors and the evaluator which node set to offer.
public enum GraphDomain: String, Hashable, Codable, Sendable, CaseIterable {
    case geometry, material, animation, physics, particle, compute, logic, scene, audio, ai
}

/// A typed node graph (spec §18 `GraphDocument`).
public struct GraphDocument: Hashable, Codable, Sendable {
    public let id: GraphID
    public internal(set) var name: String
    public internal(set) var domain: GraphDomain
    public internal(set) var nodes: [GraphNodeID: GraphNode]
    /// Authored node order; evaluation and display follow it where the
    /// connections leave a choice.
    public internal(set) var order: [GraphNodeID]
    /// In the order they were made.
    public internal(set) var connections: [GraphConnection]
    var nextNodeRaw: UInt64

    public init(
        id: GraphID,
        name: String,
        domain: GraphDomain,
        nodes: [GraphNode] = [],
        connections: [GraphConnection] = [],
        nextNodeID: GraphNodeID? = nil
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.nodes = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.order = nodes.map(\.id)
        self.connections = Self.canonical(connections)
        self.nextNodeRaw = nextNodeID?.rawValue ?? ((nodes.map(\.id.rawValue).max() ?? 0) + 1)
    }

    /// The identifier the next added node receives.
    public var nextNodeID: GraphNodeID { GraphNodeID(rawValue: nextNodeRaw) }

    public func node(_ id: GraphNodeID) -> GraphNode? { nodes[id] }

    /// The connection feeding `input`, if any.
    public func connection(into input: PortReference) -> GraphConnection? {
        connections.first { $0.to == input }
    }

    /// Nodes in an order where every node comes after everything feeding it,
    /// ties broken by authored order. Throws on a cycle.
    public func topologicalOrder() throws(AuthoringError) -> [GraphNodeID] {
        var remaining = Dictionary(uniqueKeysWithValues: order.map { ($0, 0) })
        var dependents: [GraphNodeID: [GraphNodeID]] = [:]
        for connection in connections {
            remaining[connection.to.node, default: 0] += 1
            dependents[connection.from.node, default: []].append(connection.to.node)
        }
        var result: [GraphNodeID] = []
        var ready = order.filter { remaining[$0] == 0 }
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        while !ready.isEmpty {
            ready.sort { position[$0, default: 0] < position[$1, default: 0] }
            let next = ready.removeFirst()
            result.append(next)
            for dependent in dependents[next] ?? [] {
                remaining[dependent, default: 0] -= 1
                if remaining[dependent] == 0 { ready.append(dependent) }
            }
        }
        guard result.count == order.count else { throw .invalidGraph("\(id) contains a cycle") }
        return result
    }

    /// Checks every structural rule: node signatures and values, unique
    /// identifiers below the allocator, connections between existing ports of
    /// matching types, at most one connection per input, and no cycles.
    public func validate() throws(AuthoringError) {
        guard !name.isEmpty else { throw .invalidGraph("\(id) has no name") }
        guard Set(order) == Set(nodes.keys), order.count == nodes.count else {
            throw .invalidGraph("\(id) node order does not match its nodes")
        }
        for (key, node) in nodes {
            guard key == node.id else { throw .invalidGraph("\(id) stores \(node.id) under \(key)") }
            guard node.id.rawValue > 0, node.id.rawValue < nextNodeRaw else {
                throw .invalidGraph("\(node.id) was not allocated by \(id)")
            }
            try node.validate()
        }
        var fedInputs: Set<PortReference> = []
        for connection in connections {
            guard let source = nodes[connection.from.node]?.output(connection.from.port) else {
                throw .invalidGraph("\(id) connects from missing output \(connection.from)")
            }
            guard let target = nodes[connection.to.node]?.input(connection.to.port) else {
                throw .invalidGraph("\(id) connects to missing input \(connection.to)")
            }
            guard source.type.canConnect(to: target.type) else {
                throw .invalidGraph("\(connection.from) (\(source.type)) cannot feed \(connection.to) (\(target.type))")
            }
            guard fedInputs.insert(connection.to).inserted else {
                throw .invalidGraph("\(connection.to) has more than one connection")
            }
        }
        _ = try topologicalOrder()
    }
}

/// A graph's authored content without its node allocator, which keeps
/// advancing across undo just as the entity allocator does.
struct GraphContent: Hashable {
    var id: GraphID
    var name: String
    var domain: GraphDomain
    var nodes: [GraphNodeID: GraphNode]
    var order: [GraphNodeID]
    var connections: [GraphConnection]
}

extension GraphDocument {
    var contentKey: GraphContent {
        GraphContent(id: id, name: name, domain: domain, nodes: nodes, order: order, connections: connections)
    }
}
