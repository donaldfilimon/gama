import GamaAuthoring
import Testing

@Suite("Graphs in the document")
struct GraphTests {
    @Test func connectionsAreTypeCheckedAndRefusalsChangeNothing() throws {
        var scene = try SampleScene()
        let g = scene.graph
        try scene.session.execute(AddGraphNode(
            to: g, definition: "constant.color", inputs: [], outputs: [GraphPort("value", .color)]
        ))
        let color = GraphNodeID(rawValue: 4)
        let before = scene.session.document
        let refusals: [(any DocumentCommand, AuthoringError)] = [
            (ConnectPorts(PortReference(color, "value"), to: PortReference(scene.multiply, "a"), in: g),
             .invalidGraph("n4.value is color but n2.a takes float")),
            (ConnectPorts(PortReference(scene.multiply, "result"), to: PortReference(scene.constant, "value"), in: g),
             .invalidGraph("g1 contains a cycle")),
            (ConnectPorts(PortReference(scene.multiply, "result"), to: PortReference(scene.multiply, "b"), in: g),
             .invalidGraph("g1 contains a cycle")),
            (ConnectPorts(PortReference(scene.constant, "nope"), to: PortReference(scene.multiply, "b"), in: g),
             .invalidGraph("n1 has no output 'nope'")),
            (ConnectPorts(PortReference(GraphNodeID(rawValue: 99), "value"), to: PortReference(scene.multiply, "b"), in: g),
             .missingGraphNode(g, GraphNodeID(rawValue: 99))),
            (SetGraphValue(.color(SIMD4(1, 0, 0, 1)), for: "b", of: scene.multiply, in: g),
             .invalidGraph("n2.b takes float, not color")),
            (SetGraphValue(.float(.nan), for: "b", of: scene.multiply, in: g),
             .invalidGraph("graph values must be finite")),
            (DisconnectPorts(PortReference(scene.multiply, "b"), in: g), .invalidGraph("n2.b is not connected")),
            (AddGraphNode(to: g, definition: "x", inputs: [GraphPort("1bad", .float)], outputs: []),
             .invalidGraph("n5 port '1bad' is not an identifier")),
            (AddGraphNode(to: g, definition: "x", inputs: [GraphPort("a", .float), GraphPort("a", .color)], outputs: []),
             .invalidGraph("n5 has two inputs named 'a'")),
            (DeleteGraph(GraphID(rawValue: 42)), .missingGraph(GraphID(rawValue: 42))),
            (CreateGraph(name: "", domain: .material), .invalidGraph("a graph needs a name")),
            (AddGraphNode(to: g, definition: "x", inputs: [GraphPort("c", .custom(""))], outputs: []),
             .invalidGraph("n5 port 'c' has an unnamed custom type")),
        ]
        for (command, expected) in refusals {
            #expect(throws: expected) { try scene.session.execute(command) }
        }
        #expect(scene.session.document == before)
    }

    @Test func topologicalOrderFollowsConnectionsThenAuthoredOrder() throws {
        var scene = try SampleScene()
        let g = scene.graph
        // n3 feeds n1? n1 has no inputs; add a node that feeds nothing, then one fed by n2.
        try scene.session.execute(AddGraphNode(
            to: g, definition: "math.add", inputs: [GraphPort("a", .float)], outputs: [GraphPort("r", .float)]
        ))
        try scene.session.execute(ConnectPorts(PortReference(scene.multiply, "result"), to: PortReference(GraphNodeID(rawValue: 4), "a"), in: g))
        let order = try #require(scene.session.document.graph(g)).topologicalOrder()
        #expect(order.map(\.rawValue) == [1, 2, 3, 4])
    }

    @Test func deletingATargetedEntityIsAllowed() throws {
        var scene = try SampleScene()
        try scene.session.execute(AddGraphNode(
            to: scene.graph, definition: "output.material", inputs: [GraphPort("target", .entity)], outputs: [],
            values: ["target": .entity(scene.body)]
        ))
        try scene.session.execute(DeleteEntity(scene.body))
        #expect(!scene.session.document.contains(scene.body))
        try scene.session.document.validate()
    }

    @Test func graphEditsReportGraphChangedOnly() throws {
        var scene = try SampleScene()
        let changes = try scene.session.execute(SetGraphValue(.float(1), for: "b", of: scene.multiply, in: scene.graph))
        #expect(changes == [.graphChanged(scene.graph)])
    }

    @Test func exhaustedAllocatorsRefuseInsteadOfTrapping() throws {
        let full = GraphDocument(id: GraphID(rawValue: 1), name: "Full", domain: .logic, nextNodeID: GraphNodeID(rawValue: .max))
        var session = EditorSession(document: try SceneDocument(
            restoring: [], roots: [], nextEntityID: EntityID(rawValue: 1), graphs: [full]
        ))
        #expect(throws: AuthoringError.invalidGraph("g1 has no node identifiers left")) {
            try session.execute(AddGraphNode(to: full.id, definition: "x", inputs: [], outputs: []))
        }
        var noGraphs = EditorSession(document: try SceneDocument(
            restoring: [], roots: [], nextEntityID: EntityID(rawValue: 1), nextGraphID: GraphID(rawValue: .max)
        ))
        #expect(throws: AuthoringError.invalidGraph("no graph identifiers left")) {
            try noGraphs.execute(CreateGraph(name: "X", domain: .logic))
        }
    }

    @Test func portTypesRoundTripTheirSpelling() {
        for type in PortType.builtIn + [.custom("noise")] {
            #expect(PortType(type.description) == type)
        }
        #expect(PortType("custom:") == nil)
        #expect(PortType("quaternion") == nil)
    }
}
