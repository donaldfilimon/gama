import GamaAuthoring
import GamaGraph
import Testing

/// A session with one box, plus helpers that build graphs from the standard
/// registry the way an editor does.
struct GraphBench {
    var session = EditorSession()
    let box: EntityID
    let registry = NodeRegistry.standard

    init() throws {
        box = session.document.nextEntityID
        try session.execute(CreateEntity(name: "Box", components: [
            .transform(Transform(position: SIMD3(1, 2, 3), rotation: Rotation(x: 0, y: 0.38268343, z: 0, w: 0.9238795))),
            .mesh(.box),
        ]))
    }

    mutating func graph(_ name: String, _ domain: GraphDomain) throws -> GraphID {
        let id = session.document.nextGraphID
        try session.execute(CreateGraph(name: name, domain: domain))
        return id
    }

    mutating func node(_ definition: String, in graph: GraphID) throws -> GraphNodeID {
        let id = try #require(session.document.graph(graph)).nextNodeID
        try session.execute(try #require(registry.definition(definition)).addCommand(to: graph))
        return id
    }

    mutating func connect(_ from: GraphNodeID, _ out: String, _ to: GraphNodeID, _ input: String, in graph: GraphID) throws {
        try session.execute(ConnectPorts(PortReference(from, out), to: PortReference(to, input), in: graph))
    }

    mutating func set(_ value: GraphValue, _ input: String, of node: GraphNodeID, in graph: GraphID) throws {
        try session.execute(SetGraphValue(value, for: input, of: node, in: graph))
    }

    /// Runs `edit` and the graph's evaluation as one step, as the editor does.
    mutating func live(_ edit: any DocumentCommand, _ graph: GraphID) throws {
        try session.transaction(edit.label, [edit, EvaluateGraph(graph)])
    }
}

@Suite("Graph evaluation")
struct GraphEvaluatorTests {
    @Test func materialGraphWritesTheMaterialAndUndoesAsOneStep() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Rust", .material)
        let mix = try bench.node("color.mix", in: g)
        let times = try bench.node("math.multiply", in: g)
        let output = try bench.node("output.material", in: g)
        try bench.set(.color(SIMD4(1, 0, 0, 1)), "b", of: mix, in: g)
        try bench.set(.float(0.25), "t", of: mix, in: g)
        try bench.set(.float(0.4), "a", of: times, in: g)
        try bench.set(.float(2), "b", of: times, in: g)
        try bench.connect(mix, "color", output, "base_color", in: g)
        try bench.connect(times, "result", output, "metallic", in: g)
        #expect(bench.session.document.component(.material, of: bench.box) == nil, "no evaluation yet")

        let before = bench.session.document
        try bench.live(SetGraphValue(.entity(bench.box), for: "target", of: output, in: g), g)
        let expected = Material(baseColor: SIMD4(0.25, 0, 0, 1), metallic: 0.8, roughness: 0.5)
        #expect(bench.session.document.component(.material, of: bench.box) == .material(expected))
        #expect(bench.session.undoLabel == "Set target")

        try bench.session.undo()
        #expect(bench.session.document == before, "graph edit and its scene effect undo together")
        try bench.session.redo()
        #expect(bench.session.document.component(.material, of: bench.box) == .material(expected))
    }

