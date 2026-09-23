import GamaAuthoring
import GamaCore
import GamaDraw
import GamaStudioEditor
import Testing

/// The frame size every test pumps: wide enough for all three panels.
private let frameSize = Size(width: 120, height: 40)

/// Paints `frame` into a fresh buffer and returns its rows, trailing blanks
/// trimmed, joined by newlines.
private func painted(_ frame: LaidOutNode) -> String {
    var buffer = CellBuffer(size: frameSize)
    buffer.clearBack()
    CellPainter.paint(frame, into: &buffer)
    return (0..<frameSize.height).map { buffer.rowText($0) }.joined(separator: "\n")
}

/// The id of the sample entity named `name`.
@MainActor
private func entityID(named name: String, in model: StudioModel) -> EntityID? {
    model.session.document.entities.values.first { $0.name == name }?.id
}

@MainActor
@Suite("StudioApp panels")
struct StudioAppTests {
    @Test func hierarchyListsEverySampleEntity() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        let text = painted(host.pump(size: frameSize))

        #expect(text.contains("Scene"))
        #expect(text.contains("Inspector"))
        for name in ["Ground", "Box", "Sphere", "Cone"] {
            #expect(text.contains(name), "hierarchy is missing \(name)")
        }
        #expect(text.contains("Nothing selected"))
        let duplicates = host.duplicateIDs
        #expect(duplicates.isEmpty)
    }

    @Test func inspectorShowsTheSelectedEntity() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)

        let box = try #require(entityID(named: "Box", in: model))
        model.select(box)
        let text = painted(host.pump(size: frameSize))

        #expect(text.contains("Name: Box"))
        #expect(text.contains("x: -2.00"))
        #expect(text.contains("y: 0.50"))
        #expect(text.contains("z: 0.00"))
        #expect(text.contains("Mesh: box"))
        #expect(text.contains("Visible: yes"))
        #expect(text.contains("▸ Box"), "the selected row is not marked")
        #expect(!text.contains("Nothing selected"))
    }

    @Test func viewportRegionFillsTheRemainingSpace() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)

        let regions = host.nativeRegions
        let viewport = try #require(regions.first { $0.id == StudioApp.viewportRegion })
        #expect(viewport.frame.size.width >= 30)
        #expect(viewport.frame.size.height >= 10)
        let duplicates = host.duplicateNativeRegionIDs
        #expect(duplicates.isEmpty)
    }

    @Test func toolbarActionsEditTheModel() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)
        let countBefore = model.session.document.count

        host.perform(ActionID("studio.addBox"))
        #expect(model.session.document.count == countBefore + 1)
        let text = painted(host.pump(size: frameSize))
        #expect(text.contains("Box 2"))
        #expect(text.contains("Name: Box 2"))

        host.perform(ActionID("studio.undo"))
        #expect(model.session.document.count == countBefore)
    }

    @Test func enterOnTheFocusedToolbarButtonActivatesIt() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)
        let countBefore = model.session.document.count

        // Initial focus lands on the first focusable node: "Add Box".
        host.handle(.key(.enter))
        #expect(model.session.document.count == countBefore + 1)
    }

    @Test func inspectorButtonsNudgeAndToggleTheSelection() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        let box = try #require(entityID(named: "Box", in: model))
        model.select(box)
        _ = host.pump(size: frameSize)

        host.perform(ActionID("studio.nudge.+y"))
        var text = painted(host.pump(size: frameSize))
        #expect(text.contains("y: 0.75"))

        host.perform(ActionID("studio.toggleVisibility"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("Visible: no"))
        #expect(text.contains(" Show "))
    }

    @Test func hierarchyRowSelectsItsEntity() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)
        let sphere = try #require(entityID(named: "Sphere", in: model))

        // Tab past every toolbar button to the hierarchy rows (Ground, Box,
        // Sphere) and activate the third.
        for _ in 0..<(StudioApp.toolbarActionIDs.count + 2) { host.handle(.key(.tab)) }
        host.handle(.key(.enter))
        #expect(model.session.selection.primary == sphere)
    }

    @Test func statusLineReportsRevisionAndRefusals() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        var text = painted(host.pump(size: frameSize))
        #expect(text.contains("rev 0 · no selection · undo: —"))

        host.perform(ActionID("studio.undo"))
        #expect(model.lastError == .nothingToUndo)
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("nothingToUndo"))
    }

    @Test func frameButtonCallsTheViewportHookWithoutEditing() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let calls = FrameCalls()
        var host = try FrameHost(app: StudioApp(model: model, viewport: ViewportActions(frameSelection: { calls.count += 1 }, lookThrough: { _ in })))
        let text = painted(host.pump(size: frameSize))
        #expect(text.contains("Frame"))
        let revision = model.session.revision
        host.perform(ActionID("studio.frame"))
        #expect(calls.count == 1)
        #expect(model.session.revision == revision, "framing is not an edit")
        #expect(StudioApp.toolbarActionIDs.contains(ActionID("studio.frame")))
    }

    @Test func addLightButtonCreatesAndSelectsAPointLight() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)
        let countBefore = model.session.document.count

        host.perform(ActionID("studio.addLight"))
        #expect(model.session.document.count == countBefore + 1)
        let text = painted(host.pump(size: frameSize))
        #expect(text.contains("Light"))
        #expect(text.contains("Kind: Point"))
        #expect(text.contains("lm"))
        #expect(StudioApp.toolbarActionIDs.contains(ActionID("studio.addLight")))
    }

    @Test func addCameraButtonCreatesAndSelectsACamera() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)
        let countBefore = model.session.document.count

        host.perform(ActionID("studio.addCamera"))
        #expect(model.session.document.count == countBefore + 1)
        let text = painted(host.pump(size: frameSize))
        #expect(text.contains("Camera"))
        #expect(text.contains("FOV:"))
        #expect(text.contains("Look through"))
        #expect(StudioApp.toolbarActionIDs.contains(ActionID("studio.addCamera")))
    }

    @Test func inspectorShowsExistingLightFields() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)
        let keyLight = try #require(entityID(named: "Key Light", in: model))
        model.select(keyLight)

        let text = painted(host.pump(size: frameSize))
        #expect(text.contains("Kind: Directional"))
        #expect(text.contains("Intensity: 3000.00 lx"))
        #expect(text.contains("Color: 1.00, 1.00, 1.00"))
    }

    @Test func lightKindButtonCyclesTheSelectedLight() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        let keyLight = try #require(entityID(named: "Key Light", in: model))
        model.select(keyLight)
        _ = host.pump(size: frameSize)

        host.perform(ActionID("studio.lightKind"))
        var text = painted(host.pump(size: frameSize))
        #expect(text.contains("Kind: Point"))

        host.perform(ActionID("studio.lightKind"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("Kind: Spot"))
    }

    @Test func lightIntensityButtonsScaleTheSelectedLight() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        let keyLight = try #require(entityID(named: "Key Light", in: model))
        model.select(keyLight)
        _ = host.pump(size: frameSize)

        host.perform(ActionID("studio.lightIntensity.-"))
        var text = painted(host.pump(size: frameSize))
        #expect(text.contains("Intensity: 2400.00 lx"))

        host.perform(ActionID("studio.lightIntensity.+"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("Intensity: 3000.00 lx"))
    }

    @Test func inspectorShowsExistingCameraFields() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        _ = host.pump(size: frameSize)
        let camera = try #require(entityID(named: "Camera", in: model))
        model.select(camera)

        let text = painted(host.pump(size: frameSize))
        #expect(text.contains("FOV: 60.00°"))
        #expect(text.contains("Near: 0.01"))
        #expect(text.contains("Far: 1000.00"))
    }

    @Test func cameraFovButtonsAdjustTheSelectedCamera() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        let camera = try #require(entityID(named: "Camera", in: model))
        model.select(camera)
        _ = host.pump(size: frameSize)

        host.perform(ActionID("studio.cameraFov.+"))
        var text = painted(host.pump(size: frameSize))
        #expect(text.contains("FOV: 65.00°"))

        host.perform(ActionID("studio.cameraFov.-"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("FOV: 60.00°"))
    }

    @Test func lookThroughButtonCallsTheViewportHookWithTheSelectedIDWithoutEditing() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let calls = LookThroughCalls()
        var host = try FrameHost(app: StudioApp(
            model: model,
            viewport: ViewportActions(frameSelection: {}, lookThrough: { id in calls.ids.append(id) })
        ))
        let camera = try #require(entityID(named: "Camera", in: model))
        model.select(camera)
        _ = host.pump(size: frameSize)
        let revision = model.session.revision

        host.perform(ActionID("studio.lookThrough"))
        #expect(calls.ids == [camera])
        #expect(model.session.revision == revision, "look through is not an edit")
    }

    @Test func hierarchyHintsLightAndCameraRows() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        let text = painted(host.pump(size: frameSize))

        #expect(text.contains("Key Light (L)"))
        #expect(text.contains("Camera (C)"))
    }
}

/// Counts frame-hook calls; main-actor isolated, so the `@Sendable` hook may capture it.
@MainActor
private final class FrameCalls {
    var count = 0
}

/// Records every id passed to `ViewportActions.lookThrough`; main-actor
/// isolated, so the `@Sendable` hook may capture it.
@MainActor
private final class LookThroughCalls {
    var ids: [EntityID] = []
}
