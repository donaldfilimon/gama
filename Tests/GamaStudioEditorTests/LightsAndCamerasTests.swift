//  LightsAndCamerasTests.swift — GamaStudioEditorTests
//
//  Task 3 of the camera-and-lights plan: the `StudioModel` light and camera
//  actions, the look-at orientation of the sample Key Light and Camera, the
//  viewport's fallback editor light, and Look through.

#if canImport(AppKit) && canImport(RealityKit)

import AppKit
import GamaAuthoring
import GamaReality
import GamaStudioEditor
import RealityKit
import Testing

private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tolerance: Float = 1e-3) -> Bool {
    let d = a - b
    return abs(d.x) <= tolerance && abs(d.y) <= tolerance && abs(d.z) <= tolerance
}

private func normalized(_ v: SIMD3<Float>) -> SIMD3<Float> {
    v / (v * v).sum().squareRoot()
}

@MainActor
private func id(named name: String, in model: StudioModel) -> EntityID? {
    model.session.document.entities.values.first { $0.name == name }?.id
}

@MainActor
private func converged(_ model: StudioModel) -> Bool {
    let fresh = RealityBridge()
    fresh.rebuild(from: model.session.document)
    return snapshot(model.bridge) == snapshot(fresh)
}

@MainActor
private func light(of id: EntityID, in model: StudioModel) -> Light? {
    if case .light(let light)? = model.session.document.component(.light, of: id) { return light }
    return nil
}

@MainActor
private func cameraSettings(of id: EntityID, in model: StudioModel) -> CameraSettings? {
    if case .camera(let settings)? = model.session.document.component(.camera, of: id) { return settings }
    return nil
}

/// The world direction an entity looks along: RealityKit cameras and lights
/// look down their local −Z.
@MainActor
private func worldForward(of id: EntityID, in model: StudioModel) -> SIMD3<Float>? {
    model.bridge.entity(for: id).map { normalized($0.convert(direction: SIMD3(0, 0, -1), to: nil)) }
}

@MainActor
@Suite("Sample scene lights and camera")
struct SampleSceneLightsAndCameraTests {
    @Test func sampleSceneAppendsKeyLightAndCameraAfterThePrimitives() {
        let document = StudioModel.sampleScene()
        let names = document.roots.compactMap { document.entity($0)?.name }
        #expect(names == ["Ground", "Box", "Sphere", "Cone", "Key Light", "Camera"])
        #expect(document.count == 6)
    }

    @Test func keyLightIsDirectionalAt3000AimedAtTheOriginFrom364() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let key = try #require(id(named: "Key Light", in: model))
        #expect(light(of: key, in: model) == Light(kind: .directional, intensity: 3000))
        guard case .transform(let transform)? = model.session.document.component(.transform, of: key) else {
            Issue.record("Key Light has no transform")
            return
        }
        #expect(transform.position == SIMD3(3, 6, 4))
        #expect(throws: Never.self) { try transform.validate() }
        let forward = try #require(worldForward(of: key, in: model))
        #expect(close(forward, normalized(-SIMD3<Float>(3, 6, 4))), "forward \(forward)")
    }

    @Test func cameraSitsAt037LookingAtTheOriginWithDefaultSettings() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let camera = try #require(id(named: "Camera", in: model))
        #expect(cameraSettings(of: camera, in: model) == .default)
        let entity = try #require(model.bridge.entity(for: camera))
        #expect(close(entity.position(relativeTo: nil), SIMD3(0, 3, 7)))
        let forward = try #require(worldForward(of: camera, in: model))
        #expect(close(forward, normalized(-SIMD3<Float>(0, 3, 7))), "forward \(forward)")
    }
}

@MainActor
@Suite("StudioModel lights and cameras")
struct StudioModelLightAndCameraTests {
    @Test func addLightCreatesNamesSelectsAndConvergesForEveryKind() throws {
        let model = StudioModel()
        let kinds: [LightKind] = [
            .directional,
            .point(attenuationRadius: 10),
            .spot(innerAngleDegrees: 30, outerAngleDegrees: 45, attenuationRadius: 10),
        ]
        for (index, kind) in kinds.enumerated() {
            model.addLight(kind)
            #expect(model.lastError == nil)
            let created = try #require(model.session.selection.primary)
            let record = try #require(model.session.document.entity(created))
            #expect(record.name == "Light \(index + 1)")
            #expect(record.parent == nil)
            #expect(light(of: created, in: model)?.kind == kind)
            #expect(record.components[.transform] != nil)
            #expect(record.components[.visibility] == .visibility(Visibility()))
            guard case .transform(let transform)? = record.components[.transform] else { continue }
            #expect(transform.position.y > 1, "a new light sits above the scene")
            #expect(converged(model))
        }
        #expect(model.session.undoLabel == "Create Light 3")
    }

    @Test func addLightNumbersAfterTheSampleKeyLight() {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.addLight(.directional)
        #expect(model.session.selection.primary.flatMap { model.session.document.entity($0)?.name } == "Light 2")
    }

