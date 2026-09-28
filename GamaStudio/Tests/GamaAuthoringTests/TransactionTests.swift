import GamaAuthoring
import Testing

@Suite("Transactions")
struct TransactionTests {
    @Test func failureRollsBackEveryCommand() throws {
        var scene = try SampleScene()
        let before = scene.session.document
        let revision = scene.session.revision
        let undoLabel = scene.session.undoLabel

        #expect(throws: AuthoringError.componentAbsent(scene.camera, .mesh)) {
            try scene.session.transaction("Restyle", [
                SetComponent(scene.body, moved(2.5, 0, 0)),
                RenameEntity(scene.body, to: "Torso"),
                RemoveComponent(scene.camera, .mesh),
            ])
        }
        #expect(scene.session.document == before)
        #expect(scene.session.revision == revision)
        #expect(scene.session.undoLabel == undoLabel)
        #expect(scene.session.pendingChanges.isEmpty)
    }

    @Test func successIsOneUndoableStep() throws {
        var scene = try SampleScene()
        let before = scene.session.document
        try scene.session.transaction("Restyle", [
            SetComponent(scene.body, moved(2.5, 0, 0)),
            RenameEntity(scene.body, to: "Torso"),
            SetComponent(scene.body, .material(Material(metallic: 0.8))),
        ])
        #expect(scene.session.undoLabel == "Restyle")
        #expect(scene.session.document.entity(scene.body)?.name == "Torso")

        try scene.session.undo()
        #expect(scene.session.document.hasSameContent(as: before))
        #expect(!scene.session.canUndo || scene.session.undoLabel != "Restyle")

        try scene.session.redo()
        #expect(scene.session.document.entity(scene.body)?.name == "Torso")
        #expect(scene.session.document.component(.material, of: scene.body) == .material(Material(metallic: 0.8)))
    }

    @Test func laterCommandsSeeEarlierOnes() throws {
        var session = EditorSession()
        let parent = session.document.nextEntityID
        let child = EntityID(rawValue: parent.rawValue + 1)
        try session.transaction("Build", [
            CreateEntity(name: "Desk"),
            CreateEntity(name: "Top", parent: parent, components: [.mesh(.box)]),
            SetComponent(child, moved(0, 0.75, 0)),
        ])
        #expect(session.document.children(of: parent) == [child])
        try session.undo()
        #expect(session.document.count == 0)
        try session.redo()
        #expect(session.document.component(.transform, of: child) == moved(0, 0.75, 0))
    }

    @Test func emptyTransactionIsRefused() {
        var session = EditorSession()
        #expect(throws: AuthoringError.emptyTransaction) {
            try session.transaction("Nothing", [])
        }
    }
}
