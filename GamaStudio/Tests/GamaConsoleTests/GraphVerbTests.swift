import GamaAuthoring
import GamaConsole
import GamaGraph
import Testing

@Suite("Console graph verbs")
struct GraphVerbTests {
    /// A document with one box and one material graph holding a mix node.
    struct Bench {
        var session = EditorSession()
        let box: EntityID
        let graph: GraphID
        let mix: GraphNodeID

        init() throws {
            box = session.document.nextEntityID
            try session.execute(CreateEntity(name: "Box", components: [.mesh(.box)]))
            graph = session.document.nextGraphID
            try session.execute(CreateGraph(name: "Rust", domain: .material))
            mix = GraphNodeID(rawValue: 1)
            try session.execute(try #require(NodeRegistry.standard.definition("color.mix")).addCommand(to: graph))
        }

        var parser: ConsoleParser { ConsoleParser(document: session.document, selection: session.selection) }

        /// Runs a `.graphEdit` the way StudioModel does: with evaluation.
        mutating func run(_ line: String) throws {
            switch try parser.parse(line) {
            case .graphEdit(let graph, let label, let commands):
                try session.transaction(label, commands + [EvaluateGraph(graph)])
            case .edit(let label, let commands):
                try session.transaction(label, commands)
            default:
                Issue.record("'\(line)' is not an edit")
            }
        }
    }

    @Test func buildsAMaterialGraphThatDrivesTheScene() throws {
        var bench = try Bench()
        try bench.run("graph add rust output.material")
        try bench.run("graph connect g1 n1.color n2.base_color")
        try bench.run("graph set Rust n1.b 1 0 0")
        try bench.run("graph set g1 n1.t 1")
        try bench.run("graph set g1 n2.metallic 0.7")
        #expect(bench.session.document.component(.material, of: bench.box) == nil, "no target yet")
        try bench.run("graph set g1 n2.target box")
        #expect(bench.session.document.component(.material, of: bench.box)
            == .material(Material(baseColor: SIMD4(1, 0, 0, 1), metallic: 0.7, roughness: 0.5)))
        try bench.session.undo()
        #expect(bench.session.document.component(.material, of: bench.box) == nil, "undo takes the effect with it")
    }

    @Test func graphCommandsParseToTheDirectCommands() throws {
        let bench = try Bench()
        let p = bench.parser
        guard case .createGraph(let name, .scene) = try p.parse("graph new Lift scene"), name == "Lift" else {
            Issue.record("new"); return
        }
        guard case .graphEdit(let g, "Add Add", let add) = try p.parse("graph add g1 math.add"),
              g == bench.graph, add.first is AddGraphNode else { Issue.record("add"); return }
        guard case .edit("Delete Graph", let delete) = try p.parse("graph delete rust"), delete.first is DeleteGraph else {
            Issue.record("delete"); return
        }
        guard case .help(let show) = try p.parse("graph show g1"), show.contains("n1 color.mix [a=(0, 0, 0, 1), b=(1, 1, 1, 1), t=0.5] → color") else {
            Issue.record("show"); return
        }
        guard case .help(let list) = try p.parse("graph list"), list == "g1 Rust (material, 1 nodes)" else { Issue.record("list"); return }
        guard case .help(let nodes) = try p.parse("graph nodes scene"), nodes.contains("output.transform") else { Issue.record("nodes"); return }
    }

    @Test func graphErrorsExplainThemselves() throws {
        let p = try Bench().parser
        let cases: [(String, String)] = [
            ("graph fly", "unknown graph command 'fly'; type 'graph' for the list"),
            ("graph new X", "usage: graph new <name> <domain>; domains: geometry, material, animation, physics, particle, compute, logic, scene, audio, ai"),
            ("graph add g9 math.add", "no graph g9"),
            ("graph add g1 math.teleport", "unknown node type 'math.teleport'; graph nodes material lists them"),
            ("graph add g1 output.transform", "output.transform is not offered in material graphs"),
            ("graph remove g1 n7", "g1 has no node n7"),
            ("graph connect g1 n1 n1.a", "'n1' is not a port; use n<id>.<port>"),
            ("graph set g1 n1.t hot", "'hot' is not a number"),
            ("graph set g1 n1.b 1 0", "color takes 3 or 4 numbers"),
            ("graph set g1 n1.zz 1", "n1 has no input 'zz'"),
        ]
        for (line, message) in cases {
            #expect(throws: ConsoleError(message), "\(line)") { try p.parse(line) }
        }
    }

    @Test func typeMismatchesAreRefusedByTheSession() throws {
        var bench = try Bench()
        try bench.run("graph add g1 math.add")
        let before = bench.session.document
        #expect(throws: AuthoringError.invalidGraph("n1.color is color but n2.a takes float")) {
            try bench.run("graph connect g1 n1.color n2.a")
        }
        #expect(bench.session.document == before)
    }
}