    @Test func addCameraCreatesADefaultCameraLookingAtTheOrigin() throws {
        let model = StudioModel()
        model.addCamera()
        #expect(model.lastError == nil)
        let created = try #require(model.session.selection.primary)
        #expect(model.session.document.entity(created)?.name == "Camera 1")
        #expect(cameraSettings(of: created, in: model) == .default)
        let entity = try #require(model.bridge.entity(for: created))
        let eye = entity.position(relativeTo: nil)
        let forward = try #require(worldForward(of: created, in: model))
        #expect(close(forward, normalized(-eye)), "forward \(forward), eye \(eye)")
        #expect(converged(model))

        model.addCamera()
        #expect(model.session.selection.primary.flatMap { model.session.document.entity($0)?.name } == "Camera 2")
    }

    @Test func cycleLightKindWalksDirectionalPointSpotAndKeepsIntensityAndColor() throws {
        let model = StudioModel()
        model.addLight(.directional)
        let lamp = try #require(model.session.selection.primary)
        let before = try #require(light(of: lamp, in: model))

        model.cycleLightKind()
        guard case .point? = light(of: lamp, in: model)?.kind else {
            Issue.record("expected point, got \(String(describing: light(of: lamp, in: model)))")
            return
        }
        #expect(converged(model))
        model.cycleLightKind()
        guard case .spot? = light(of: lamp, in: model)?.kind else {
            Issue.record("expected spot, got \(String(describing: light(of: lamp, in: model)))")
            return
        }
        #expect(converged(model))
        model.cycleLightKind()
        #expect(light(of: lamp, in: model)?.kind == .directional)
        #expect(light(of: lamp, in: model)?.intensity == before.intensity)
        #expect(light(of: lamp, in: model)?.color == before.color)
        #expect(model.lastError == nil)
        #expect(converged(model))
    }

    @Test func scaleLightIntensityMultipliesAndRefusesInvalidFactors() throws {
        let model = StudioModel()
        model.addLight(.directional)
        let lamp = try #require(model.session.selection.primary)

        model.scaleLightIntensity(by: 1.25)
        #expect(model.lastError == nil)
        #expect(light(of: lamp, in: model)?.intensity == 3750)
        #expect(converged(model))

        let revision = model.session.revision
        model.scaleLightIntensity(by: -1)
        guard case .invalidLight? = model.lastError else {
            Issue.record("expected invalidLight, got \(String(describing: model.lastError))")
            return
        }
        #expect(model.session.revision == revision)
        #expect(light(of: lamp, in: model)?.intensity == 3750)
        #expect(converged(model))
    }

    @Test func adjustFieldOfViewStepsAndRefusesOutOfRange() throws {
        let model = StudioModel()
        model.addCamera()
        let camera = try #require(model.session.selection.primary)

        model.adjustFieldOfView(by: 5)
        #expect(model.lastError == nil)
        #expect(cameraSettings(of: camera, in: model)?.fieldOfViewDegrees == 65)
        #expect(converged(model))

        let revision = model.session.revision
        model.adjustFieldOfView(by: 200)
        guard case .invalidCamera? = model.lastError else {
            Issue.record("expected invalidCamera, got \(String(describing: model.lastError))")
            return
        }
        #expect(model.session.revision == revision)
        #expect(cameraSettings(of: camera, in: model)?.fieldOfViewDegrees == 65)
        #expect(converged(model))
    }

    @Test func lightAndCameraActionsRefuseAnEntityWithoutTheComponent() throws {
        let model = StudioModel()
        model.addPrimitive(.box)
        let box = try #require(model.session.selection.primary)
        let revision = model.session.revision

        model.cycleLightKind()
        #expect(model.lastError == .componentAbsent(box, .light))
        model.scaleLightIntensity(by: 2)
        #expect(model.lastError == .componentAbsent(box, .light))
        model.adjustFieldOfView(by: 5)
        #expect(model.lastError == .componentAbsent(box, .camera))

        #expect(model.session.revision == revision)
        #expect(model.session.document.component(.light, of: box) == nil)
        #expect(model.session.document.component(.camera, of: box) == nil)
        #expect(converged(model))
    }

    @Test func lightAndCameraActionsAreNoOpsWithoutSelection() {
        let model = StudioModel(document: StudioModel.sampleScene())
        let revision = model.session.revision
        model.cycleLightKind()
        model.scaleLightIntensity(by: 2)
        model.adjustFieldOfView(by: 5)
        #expect(model.lastError == nil)
        #expect(model.session.revision == revision)
    }

    @Test func onDocumentChangeFiresAfterEditsUndoAndRedoOnly() throws {
        let model = StudioModel()
        var calls = 0
        model.onDocumentChange = { calls += 1 }

        model.addLight(.directional)       // create, then select: one change
        #expect(calls == 1)
        model.select(nil)
        #expect(calls == 1, "selection is not a document change")
        model.undo()
        #expect(calls == 2)
        model.redo()
        #expect(calls == 3)
        model.redo()                        // refused: nothing to redo
        #expect(model.lastError == .nothingToRedo)
        #expect(calls == 3, "a refusal is not a change")
    }
}

