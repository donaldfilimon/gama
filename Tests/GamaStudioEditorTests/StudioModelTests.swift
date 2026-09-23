import GamaAuthoring
import GamaReality
import GamaStudioEditor
import Testing

/// Asserts the model's bridge equals a fresh `rebuild` from its current
/// document — the convergence idea from `BridgeConvergenceTests`, applied
/// after every `StudioModel` action.
@MainActor
private func assertConverged(
    _ model: StudioModel,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let fresh = RealityBridge()
    fresh.rebuild(from: model.session.document)
    #expect(snapshot(model.bridge) == snapshot(fresh), sourceLocation: sourceLocation)
}

@MainActor
@Suite("StudioModel editing")
struct StudioModelEditingTests {
    @Test func addPrimitiveCreatesNamesSelectsAndConverges() {
        let model = StudioModel()
        let revisionBefore = model.session.revision
        model.addPrimitive(.box)

        #expect(model.lastError == nil)
        #expect(model.session.revision == revisionBefore + 1)
        // `StudioModel.run` always calls `EditorSession.execute`, so the undo
        // label is the command's own label ("Create Box 1"), not a label
        // `StudioModel` supplies itself.
        #expect(model.session.undoLabel == "Create Box 1")
        let created = model.session.selection.primary
        #expect(created != nil)
        #expect(created.flatMap { model.session.document.entity($0)?.name } == "Box 1")
        assertConverged(model)
    }

    @Test func addingTwoOfTheSamePrimitiveNumbersThemDistinctly() {
        let model = StudioModel()
        model.addPrimitive(.sphere)
        model.addPrimitive(.sphere)
        let names = model.session.document.entities.values.map(\.name).sorted()
        #expect(names == ["Sphere 1", "Sphere 2"])
        assertConverged(model)
    }

    @Test func deleteSelectionPrunesSelectionAndConverges() {
        let model = StudioModel()
        model.addPrimitive(.box)
        let id = model.session.selection.primary!

        model.deleteSelection()

        #expect(model.lastError == nil)
        #expect(model.session.selection.primary == nil)
        #expect(model.session.document.contains(id) == false)
        assertConverged(model)
    }

    @Test func deleteSelectionIsANoOpWithoutSelection() {
        let model = StudioModel()
        let revisionBefore = model.session.revision

        model.deleteSelection()

        #expect(model.lastError == nil)
        #expect(model.session.revision == revisionBefore)
        assertConverged(model)
    }

    @Test func deleteThenUndoRestoresTheEntityWithItsOriginalID() {
        let model = StudioModel()
        model.addPrimitive(.box)
        let id = model.session.selection.primary!

        model.deleteSelection()
        model.undo()

        #expect(model.lastError == nil)
        #expect(model.session.document.contains(id))
        assertConverged(model)
    }

    @Test func duplicateSelectionCopiesTheSubtreeAndConverges() {
        let model = StudioModel()
        model.addPrimitive(.sphere)
        let countBefore = model.session.document.count

        model.duplicateSelection()

        #expect(model.lastError == nil)
        #expect(model.session.undoLabel == "Duplicate")
        #expect(model.session.document.count == countBefore + 1)
        assertConverged(model)
    }

    @Test func duplicateSelectionIsANoOpWithoutSelection() {
        let model = StudioModel()
        let revisionBefore = model.session.revision

        model.duplicateSelection()

        #expect(model.lastError == nil)
        #expect(model.session.revision == revisionBefore)
        assertConverged(model)
    }

    @Test func nudgeSelectionMovesTheEntityRelativelyAndConverges() {
        let model = StudioModel()
        model.addPrimitive(.cone)
        let id = model.session.selection.primary!
        guard case .transform(let before)? = model.session.document.component(.transform, of: id) else {
            Issue.record("expected a transform component")
            return
        }

        model.nudgeSelection(by: SIMD3(1, 2, 3))

        #expect(model.lastError == nil)
        guard case .transform(let after)? = model.session.document.component(.transform, of: id) else {
            Issue.record("expected a transform component")
            return
        }
        #expect(after.position == before.position + SIMD3<Float>(1, 2, 3))
        assertConverged(model)
    }

