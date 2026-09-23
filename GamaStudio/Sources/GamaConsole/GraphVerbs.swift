public import GamaAuthoring
import GamaGraph

/// The `graph` verb family (ADR 0007). Graph references are `g<id>` or a
/// graph name; node references are `n<id>`; ports are `n<id>.<port>`.
extension ConsoleParser {
    static let graphUsage = [
        "graph new <name> <domain>",
        "graph list | graph show <graph> | graph nodes <domain>",
        "graph add <graph> <node type>",
        "graph remove <graph> n<id>",
        "graph connect <graph> n<id>.<output> n<id>.<input>",
        "graph disconnect <graph> n<id>.<input>",
        "graph set <graph> n<id>.<input> <value…>   (number, x y z, r g b [a], true|false, text, or an entity target)",
        "graph rename <graph> to <name> | graph delete <graph> | graph apply <graph>",
    ]

    func graph(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        guard let sub = words.first?.keyword else {
            return .help(Self.graphUsage.joined(separator: "\n"))
        }
        let rest = Array(words.dropFirst())
        switch sub {
        case "new", "create":
            guard rest.count == 2, let domain = GraphDomain(rawValue: rest[1].text.lowercased()) else {
                let domains = GraphDomain.allCases.map(\.rawValue).joined(separator: ", ")
                throw ConsoleError("usage: graph new <name> <domain>; domains: \(domains)")
            }
            return .createGraph(name: rest[0].text, domain: domain)
        case "list":
            let lines = document.graphOrder.compactMap(document.graph).map {
                "\($0.id) \($0.name) (\($0.domain.rawValue), \($0.nodes.count) nodes)"
            }
            return .help(lines.isEmpty ? "no graphs; graph new <name> <domain>" : lines.joined(separator: "\n"))
        case "nodes":
            guard rest.count == 1, let domain = GraphDomain(rawValue: rest[0].text.lowercased()) else {
                throw ConsoleError("usage: graph nodes <domain>")
            }
            return .help(registry.offered(in: domain).map { "\($0.id) (\($0.title))" }.joined(separator: ", "))
        case "show":
            let graph = try graphTarget(rest, count: 1)
            return .help(Self.describe(graph))
        case "add":
            let graph = try graphTarget(rest, count: 2)
            let type = rest[1].text
            guard let definition = registry.definition(type) else {
                throw ConsoleError("unknown node type '\(type)'; graph nodes \(graph.domain.rawValue) lists them")
            }
            guard definition.isOffered(in: graph.domain) else {
                throw ConsoleError("\(type) is not offered in \(graph.domain.rawValue) graphs")
            }
            let position = SIMD2<Float>(Float(graph.nodes.count) * 4, 0)
            return .graphEdit(graph.id, label: "Add \(definition.title)", commands: [definition.addCommand(to: graph.id, at: position)])
        case "remove":
            let graph = try graphTarget(rest, count: 2)
            let node = try nodeReference(rest[1].text, in: graph)
            return .graphEdit(graph.id, label: "Remove Node", commands: [RemoveGraphNode(node, from: graph.id)])
        case "connect":
            let graph = try graphTarget(rest, count: 3)
            let from = try portReference(rest[1].text, in: graph)
            let to = try portReference(rest[2].text, in: graph)
            return .graphEdit(graph.id, label: "Connect", commands: [ConnectPorts(from, to: to, in: graph.id)])
        case "disconnect":
            let graph = try graphTarget(rest, count: 2)
            let input = try portReference(rest[1].text, in: graph)
            return .graphEdit(graph.id, label: "Disconnect", commands: [DisconnectPorts(input, in: graph.id)])
        case "set":
            guard rest.count >= 3 else { throw ConsoleError("usage: \(Self.graphUsage[6])") }
            let graph = try graphTarget(Array(rest.prefix(2)), count: 2)
            let input = try portReference(rest[1].text, in: graph)
            guard let port = graph.node(input.node)?.input(input.port) else {
                throw ConsoleError("\(input.node) has no input '\(input.port)'")
            }
            let value = try graphValue(Array(rest.dropFirst(2)), for: port.type)
            return .graphEdit(graph.id, label: "Set \(input.port)", commands: [SetGraphValue(value, for: input.port, of: input.node, in: graph.id)])
        case "rename":
            guard rest.count >= 3, rest[1].keyword == "to" else { throw ConsoleError("usage: graph rename <graph> to <name>") }
            let graph = try graphTarget([rest[0]], count: 1)
            let name = rest.dropFirst(2).map(\.text).joined(separator: " ")
            return .edit(label: "Rename Graph", commands: [RenameGraph(graph.id, to: name)])
        case "delete":
            let graph = try graphTarget(rest, count: 1)
            return .edit(label: "Delete Graph", commands: [DeleteGraph(graph.id)])
        case "apply":
            let graph = try graphTarget(rest, count: 1)
            return .edit(label: "Evaluate Graph", commands: [EvaluateGraph(graph.id, evaluator: GraphEvaluator(registry: registry))])
        default:
            throw ConsoleError("unknown graph command '\(sub)'; type 'graph' for the list")
        }
    }

    // MARK: References

    /// The graph named by the first word, after checking the word count.
    func graphTarget(_ words: [ConsoleWord], count: Int) throws(ConsoleError) -> GraphDocument {
        guard words.count == count, let first = words.first else {
            throw ConsoleError("usage: type 'graph' for the graph commands")
        }
        return try resolveGraph(first)
    }

