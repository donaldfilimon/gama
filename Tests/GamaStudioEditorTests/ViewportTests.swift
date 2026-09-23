//  ViewportTests.swift — GamaStudioEditorTests
//
//  The RealityKit viewport: the pick lookup that turns a hit entity into an
//  authored selection, and the host placing the ARView on the viewport
//  region.

#if canImport(AppKit) && canImport(RealityKit)

import AppKit
import Foundation
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

    /// A real click, delivered through `NSWindow.sendEvent` so AppKit's own
    /// hit-testing, gesture recognizer, and first-responder handling run,
    /// selects the hit entity, and the keyboard keeps driving Gama's panels
    /// afterwards even though AppKit made the ARView first responder.
    @Test func windowClickSelectsAndKeysStillReachGama() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = GamaHostView(frame: frame)
        window.contentView = host
        try host.install(app: StudioApp(model: model))
        var changes = 0
        let viewport = ViewportController(model: model, onSelectionChange: { changes += 1; host.invalidate() })
        host.attach(viewport.arView, to: StudioApp.viewportRegion)
        host.invalidate()
        window.orderFront(nil)
        #expect(window.makeFirstResponder(host))

        let box = try #require(sampleID(named: "Box", in: model))
        let boxEntity = try #require(model.bridge.entity(for: box))
        let inView = try #require(viewport.arView.project(boxEntity.position(relativeTo: nil)))
        let inWindow = viewport.arView.convert(inView, to: nil)
        #expect(window.contentView?.hitTest(inWindow) === viewport.arView)

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        #expect(model.session.selection.primary == box, "the click gesture did not select Box")
        #expect(changes == 1)
        // AppKit hands a clicked ARView first responder. Pinned so that if
        // this ever changes, the key assertions below are re-read against it.
        let arViewIsFirstResponder = window.firstResponder === viewport.arView
        #expect(arViewIsFirstResponder)

        // Keys still reach Gama through the responder chain (ARView ->
        // GamaHostView). Gama focus starts on the first toolbar button,
        // "Add Box"; Tab and Right each move it one button along.
        func press(_ characters: String, _ keyCode: UInt16) throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ))
            window.sendEvent(event)
        }
        let enter = ("\r", UInt16(36))
        let tab = ("\t", UInt16(48))
        let right = (String(UnicodeScalar(0xF703)!), UInt16(124))
        try press(enter.0, enter.1)
        try press(tab.0, tab.1)
        try press(enter.0, enter.1)
        try press(right.0, right.1)
        try press(enter.0, enter.1)
        let names = Set(model.session.document.entities.values.map(\.name))
        #expect(model.session.document.count == 7)
        #expect(names.isSuperset(of: ["Box 2", "Sphere 2", "Cone 2"]), "entities after the keys: \(names.sorted())")
    }

    /// ADR 0016's handoff still works with the click fix in place: when Gama
    /// focus reaches the viewport region by keyboard, the host gives the
    /// ARView first responder, and a click there leaves it with the ARView.
    @Test func gamaFocusOnTheRegionStillHandsTheViewportFirstResponder() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = GamaHostView(frame: frame)
        window.contentView = host
        try host.install(app: StudioApp(model: model))
        let viewport = ViewportController(model: model, onSelectionChange: { host.invalidate() })
        host.attach(viewport.arView, to: StudioApp.viewportRegion)
        host.invalidate()
        window.orderFront(nil)
        #expect(window.makeFirstResponder(host))

        // Tab through Gama focus until it lands on the viewport region.
        var tabs = 0
        while window.firstResponder !== viewport.arView, tabs < 40 {
            let tab = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
                isARepeat: false, keyCode: 48
            ))
            // Straight to the window: the test process is never the active
            // app, so NSApp would route a key event to a key window it lacks.
            window.sendEvent(tab)
            tabs += 1
        }
        let handedOff = window.firstResponder === viewport.arView
        #expect(handedOff, "Gama focus never handed the viewport first responder after \(tabs) tabs")

        let box = try #require(sampleID(named: "Box", in: model))
        let boxEntity = try #require(model.bridge.entity(for: box))
        let inView = try #require(viewport.arView.project(boxEntity.position(relativeTo: nil)))
        let inWindow = viewport.arView.convert(inView, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        #expect(model.session.selection.primary == box)
        let keptByViewport = window.firstResponder === viewport.arView
        #expect(keptByViewport, "a click on the focused viewport moved first responder away")
    }
}

#endif