    @Test func nudgeSelectionIsANoOpWithoutSelection() {
        let model = StudioModel()
        let revisionBefore = model.session.revision

        model.nudgeSelection(by: SIMD3(1, 0, 0))

        #expect(model.lastError == nil)
        #expect(model.session.revision == revisionBefore)
        assertConverged(model)
    }

    @Test func toggleVisibilityFlipsFromTheDefaultAndBackAndConverges() {
        let model = StudioModel()
        model.addPrimitive(.box)
        let id = model.session.selection.primary!

        model.toggleVisibility()
        guard case .visibility(let hidden)? = model.session.document.component(.visibility, of: id) else {
            Issue.record("expected a visibility component")
            return
        }
        #expect(hidden.visible == false)
        assertConverged(model)

        model.toggleVisibility()
        guard case .visibility(let shown)? = model.session.document.component(.visibility, of: id) else {
            Issue.record("expected a visibility component")
            return
        }
        #expect(shown.visible == true)
        assertConverged(model)
    }

    @Test func toggleVisibilityIsANoOpWithoutSelection() {
        let model = StudioModel()
        let revisionBefore = model.session.revision

        model.toggleVisibility()

        #expect(model.lastError == nil)
        #expect(model.session.revision == revisionBefore)
        assertConverged(model)
    }
}

@MainActor
@Suite("StudioModel history")
struct StudioModelHistoryTests {
    @Test func undoThenRedoRestoresTheDocumentAndConverges() {
        let model = StudioModel()
        model.addPrimitive(.box)
        let afterAdd = model.session.document

        model.undo()
        #expect(model.lastError == nil)
        #expect(model.session.document.count == 0)
        assertConverged(model)

        model.redo()
        #expect(model.lastError == nil)
        #expect(model.session.document.hasSameContent(as: afterAdd))
        assertConverged(model)
    }

    @Test func undoWithEmptyHistorySetsLastErrorAndChangesNothing() {
        let model = StudioModel()
        model.addPrimitive(.box)
        model.select(nil)
        model.undo()  // drain the one real step so the stack is empty
        let documentBefore = model.session.document
        let revisionBefore = model.session.revision

        model.undo()

        #expect(model.lastError == .nothingToUndo)
        #expect(model.session.document == documentBefore)
        #expect(model.session.revision == revisionBefore)
        assertConverged(model)
    }

    @Test func redoWithEmptyHistorySetsLastErrorAndChangesNothing() {
        let model = StudioModel()
        let documentBefore = model.session.document
        let revisionBefore = model.session.revision

        model.redo()

        #expect(model.lastError == .nothingToRedo)
        #expect(model.session.document == documentBefore)
        #expect(model.session.revision == revisionBefore)
        assertConverged(model)
    }
}

@MainActor
@Suite("StudioModel selection")
struct StudioModelSelectionTests {
    @Test func selectingAMissingEntitySetsLastErrorAndLeavesSelectionUnchanged() {
        let model = StudioModel()
        model.addPrimitive(.box)
        let selectedBefore = model.session.selection.primary
        let missing = EntityID(rawValue: 999)

        model.select(missing)

        #expect(model.lastError == .missingEntity(missing))
        #expect(model.session.selection.primary == selectedBefore)
        assertConverged(model)
    }

    @Test func selectingNilClearsTheSelection() {
        let model = StudioModel()
        model.addPrimitive(.box)

        model.select(nil)

        #expect(model.lastError == nil)
        #expect(model.session.selection.primary == nil)
        assertConverged(model)
    }
}

@MainActor
@Suite("StudioModel construction")
struct StudioModelConstructionTests {
    @Test func initProjectsTheGivenDocumentImmediately() {
        let model = StudioModel(document: StudioModel.sampleScene())

        #expect(model.bridge.count == model.session.document.count)
        assertConverged(model)
    }

    @Test func sampleSceneHasTheFourNamedEntities() {
        let document = StudioModel.sampleScene()

        let names = Set(document.entities.values.map(\.name))
        #expect(names == ["Ground", "Box", "Sphere", "Cone"])
        #expect(document.count == 4)
    }
}
