//  ViewportNotesTests.swift — GamaStudioEditorTests
//
//  Viewport events kept in the console log as notes (ADR 0018), driven
//  through the AppKit viewport: picking, Frame, Look through, and camera
//  moves, including a real window drag. The touch viewport shares the note
//  helpers in ViewportSupport and is checked by the gate's simulator smoke.

#if canImport(AppKit) && canImport(RealityKit)

import AppKit
import GamaAppleUI
import GamaAuthoring
import GamaReality
import GamaStudioEditor
import RealityKit
import Testing

@MainActor
private func sampleID(named name: String, in model: StudioModel) -> EntityID? {
    model.session.document.entities.values.first { $0.name == name }?.id
}

@MainActor
@Suite("Viewport notes")
struct ViewportNotesTests {
    func notes(_ model: StudioModel) -> [String] {
        model.consoleLog.filter(\.isNote).map(\.output)
    }

    func makeViewport(_ model: StudioModel) -> ViewportController {
        let viewport = ViewportController(model: model, onSelectionChange: {})
        viewport.arView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        return viewport
    }

    @Test func settingUpTheViewportLogsNothing() {
        let model = StudioModel(document: StudioModel.sampleScene())
        _ = makeViewport(model)
        #expect(model.consoleLog.isEmpty)
    }

    @Test func pickingNotesWhatWasPickedAndClearing() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = makeViewport(model)
        let box = try #require(sampleID(named: "Box", in: model))
        let boxEntity = try #require(model.bridge.entity(for: box))
        let point = try #require(viewport.arView.project(boxEntity.position(relativeTo: nil)))

        viewport.pick(at: point)
        viewport.pick(at: point)
        #expect(notes(model) == ["picked Box"], "the same pick twice is one line")
        viewport.pick(at: CGPoint(x: 2, y: viewport.arView.bounds.height - 2))
        #expect(notes(model) == ["picked Box", "cleared selection"])
    }

    @Test func selectingFromThePanelOrConsoleIsNotAViewportEvent() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        _ = makeViewport(model)
        model.select(try #require(sampleID(named: "Box", in: model)))
        model.runConsole("select Sphere")
        #expect(notes(model).isEmpty)
    }

    @Test func frameNotesItsSubject() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = makeViewport(model)
        viewport.frameSelection()
        model.select(try #require(sampleID(named: "Sphere", in: model)))
        viewport.frameSelection()
        #expect(notes(model) == ["framed the scene", "framed Sphere"])
    }

    @Test func lookThroughNotesTheCameraAndIgnoresNonCameras() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = makeViewport(model)
        viewport.lookThrough(try #require(sampleID(named: "Box", in: model)))
        #expect(notes(model).isEmpty, "not a camera: nothing happened, so nothing is noted")
        viewport.lookThrough(try #require(sampleID(named: "Camera", in: model)))
        #expect(notes(model) == ["looking through Camera"])
    }

    @Test func cameraMovesCoalesceIntoOneLine() {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = makeViewport(model)
        viewport.orbit(byDragX: 10, dragY: 0)
        viewport.pan(byDragX: 5, dragY: 5)
        viewport.zoom(scale: 0.9)
        viewport.magnify(by: 0.1)
        #expect(notes(model) == ["moved the camera"])
        viewport.frameSelection()
        viewport.orbit(byDragX: 10, dragY: 0)
        #expect(notes(model) == ["moved the camera", "framed the scene", "moved the camera"])
    }

    /// A real drag through `NSWindow.sendEvent` notes one camera move, and
    /// no pick, because a drag does not select.
    @Test func aWindowDragNotesOneCameraMove() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = GamaHostView(frame: frame)
        window.contentView = host
        try host.install(app: StudioApp(model: model))
        let viewport = ViewportController(model: model, onSelectionChange: {})
        host.attach(viewport.arView, to: StudioApp.viewportRegion)
        host.invalidate()
        window.orderFront(nil)

        let start = viewport.arView.convert(NSPoint(x: viewport.arView.bounds.midX, y: viewport.arView.bounds.midY), to: nil)
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

        #expect(notes(model) == ["moved the camera"])
    }
}
#endif
