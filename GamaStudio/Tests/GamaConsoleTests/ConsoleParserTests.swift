import GamaAuthoring
import GamaConsole
import Testing

/// `World > [Box, Sphere, "Key Light"]`, plus a root `Box` duplicate name
/// under `Other` and an entity literally named `2`.
struct ConsoleScene {
    var session = EditorSession()
    let world: EntityID, box: EntityID, sphere: EntityID, lamp: EntityID, cam: EntityID
    let other: EntityID, otherBox: EntityID, two: EntityID

    init() throws {
        func add(_ s: inout EditorSession, _ name: String, _ parent: EntityID? = nil, _ c: [Component] = []) throws -> EntityID {
            let id = s.document.nextEntityID
            try s.execute(CreateEntity(name: name, parent: parent, components: c))
            return id
        }
        var s = EditorSession()
        world = try add(&s, "World", nil, [.transform(.identity)])
        box = try add(&s, "Box", world, [.transform(Transform(position: SIMD3(1, 0, 0))), .mesh(.box), .material(Material())])
        sphere = try add(&s, "Sphere", world, [.mesh(.sphere)])
        lamp = try add(&s, "Key Light", world, [.light(.defaultPoint)])
        cam = try add(&s, "Cam", nil, [.camera(.default)])
        other = try add(&s, "Other")
        otherBox = try add(&s, "box", other, [.mesh(.box)])
        two = try add(&s, "2")
        session = s
    }

    var parser: ConsoleParser { ConsoleParser(document: session.document, selection: session.selection) }

    /// Runs an `.edit` the way StudioModel does: one command through
    /// `execute`, several through one transaction.
    mutating func run(_ line: String) throws {
        guard case .edit(let label, let commands) = try parser.parse(line) else {
            Issue.record("'\(line)' did not parse to an edit")
            return
        }
        if commands.count == 1 {
            try session.execute(commands[0])
        } else {
            try session.transaction(label, commands)
        }
    }
}

@Suite("Console parser")
struct ConsoleParserTests {
    /// The console and a panel produce the same command: same resulting
    /// document, same undo label.
    @Test(arguments: [
        ("move sphere 0 1 0", "sphere-move"),
        ("position #2 3 4 5", "box-position"),
        ("rename sphere to Ball", "rename"),
        ("metallic sphere 0.8", "metallic"),
        ("hide sphere", "hide"),
        ("delete sphere", "delete"),
        ("duplicate sphere", "duplicate"),
        ("parent sphere to Cam", "parent"),
    ])
    func consoleEditsMatchTheDirectCommand(_ line: String, _ tag: String) throws {
        var viaConsole = try ConsoleScene()
        var direct = viaConsole
        try viaConsole.run(line)
        let s = direct.sphere
        let command: any DocumentCommand = switch tag {
        case "sphere-move": SetComponent(s, .transform(Transform(position: SIMD3(0, 1, 0))))
        case "box-position": SetComponent(direct.box, .transform(Transform(position: SIMD3(3, 4, 5))))
        case "rename": RenameEntity(s, to: "Ball")
        case "metallic": SetComponent(s, .material(Material(metallic: 0.8)))
        case "hide": SetComponent(s, .visibility(Visibility(visible: false)))
        case "delete": DeleteEntity(s)
        case "duplicate": DuplicateEntity(s)
        default: ReparentEntity(s, to: direct.cam)
        }
        try direct.session.execute(command)
        #expect(viaConsole.session.document == direct.session.document, "\(line)")
        #expect(viaConsole.session.undoLabel == direct.session.undoLabel, "\(line)")
    }

    @Test func omittedTargetMeansTheSelectionAndSeveralTargetsAreOneStep() throws {
        var scene = try ConsoleScene()
        try scene.session.select([scene.box, scene.sphere])
        try scene.run("move 0 2 0")
        let doc = scene.session.document
        #expect(doc.component(.transform, of: scene.box) == .transform(Transform(position: SIMD3(1, 2, 0))))
        #expect(doc.component(.transform, of: scene.sphere) == .transform(Transform(position: SIMD3(0, 2, 0))))
        #expect(scene.session.undoLabel == "Move 2 Entities")
        try scene.session.undo()
        #expect(scene.session.document.component(.transform, of: scene.sphere) == nil, "one undo reverts both")
    }

