//  ViewportTests.swift — GamaStudioEditorTests
//
//  The RealityKit viewport: the pick lookup that turns a hit entity into an
//  authored selection, and the host placing the ARView on the viewport
//  region.

#if canImport(AppKit) && canImport(RealityKit)

import AppKit
import GamaAppleUI
import GamaAuthoring
import GamaReality
import GamaStudioEditor
import RealityKit
import Testing

/// The id of the sample entity named `name`.
@MainActor
private func sampleID(named name: String, in model: StudioModel) -> EntityID? {
    model.session.document.entities.values.first { $0.name == name }?.id
}

@MainActor
@Suite("Viewport")
struct ViewportTests {
    @Test func pickResolvesProjectedEntitiesAndTheirSubparts() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let box = try #require(sampleID(named: "Box", in: model))
        let boxEntity = try #require(model.bridge.entity(for: box))

        #expect(ViewportController.pickedEntityID(for: boxEntity, in: model.bridge) == box)

        // A sub-part the bridge did not create resolves to its owner.
        let part = Entity()
        let nested = Entity()
        boxEntity.addChild(part)
        part.addChild(nested)
        #expect(ViewportController.pickedEntityID(for: part, in: model.bridge) == box)
        #expect(ViewportController.pickedEntityID(for: nested, in: model.bridge) == box)

        #expect(ViewportController.pickedEntityID(for: Entity(), in: model.bridge) == nil)
        #expect(ViewportController.pickedEntityID(for: model.bridge.root, in: model.bridge) == nil)
        #expect(ViewportController.pickedEntityID(for: nil, in: model.bridge) == nil)
    }

    @Test func controllerParentsTheBridgeUnderItsScene() {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        // bridge.root sits under an anchor in the ARView's scene, so every
        // edit the bridge applies is what the view renders.
        let anchor = model.bridge.root.parent
        #expect(anchor is AnchorEntity)
        #expect(viewport.arView.scene.anchors.contains { $0 === anchor })
    }

    @Test func hostPlacesTheViewportOnItsRegion() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let host = GamaHostView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        try host.install(app: StudioApp(model: model))
        let viewport = ViewportController(model: model, onSelectionChange: {})
        host.attach(viewport.arView, to: StudioApp.viewportRegion)
        host.invalidate()

        let frame = viewport.arView.frame
        #expect(viewport.arView.superview === host)
        #expect(!viewport.arView.isHidden)
        #expect(host.bounds.contains(frame))
        // The side panels take a fixed share of the width; the viewport is
        // the bulk of what is left, not a sliver or an empty rect.
        #expect(frame.width > host.bounds.width * 0.5)
        #expect(frame.height > host.bounds.height * 0.5)
    }

    @Test func clickSelectsTheHitEntityAndEmptySpaceClears() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var changes = 0
        let viewport = ViewportController(model: model, onSelectionChange: { changes += 1 })
        viewport.arView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let box = try #require(sampleID(named: "Box", in: model))
        let boxEntity = try #require(model.bridge.entity(for: box))

        // `project` and `entity(at:)` share the view's own coordinates:
        // AppKit's bottom-left origin (ARView is not flipped), the same
        // space `NSClickGestureRecognizer.location(in:)` reports.
        #expect(!viewport.arView.isFlipped)
        let point = try #require(viewport.arView.project(boxEntity.position(relativeTo: nil)))
        viewport.pick(at: point)
        #expect(model.session.selection.primary == box)
        #expect(changes == 1)

        // Top-left corner (high y, since the origin is bottom-left): the
        // background above the ground plane, where nothing is projected.
        viewport.pick(at: CGPoint(x: 2, y: viewport.arView.bounds.height - 2))
        #expect(model.session.selection.primary == nil)
        #expect(changes == 2)
    }
}

#endif
