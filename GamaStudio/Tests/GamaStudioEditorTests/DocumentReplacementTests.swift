import GamaAuthoring
import GamaReality
import GamaStudioEditor
import Testing

@MainActor
@Suite("StudioModel document replacement")
struct DocumentReplacementTests {
    @Test func replaceClearsHistorySelectionAndErrorAndRebuilds() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.addPrimitive(.box)
        model.undo()
        model.redo()
        model.undo()
        model.undo()  // nothing left: sets lastError
        #expect(model.lastError != nil)
        model.addPrimitive(.sphere)
        #expect(model.session.selection.primary != nil)

        var replacement = EditorSession()
        try replacement.execute(CreateEntity(name: "Only", components: [.mesh(.cone)]))
        var notified = 0
        model.onDocumentChange = { notified += 1 }
        model.replaceDocument(replacement.document)

        #expect(model.session.document == replacement.document)
        #expect(!model.session.canUndo)
        #expect(!model.session.canRedo)
        #expect(model.session.selection.primary == nil)
        #expect(model.lastError == nil)
        #expect(notified == 1)
        let fresh = RealityBridge()
        fresh.rebuild(from: replacement.document)
        #expect(snapshot(model.bridge) == snapshot(fresh))
        #expect(model.bridge.count == 1)
        #expect(!model.hasUnsavedChanges)
    }

    @Test func unsavedChangesTrackContentNotRevision() {
        let model = StudioModel(document: StudioModel.sampleScene())
        #expect(!model.hasUnsavedChanges)
        model.addPrimitive(.box)
        #expect(model.hasUnsavedChanges)
        model.undo()
        #expect(!model.hasUnsavedChanges, "undoing back to the saved content is clean")
        model.redo()
        #expect(model.hasUnsavedChanges)
        model.markSaved()
        #expect(!model.hasUnsavedChanges)
        model.select(nil)
        #expect(!model.hasUnsavedChanges, "selection is not content")
        model.undo()
        #expect(model.hasUnsavedChanges)
    }
}
