import GamaAuthoring
import Testing

@Suite("Selection")
struct SelectionTests {
    @Test func selectionOrderAndPrimary() {
        var selection = Selection()
        let a = EntityID(rawValue: 1), b = EntityID(rawValue: 2), c = EntityID(rawValue: 3)
        selection.replace(with: [a, b])
        #expect(selection.ordered == [a, b])
        #expect(selection.primary == b)
        selection.add([c, a])
        #expect(selection.ordered == [a, b, c])
        #expect(selection.primary == a)
        selection.subtract([a])
        #expect(selection.primary == c)
        selection.clear()
        #expect(selection.isEmpty && selection.primary == nil)
    }

    @Test func deletionPrunesSelectionAndUndoDoesNotRestoreIt() throws {
        var scene = try SampleScene()
        try scene.session.select([scene.camera, scene.body, scene.hair])
        try scene.session.execute(DeleteEntity(scene.character))
        #expect(scene.session.selection.ordered == [scene.camera])
        #expect(scene.session.selection.primary == scene.camera)
        try scene.session.undo()
        #expect(scene.session.selection.ordered == [scene.camera])
    }

    @Test func selectingMissingEntitiesIsRefused() throws {
        var scene = try SampleScene()
        try scene.session.select([scene.body])
        let missing = EntityID(rawValue: 42)
        #expect(throws: AuthoringError.missingEntity(missing)) {
            try scene.session.select([scene.hair, missing])
        }
        #expect(scene.session.selection.ordered == [scene.body])
    }

    @Test func selectionIsNotHistory() throws {
        var scene = try SampleScene()
        let revision = scene.session.revision
        try scene.session.select([scene.body])
        #expect(scene.session.revision == revision)
        #expect(scene.session.undoLabel == "Add Node", "still the fixture's last edit")
    }
}

@Suite("Change feed")
struct ChangeFeedTests {
    @Test func eachCommandReportsExactlyWhatChanged() throws {
        var scene = try SampleScene()
        let s = scene
        #expect(try scene.session.execute(RenameEntity(s.hair, to: "Bun")) == [.renamed(s.hair)])
        #expect(try scene.session.execute(SetComponent(s.hair, moved(0, 2, 0))) == [.componentSet(s.hair, .transform)])
        #expect(try scene.session.execute(RemoveComponent(s.hair, .mesh)) == [.componentRemoved(s.hair, .mesh)])
        #expect(try scene.session.execute(ReparentEntity(s.hair, to: nil)) == [.reparented(s.hair)])
    }

    @Test func subtreeDeletionReportsChildrenFirstAndRestoreParentFirst() throws {
        var scene = try SampleScene()
        let s = scene
        let deleted = try scene.session.execute(DeleteEntity(s.character))
        #expect(deleted == [.entityDeleted(s.hair), .entityDeleted(s.body), .entityDeleted(s.character)])
        let restored = try scene.session.undo()
        #expect(restored == [.entityCreated(s.character), .entityCreated(s.body), .entityCreated(s.hair)])
    }

    @Test func transactionChangesAccumulateAndDrain() throws {
        var scene = try SampleScene()
        let s = scene
        try scene.session.transaction("Two", [RenameEntity(s.body, to: "A"), RenameEntity(s.hair, to: "B")])
        try scene.session.undo()
        #expect(scene.session.drainChanges() == [.renamed(s.body), .renamed(s.hair), .renamed(s.hair), .renamed(s.body)])
        #expect(scene.session.pendingChanges.isEmpty)
    }

    @Test func revisionCountsCommittedSteps() throws {
        var scene = try SampleScene()
        let start = scene.session.revision
        try scene.session.execute(RenameEntity(scene.body, to: "A"))
        try scene.session.undo()
        try scene.session.redo()
        #expect(scene.session.revision == start + 3)
    }
}