    @Test func targetsResolveBySelectedIdNameAndQuotes() throws {
        var scene = try ConsoleScene()
        let p = scene.parser
        #expect(try p.resolve(ConsoleWord("#3")) == [scene.sphere])
        #expect(try p.resolve(ConsoleWord("SPHERE")) == [scene.sphere])
        #expect(try p.resolve(ConsoleWord("Key Light", quoted: true)) == [scene.lamp])
        #expect(throws: ConsoleError("'box' is ambiguous (#2 Box, #7 box); use #<id>")) { try p.resolve(ConsoleWord("box")) }
        #expect(throws: ConsoleError("no entity named 'ghost'")) { try p.resolve(ConsoleWord("ghost")) }
        #expect(throws: ConsoleError("no entity #99")) { try p.resolve(ConsoleWord("#99")) }
        #expect(throws: ConsoleError("nothing is selected; name a target or select one first")) {
            try p.resolve(ConsoleWord("selected"))
        }
        // A quoted number is a name, so `"2"` targets the entity called 2.
        try scene.run("move \"2\" 1 0 0")
        #expect(scene.session.document.component(.transform, of: scene.two) == .transform(Transform(position: SIMD3(1, 0, 0))))
        // Quoted names with spaces.
        try scene.run("intensity \"Key Light\" 500")
        guard case .light(let light)? = scene.session.document.component(.light, of: scene.lamp) else {
            Issue.record("light missing"); return
        }
        #expect(light.intensity == 500)
    }

    @Test func editorIntentsParse() throws {
        let p = try ConsoleScene().parser
        guard case .addPrimitive(.sphere) = try p.parse("add sphere") else { Issue.record("add sphere"); return }
        guard case .addPrimitive(.box) = try p.parse("ADD Cube") else { Issue.record("add cube"); return }
        guard case .addLight(.directional) = try p.parse("add light directional") else { Issue.record("light"); return }
        guard case .addLight(.spot) = try p.parse("add light spot") else { Issue.record("spot"); return }
        guard case .addLight(.point) = try p.parse("add light") else { Issue.record("point"); return }
        guard case .addCamera = try p.parse("add camera") else { Issue.record("camera"); return }
        guard case .undo = try p.parse("undo"), case .redo = try p.parse("redo") else { Issue.record("history"); return }
        guard case .select(let none) = try p.parse("select none"), none.isEmpty else { Issue.record("none"); return }
        guard case .select(let all) = try p.parse("select all"), all.count == 8 else { Issue.record("all"); return }
        guard case .help(let text) = try p.parse("help move"), text.hasPrefix("move [target]") else { Issue.record("help"); return }
    }

    @Test func malformedLinesExplainThemselves() throws {
        let p = try ConsoleScene().parser
        let cases: [(String, String)] = [
            ("", "empty command"),
            ("fly sphere", "unknown command 'fly'; type 'help' for the list"),
            ("move sphere 1 2", "usage: move [target] <dx> <dy> <dz>   (relative, meters)"),
            ("move sphere 1 two 3", "'two' is not a number; usage: move [target] <dx> <dy> <dz>   (relative, meters)"),
            ("move sphere 1 nan 3", "'nan' is not a number; usage: move [target] <dx> <dy> <dz>   (relative, meters)"),
            ("add teapot", "cannot add 'teapot'; use box, sphere, cylinder, cone, plane, light, or camera"),
            ("add light laser", "unknown light kind 'laser'; use directional, point, or spot"),
            ("intensity sphere 5", "#3 Sphere has no light"),
            ("fov sphere 50", "#3 Sphere has no camera"),
            ("undo now", "'undo' takes no arguments"),
            ("rename \"open", "unterminated quote"),
            ("move 1 0 0", "nothing is selected; name a target or select one first"),
        ]
        for (line, message) in cases {
            #expect(throws: ConsoleError(message), "\(line)") { try p.parse(line) }
        }
    }

    /// Parsing accepts a value the session will refuse; the session is the
    /// validator, so a refused console edit changes nothing.
    @Test func invalidValuesAreRefusedByTheSessionNotSilentlyClamped() throws {
        var scene = try ConsoleScene()
        let before = scene.session.document
        #expect(throws: AuthoringError.self) { try scene.run("metallic sphere 3") }
        #expect(throws: AuthoringError.self) { try scene.run("scale sphere 0") }
        #expect(throws: AuthoringError.self) { try scene.run("parent World to #2") }
        #expect(scene.session.document == before)
    }

    @Test func deletingAParentAndItsChildIsOneStepThatSucceeds() throws {
        var scene = try ConsoleScene()
        try scene.session.select([scene.box, scene.world])
        try scene.run("delete")
        #expect(!scene.session.document.contains(scene.world))
        #expect(!scene.session.document.contains(scene.box))
        try scene.session.undo()
        #expect(scene.session.document.contains(scene.box))
    }

    @Test func tokenizerGroupsQuotesAndEscapes() throws {
        #expect(try ConsoleParser.tokenize("  rename   \"a \\\"b\\\" c\"  ") == [
            ConsoleWord("rename"), ConsoleWord("a \"b\" c", quoted: true),
        ])
        #expect(try ConsoleParser.tokenize("select \"\"") == [ConsoleWord("select"), ConsoleWord("", quoted: true)])
    }
}