@MainActor
@Suite("Viewport fallback light")
struct ViewportFallbackLightTests {
    @Test func sampleSceneKeyLightTurnsTheEditorLightOffAndEditsFollow() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        #expect(viewport.editorLight.isEnabled == false, "the document's Key Light lights the scene")

        let key = try #require(id(named: "Key Light", in: model))
        model.select(key)
        model.deleteSelection()
        #expect(viewport.editorLight.isEnabled == true, "no light left")
        model.undo()
        #expect(viewport.editorLight.isEnabled == false)

        model.select(key)
        model.toggleVisibility()
        #expect(viewport.editorLight.isEnabled == true, "a hidden light does not count")
        model.undo()
        #expect(viewport.editorLight.isEnabled == false)
        model.redo()
        #expect(viewport.editorLight.isEnabled == true)
    }

    @Test func emptyDocumentUsesTheEditorLightUntilALightIsAdded() {
        let model = StudioModel()
        let viewport = ViewportController(model: model, onSelectionChange: {})
        #expect(viewport.editorLight.isEnabled == true)
        model.addLight(.point(attenuationRadius: 10))
        #expect(viewport.editorLight.isEnabled == false)
    }

    @Test func aLightUnderAHiddenAncestorDoesNotCount() throws {
        var session = EditorSession()
        try session.execute(CreateEntity(name: "Rig", components: [.visibility(Visibility(visible: false))]))
        let rig = try #require(session.document.roots.first)
        try session.execute(CreateEntity(
            name: "Lamp", parent: rig,
            components: [.transform(.identity), .light(.defaultPoint)]
        ))
        let model = StudioModel(document: session.document)
        let viewport = ViewportController(model: model, onSelectionChange: {})
        #expect(viewport.editorLight.isEnabled == true)

        model.select(rig)
        model.toggleVisibility()   // show the rig: its lamp now lights the scene
        #expect(viewport.editorLight.isEnabled == false)
    }

    @Test func theControllerChainsAnExistingDocumentChangeListener() {
        let model = StudioModel()
        var calls = 0
        model.onDocumentChange = { calls += 1 }
        let viewport = ViewportController(model: model, onSelectionChange: {})
        model.addLight(.directional)
        #expect(calls == 1, "the listener installed first still runs")
        #expect(viewport.editorLight.isEnabled == false)
    }
}

@MainActor
@Suite("Viewport look through")
struct ViewportLookThroughTests {
    @Test func lookThroughPlacesTheOrbitOnTheCameraAndCopiesItsFieldOfView() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        let camera = try #require(id(named: "Camera", in: model))
        model.select(camera)
        model.adjustFieldOfView(by: -20)
        model.nudgeSelection(by: SIMD3(1, 0, 0))
        viewport.orbit(byDragX: 200, dragY: 50)      // move away from the camera first
        let distance = viewport.orbit.distance

        viewport.lookThrough(camera)

        let eye = SIMD3<Float>(1, 3, 7)
        let forward = normalized(-SIMD3<Float>(0, 3, 7))
        #expect(close(viewport.orbit.position, eye), "eye \(viewport.orbit.position)")
        #expect(close(viewport.orbit.target, eye + forward * distance), "target \(viewport.orbit.target)")
        #expect(abs(viewport.orbit.distance - distance) < 1e-3)
        #expect(close(viewport.camera.position(relativeTo: nil), eye))
        #expect(viewport.camera.camera.fieldOfViewInDegrees == 40)
    }

    @Test func pickingStillWorksFromInsideTheCameraLookedThrough() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        viewport.arView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let camera = try #require(id(named: "Camera", in: model))
        let box = try #require(id(named: "Box", in: model))
        viewport.orbit(byDragX: 150, dragY: 0)
        viewport.lookThrough(camera)   // the eye is now inside the camera's marker

        let boxEntity = try #require(model.bridge.entity(for: box))
        let point = try #require(viewport.arView.project(boxEntity.position(relativeTo: nil)))
        viewport.pick(at: point)
        #expect(model.session.selection.primary == box)

        viewport.pick(at: CGPoint(x: 2, y: viewport.arView.bounds.height - 2))
        #expect(model.session.selection.primary == nil, "the marker around the eye is not a hit")
    }

    @Test func lookThroughIgnoresAnEntityWithoutACamera() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        let box = try #require(id(named: "Box", in: model))
        let before = viewport.orbit
        let fieldOfView = viewport.camera.camera.fieldOfViewInDegrees

        viewport.lookThrough(box)
        viewport.lookThrough(EntityID(rawValue: 999))

        #expect(viewport.orbit == before)
        #expect(viewport.camera.camera.fieldOfViewInDegrees == fieldOfView)
    }
}

#endif
