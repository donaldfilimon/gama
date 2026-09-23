import GamaAuthoring
import Testing

/// Every command must satisfy: execute, then undo, restores the authored
/// content exactly; redo then restores the executed state exactly.
@Suite("Command round trips")
struct CommandRoundTripTests {
    static let cases: [(String, @Sendable (SampleScene) -> any DocumentCommand)] = [
        ("create root", { _ in CreateEntity(name: "Light") }),
        ("create nested at index", { CreateEntity(name: "Hat", parent: $0.character, index: 0) }),
        ("delete leaf", { DeleteEntity($0.hair) }),
        ("delete subtree", { DeleteEntity($0.character) }),
        ("delete root with descendants", { DeleteEntity($0.world) }),
        ("duplicate leaf", { DuplicateEntity($0.ground) }),
        ("duplicate subtree", { DuplicateEntity($0.character) }),
        ("rename", { RenameEntity($0.hair, to: "Ponytail") }),
        ("set existing component", { SetComponent($0.body, moved(2.5, 0, 0)) }),
        ("add new component", { SetComponent($0.camera, .visibility(Visibility(visible: false))) }),
        ("remove component", { RemoveComponent($0.body, .material) }),
        ("add light", { SetComponent($0.body, .light(.defaultPoint)) }),
        ("change light", { SetComponent($0.camera, .light(.defaultPoint)) }),
        ("remove light", { RemoveComponent($0.camera, .light) }),
        ("add camera", { SetComponent($0.hair, .camera(.default)) }),
        ("change camera", { SetComponent($0.camera, .camera(CameraSettings(fieldOfViewDegrees: 90))) }),
        ("remove camera", { RemoveComponent($0.camera, .camera) }),
        ("reparent to root", { ReparentEntity($0.body, to: nil) }),
        ("reparent across branches", { ReparentEntity($0.hair, to: $0.ground) }),
        ("reorder among siblings", { ReparentEntity($0.hair, to: $0.character, at: 0) }),
        ("create graph", { _ in CreateGraph(name: "Wobble", domain: .logic) }),
        ("delete graph", { DeleteGraph($0.graph) }),
        ("rename graph", { RenameGraph($0.graph, to: "Gloss") }),
        ("add graph node", {
            AddGraphNode(to: $0.graph, definition: "constant.float", inputs: [], outputs: [GraphPort("value", .float)])
        }),
        ("remove connected node", { RemoveGraphNode($0.constant, from: $0.graph) }),
        ("remove fed node", { RemoveGraphNode($0.multiply, from: $0.graph) }),
        ("move graph node", { MoveGraphNode($0.multiply, in: $0.graph, to: SIMD2(9, 9)) }),
        ("set graph value", { SetGraphValue(.float(3), for: "b", of: $0.multiply, in: $0.graph) }),
        ("clear graph value", { SetGraphValue(nil, for: "b", of: $0.multiply, in: $0.graph) }),
        ("connect replaces", {
            ConnectPorts(PortReference($0.constant, "value"), to: PortReference($0.multiply, "b"), in: $0.graph)
        }),
        ("disconnect", { DisconnectPorts(PortReference($0.multiply, "a"), in: $0.graph) }),
        ("composite", { CompositeCommand("Both", [RenameGraph($0.graph, to: "X"), DeleteEntity($0.hair)]) }),
    ]

    @Test(arguments: 0..<cases.count)
    func undoRestoresAndRedoReapplies(_ index: Int) throws {
        let (name, make) = Self.cases[index]
        var scene = try SampleScene()
        let original = scene.session.document
        let command = make(scene)

        try scene.session.execute(command)
        let executed = scene.session.document
        #expect(!executed.hasSameContent(as: original), "\(name) changed nothing")

        try scene.session.undo()
        #expect(scene.session.document.hasSameContent(as: original), "\(name) undo")

        try scene.session.redo()
        #expect(scene.session.document.hasSameContent(as: executed), "\(name) redo")

        try scene.session.undo()
        #expect(scene.session.document.hasSameContent(as: original), "\(name) second undo")
        try scene.session.document.validate()
    }

    @Test func redoOfCreationKeepsTheOriginalIdentifier() throws {
        var session = EditorSession()
        let id = session.document.nextEntityID
        try session.execute(CreateEntity(name: "Sphere", components: [.mesh(.sphere)]))
        try session.execute(SetComponent(id, moved(0, 1, 0)))
        try session.undo()
        try session.undo()
        try session.redo()
        try session.redo()
        #expect(session.document.component(.transform, of: id) == moved(0, 1, 0))
        #expect(session.document.entity(id)?.name == "Sphere")
    }

    @Test func newCommandClearsRedo() throws {
        var scene = try SampleScene()
        try scene.session.execute(RenameEntity(scene.hair, to: "A"))
        try scene.session.undo()
        #expect(scene.session.canRedo)
        try scene.session.execute(RenameEntity(scene.hair, to: "B"))
        #expect(!scene.session.canRedo)
        #expect(throws: AuthoringError.nothingToRedo) { try scene.session.redo() }
    }

    @Test func labelsTrackTheStacks() throws {
        var scene = try SampleScene()
        try scene.session.execute(SetComponent(scene.body, moved(1, 0, 0)))
        #expect(scene.session.undoLabel == "Set Transform")
        try scene.session.undo()
        #expect(scene.session.redoLabel == "Set Transform")
    }

    @Test func emptyHistoryRefusesUndo() {
        var session = EditorSession()
        #expect(throws: AuthoringError.nothingToUndo) { try session.undo() }
    }

    @Test func refusedCommandsLeaveEverythingUntouched() throws {
        var scene = try SampleScene()
        try scene.session.execute(RenameEntity(scene.ground, to: "Floor"))
        try scene.session.undo()
        try scene.session.select([scene.body])
        let redoLabel = scene.session.redoLabel
        let before = scene.session.document
        let revision = scene.session.revision
        let undoLabel = scene.session.undoLabel
        let missing = EntityID(rawValue: 999)
        let refusals: [(any DocumentCommand, AuthoringError)] = [
            (DeleteEntity(missing), .missingEntity(missing)),
            (RenameEntity(missing, to: "x"), .missingEntity(missing)),
            (RemoveComponent(scene.camera, .mesh), .componentAbsent(scene.camera, .mesh)),
            (CreateEntity(name: "x", parent: missing), .missingEntity(missing)),
            (CreateEntity(name: "x", index: 9), .invalidIndex(9, count: 2)),
            (ReparentEntity(scene.world, to: scene.hair), .wouldCreateCycle(entity: scene.world, parent: scene.hair)),
            (ReparentEntity(scene.world, to: scene.world), .wouldCreateCycle(entity: scene.world, parent: scene.world)),
        ]
        for (command, expected) in refusals {
            #expect(throws: expected) { try scene.session.execute(command) }
        }
        #expect(scene.session.document == before)
        #expect(scene.session.revision == revision)
        #expect(scene.session.undoLabel == undoLabel)
        #expect(scene.session.redoLabel == redoLabel)
        #expect(redoLabel == "Rename")
        #expect(scene.session.pendingChanges.count == 2)  // only the setup's rename and its undo
        #expect(scene.session.selection.ordered == [scene.body])
    }
}