    @Test func transformGraphMovesAndScalesButKeepsRotation() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Lift", .scene)
        let compose = try bench.node("vector3.compose", in: g)
        let output = try bench.node("output.transform", in: g)
        try bench.set(.float(5), "y", of: compose, in: g)
        try bench.connect(compose, "vector", output, "position", in: g)
        try bench.set(.vector3(SIMD3(2, 2, 2)), "scale", of: output, in: g)
        try bench.live(SetGraphValue(.entity(bench.box), for: "target", of: output, in: g), g)
        guard case .transform(let t)? = bench.session.document.component(.transform, of: bench.box) else {
            Issue.record("transform missing"); return
        }
        #expect(t.position == SIMD3(0, 5, 0))
        #expect(t.scale == SIMD3(2, 2, 2))
        #expect(t.rotation == Rotation(x: 0, y: 0.38268343, z: 0, w: 0.9238795))
    }

    @Test func materialChannelsSaturate() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Hot", .material)
        let output = try bench.node("output.material", in: g)
        try bench.set(.float(3), "roughness", of: output, in: g)
        try bench.set(.color(SIMD4(2, -1, 0.5, 1)), "base_color", of: output, in: g)
        try bench.live(SetGraphValue(.entity(bench.box), for: "target", of: output, in: g), g)
        #expect(bench.session.document.component(.material, of: bench.box)
            == .material(Material(baseColor: SIMD4(1, 0, 0.5, 1), metallic: 0, roughness: 1)))
    }

    @Test func unsetOrDeletedTargetsAreInert() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Idle", .material)
        let output = try bench.node("output.material", in: g)
        let evaluator = GraphEvaluator()
        let graph = try #require(bench.session.document.graph(g))
        #expect(try evaluator.commands(for: graph, in: bench.session.document).isEmpty)

        try bench.set(.entity(bench.box), "target", of: output, in: g)
        try bench.session.execute(DeleteEntity(bench.box))
        let after = try #require(bench.session.document.graph(g))
        #expect(try evaluator.commands(for: after, in: bench.session.document).isEmpty)
        // And a live edit on such a graph succeeds and changes only the graph.
        try bench.live(SetGraphValue(.float(0.3), for: "metallic", of: output, in: g), g)
    }

    @Test func evaluationErrorsFeedingAnOutputRefuseTheWholeEdit() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Bad", .material)
        let divide = try bench.node("math.divide", in: g)
        let output = try bench.node("output.material", in: g)
        try bench.set(.entity(bench.box), "target", of: output, in: g)
        try bench.connect(divide, "result", output, "metallic", in: g)
        let before = bench.session.document
        #expect(throws: AuthoringError.invalidGraph("g1 evaluation failed: n1: division by zero")) {
            try bench.live(SetGraphValue(.float(0), for: "b", of: divide, in: g), g)
        }
        #expect(bench.session.document == before)
    }

    /// Only outputs and what feeds them are evaluated for scene edits, so a
    /// broken scratch node does not block the rest of the graph.
    @Test func brokenNodesThatFeedNoOutputDoNotBlockEdits() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Scratch", .material)
        let divide = try bench.node("math.divide", in: g)
        try bench.set(.float(0), "b", of: divide, in: g)
        try bench.session.execute(AddGraphNode(to: g, definition: "plugin.unknown", inputs: [], outputs: []))
        let output = try bench.node("output.material", in: g)
        try bench.live(SetGraphValue(.entity(bench.box), for: "target", of: output, in: g), g)
        #expect(bench.session.document.component(.material, of: bench.box) != nil)
        // A full evaluation (for display) still reports them.
        #expect(throws: GraphError.self) { try GraphEvaluator().evaluate(try #require(bench.session.document.graph(g))) }
    }

    @Test func clearedInputsFallBackToTheirDefault() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Defaults", .material)
        let output = try bench.node("output.material", in: g)
        try bench.set(.entity(bench.box), "target", of: output, in: g)
        try bench.live(SetGraphValue(nil, for: "roughness", of: output, in: g), g)
        guard case .material(let material)? = bench.session.document.component(.material, of: bench.box) else {
            Issue.record("material missing"); return
        }
        #expect(material.roughness == 0.5, "the definition's default")
    }

    @Test func unknownAndChangedDefinitionsAreReported() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Odd", .logic)
        try bench.session.execute(AddGraphNode(to: g, definition: "plugin.warp", inputs: [], outputs: []))
        try bench.session.execute(AddGraphNode(
            to: g, definition: "math.add", inputs: [GraphPort("a", .float)], outputs: [GraphPort("result", .float)],
            values: ["a": .float(1)]
        ))
        let graph = try #require(bench.session.document.graph(g))
        #expect(throws: GraphError.unknownDefinition(GraphNodeID(rawValue: 1), "plugin.warp")) {
            try GraphEvaluator().evaluate(graph)
        }
        var registry = NodeRegistry.standard
        registry.register(NodeDefinition(
            id: "plugin.warp", title: "Warp", category: "Plugin", inputs: [], outputs: [], defaults: [:]
        ))
        #expect(throws: GraphError.signatureMismatch(GraphNodeID(rawValue: 2), "math.add")) {
            try GraphEvaluator(registry: registry).evaluate(graph)
        }
    }

    @Test func valuesFlowAlongConnectionsInDependencyOrder() throws {
        var bench = try GraphBench()
        let g = try bench.graph("Chain", .logic)
        let add = try bench.node("math.add", in: g)        // added first, evaluated last
        let constant = try bench.node("constant.float", in: g)
        try bench.set(.float(4), "value", of: constant, in: g)
        try bench.set(.float(1.5), "b", of: add, in: g)
        try bench.connect(constant, "value", add, "a", in: g)
        let result = try GraphEvaluator().evaluate(try #require(bench.session.document.graph(g)))
        #expect(result.outputs[PortReference(add, "result")] == .float(5.5))
        #expect(result.inputs[PortReference(add, "a")] == .float(4))
    }

    /// Every standard node can be added and evaluated as-is.
    @Test func everyStandardNodeEvaluatesWithItsDefaults() throws {
        for definition in NodeRegistry.standard.definitions {
            var bench = try GraphBench()
            let g = try bench.graph("T", definition.isOffered(in: .material) ? .material : .scene)
            let node = try bench.node(definition.id, in: g)
            for port in definition.inputs {
                #expect(definition.defaults[port.name]?.type == port.type, "\(definition.id).\(port.name)")
            }
            let result = try GraphEvaluator().evaluate(try #require(bench.session.document.graph(g)))
            for port in definition.outputs {
                #expect(result.outputs[PortReference(node, port.name)]?.type == port.type, "\(definition.id)")
            }
        }
    }

    @Test func domainsOfferTheirOutputs() {
        let material = NodeRegistry.standard.offered(in: .material).map(\.id)
        let scene = NodeRegistry.standard.offered(in: .scene).map(\.id)
        #expect(material.contains("output.material") && !material.contains("output.transform"))
        #expect(scene.contains("output.transform") && !scene.contains("output.material"))
        #expect(material.contains("math.add") && scene.contains("math.add"))
    }
}
