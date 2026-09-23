//  ViewportCameraTests.swift — GamaStudioEditorTests
//
//  The viewport's orbit controls: the drag/scroll/pinch mapping onto
//  `OrbitCamera`, device routing for scroll events, and a real window drag
//  that must orbit without touching the selection.

#if canImport(AppKit) && canImport(RealityKit)

import AppKit
import Foundation
import GamaAppleUI
import GamaAuthoring
import GamaStudioEditor
import RealityKit
import Testing

private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tolerance: Float = 1e-3) -> Bool {
    let d = a - b
    return abs(d.x) <= tolerance && abs(d.y) <= tolerance && abs(d.z) <= tolerance
}

/// A scroll event as the named device sends it: a notched wheel reports
/// line units and non-continuous deltas; a trackpad reports pixel units
/// with the continuous flag, which AppKit exposes as
/// `hasPreciseScrollingDeltas`.
private func scrollEvent(dx: Int32, dy: Int32, trackpad: Bool, shift: Bool = false) throws -> NSEvent {
    let cg = try #require(CGEvent(
        scrollWheelEvent2Source: nil, units: trackpad ? .pixel : .line,
        wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0
    ))
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: trackpad ? 1 : 0)
    if shift { cg.flags = .maskShift }
    return try #require(NSEvent(cgEvent: cg))
}

@MainActor
@Suite("Viewport camera")
struct ViewportCameraTests {
    @Test func cameraEntityFollowsTheOrbit() {
        let viewport = ViewportController(model: StudioModel(document: StudioModel.sampleScene()), onSelectionChange: {})
        #expect(close(viewport.camera.position(relativeTo: nil), SIMD3(0, 3, 7)))

        viewport.orbit(byDragX: 120, dragY: 0)
        #expect(viewport.orbit.yaw < 0, "dragging right turns the eye toward -X")
        #expect(close(viewport.camera.position(relativeTo: nil), viewport.orbit.position))

        let target = viewport.orbit.target
        viewport.pan(byDragX: -50, dragY: 0)
        #expect(!close(viewport.orbit.target, target))
        #expect(close(viewport.camera.position(relativeTo: nil), viewport.orbit.position))

        let distance = viewport.orbit.distance
        viewport.magnify(by: 0.5)
        #expect(viewport.orbit.distance < distance)
        let closer = viewport.orbit.distance
        viewport.magnify(by: -0.99)          // a collapse this large is ignored
        #expect(viewport.orbit.distance == closer)
    }

    @Test func mouseWheelZoomsAndTrackpadScrollOrbits() throws {
        let viewport = ViewportController(model: StudioModel(document: StudioModel.sampleScene()), onSelectionChange: {})
        let start = viewport.orbit

        let wheel = try scrollEvent(dx: 0, dy: 3, trackpad: false)
        #expect(!wheel.hasPreciseScrollingDeltas)
        viewport.arView.scrollWheel(with: wheel)
        #expect(viewport.orbit.distance < start.distance, "wheel up moves closer")
        #expect(viewport.orbit.yaw == start.yaw)
        #expect(viewport.orbit.target == start.target)

        let afterWheel = viewport.orbit
        let swipe = try scrollEvent(dx: 40, dy: 0, trackpad: true)
        #expect(swipe.hasPreciseScrollingDeltas)
        viewport.arView.scrollWheel(with: swipe)
        #expect(viewport.orbit.yaw != afterWheel.yaw, "a trackpad swipe orbits")
        #expect(viewport.orbit.distance == afterWheel.distance)
        #expect(viewport.orbit.target == afterWheel.target)

        let afterSwipe = viewport.orbit
        let shiftSwipe = try scrollEvent(dx: 40, dy: 0, trackpad: true, shift: true)
        viewport.arView.scrollWheel(with: shiftSwipe)
        #expect(viewport.orbit.target != afterSwipe.target, "Shift + trackpad swipe pans")
        #expect(viewport.orbit.yaw == afterSwipe.yaw)
        #expect(viewport.orbit.distance == afterSwipe.distance)
    }

    /// A real left-drag through `NSWindow.sendEvent` orbits the camera and
    /// does not select: the click recognizer fails once the pointer moves.
    @Test func windowDragOrbitsWithoutSelecting() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = GamaHostView(frame: frame)
        window.contentView = host
        try host.install(app: StudioApp(model: model))
        var changes = 0
        let viewport = ViewportController(model: model, onSelectionChange: { changes += 1 })
        host.attach(viewport.arView, to: StudioApp.viewportRegion)
        host.invalidate()
        window.orderFront(nil)

        let center = NSPoint(x: viewport.arView.bounds.midX, y: viewport.arView.bounds.midY)
        let start = viewport.arView.convert(center, to: nil)
        let yawBefore = viewport.orbit.yaw
        let selectionBefore = model.session.selection.primary

        func send(_ type: NSEvent.EventType, _ point: NSPoint) throws {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            window.sendEvent(event)
        }
        try send(.leftMouseDown, start)
        for step in 1...8 {
            try send(.leftMouseDragged, NSPoint(x: start.x + CGFloat(step) * 10, y: start.y))
        }
        try send(.leftMouseUp, NSPoint(x: start.x + 80, y: start.y))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        #expect(viewport.orbit.yaw != yawBefore, "the drag did not orbit")
        #expect(model.session.selection.primary == selectionBefore, "a drag must not change the selection")
        #expect(changes == 0)
        #expect(close(viewport.camera.position(relativeTo: nil), viewport.orbit.position))
    }
}

#endif