    /// `g<id>` or a case-insensitive graph name.
    public func resolveGraph(_ word: ConsoleWord) throws(ConsoleError) -> GraphDocument {
        if !word.quoted, word.text.hasPrefix("g"), let raw = UInt64(word.text.dropFirst()) {
            guard let graph = document.graph(GraphID(rawValue: raw)) else { throw ConsoleError("no graph \(word.text)") }
            return graph
        }
        let lowered = word.text.lowercased()
        let matches = document.graphOrder.compactMap(document.graph).filter { $0.name.lowercased() == lowered }
        switch matches.count {
        case 0: throw ConsoleError("no graph named '\(word.text)'")
        case 1: return matches[0]
        default:
            throw ConsoleError("'\(word.text)' names \(matches.count) graphs (\(matches.map(\.id.description).joined(separator: ", "))); use g<id>")
        }
    }

    func nodeReference(_ text: String, in graph: GraphDocument) throws(ConsoleError) -> GraphNodeID {
        guard text.hasPrefix("n"), let raw = UInt64(text.dropFirst()) else {
            throw ConsoleError("'\(text)' is not a node; use n<id>")
        }
        let id = GraphNodeID(rawValue: raw)
        guard graph.node(id) != nil else { throw ConsoleError("\(graph.id) has no node \(id)") }
        return id
    }

    func portReference(_ text: String, in graph: GraphDocument) throws(ConsoleError) -> PortReference {
        guard let dot = text.firstIndex(of: ".") else {
            throw ConsoleError("'\(text)' is not a port; use n<id>.<port>")
        }
        let node = try nodeReference(String(text[..<dot]), in: graph)
        return PortReference(node, String(text[text.index(after: dot)...]))
    }

    // MARK: Values

    func graphValue(_ words: [ConsoleWord], for type: PortType) throws(ConsoleError) -> GraphValue {
        func numbers(_ count: ClosedRange<Int>) throws(ConsoleError) -> [Float] {
            guard count.contains(words.count) else { throw ConsoleError("\(type) takes \(count.lowerBound == count.upperBound ? "\(count.lowerBound)" : "\(count.lowerBound) or \(count.upperBound)") numbers") }
            var result: [Float] = []
            for word in words {
                guard !word.quoted, let value = Self.number(word.text) else {
                    throw ConsoleError("'\(word.text)' is not a number")
                }
                result.append(value)
            }
            return result
        }
        switch type {
        case .float: return .float(try numbers(1...1)[0])
        case .vector2: let v = try numbers(2...2); return .vector2(SIMD2(v[0], v[1]))
        case .vector3: let v = try numbers(3...3); return .vector3(SIMD3(v[0], v[1], v[2]))
        case .vector4: let v = try numbers(4...4); return .vector4(SIMD4(v[0], v[1], v[2], v[3]))
        case .color: let v = try numbers(3...4); return .color(SIMD4(v[0], v[1], v[2], v.count == 4 ? v[3] : 1))
        case .boolean:
            switch words.count == 1 ? words[0].keyword : nil {
            case "true"?, "yes"?, "on"?, "1"?: return .boolean(true)
            case "false"?, "no"?, "off"?, "0"?: return .boolean(false)
            default: throw ConsoleError("boolean takes true or false")
            }
        case .integer:
            guard words.count == 1, let value = Int64(words[0].text) else { throw ConsoleError("integer takes one whole number") }
            return .integer(value)
        case .string: return .string(words.map(\.text).joined(separator: " "))
        case .entity:
            guard words.count == 1 else { throw ConsoleError("an entity input takes one target, or none") }
            if words[0].keyword == "none" { return .entity(nil) }
            let targets = try resolve(words[0])
            guard targets.count == 1 else { throw ConsoleError("an entity input takes exactly one entity") }
            return .entity(targets[0])
        case .transform, .material, .texture, .mesh, .execution, .custom:
            throw ConsoleError("\(type) inputs cannot be typed in; connect them instead")
        }
    }

    // MARK: Description

    static func describe(_ graph: GraphDocument) -> String {
        var lines = ["\(graph.id) \(graph.name) (\(graph.domain.rawValue))"]
        for id in graph.order {
            guard let node = graph.node(id) else { continue }
            let inputs = node.inputs.map { port -> String in
                if let link = graph.connection(into: PortReference(id, port.name)) {
                    return "\(port.name)←\(link.from)"
                }
                if let value = node.values[port.name] { return "\(port.name)=\(format(value))" }
                return "\(port.name)=?"
            }
            let outputs = node.outputs.map(\.name)
            var line = "  \(id) \(node.definition)"
            if !inputs.isEmpty { line += " [\(inputs.joined(separator: ", "))]" }
            if !outputs.isEmpty { line += " → \(outputs.joined(separator: ", "))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Short text for a constant, as the editor and console show it.
    public static func format(_ value: GraphValue) -> String {
        func n(_ v: Float) -> String {
            let text = v.description
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        switch value {
        case .float(let v): return n(v)
        case .vector2(let v): return "(\(n(v.x)), \(n(v.y)))"
        case .vector3(let v): return "(\(n(v.x)), \(n(v.y)), \(n(v.z)))"
        case .vector4(let v), .color(let v): return "(\(n(v.x)), \(n(v.y)), \(n(v.z)), \(n(v.w)))"
        case .boolean(let v): return v ? "true" : "false"
        case .integer(let v): return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .entity(let v): return v.map { "\($0)" } ?? "none"
        case .transform: return "transform"
        case .material: return "material"
        }
    }
}
