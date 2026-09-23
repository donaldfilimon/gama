//  HostRedrawTests.swift — GamaStudioEditorTests
//
//  A document change made by a gama button runs inside GamaHostView's own
//  event dispatch. The redraw hooks that repaint the host after outside
//  changes (File > Open) must not invalidate it from there: doing so
//  re-entered the frame pump and trapped on an exclusivity conflict, first
//  seen on iOS as a crash on the inspector's +X button.

#if canImport(AppKit)

import AppKit
import Foundation
import GamaAppleUI
import GamaAuthoring
import GamaDraw
import GamaStudioEditor
import Testing

@MainActor
@Suite("Host redraw")
struct HostRedrawTests {
    @Test func aButtonEditWithTheRedrawHookInstalledDoesNotReenterTheHost() async throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = StudioAppDelegate.makeMainWindow(contentRect: frame)
        defer { window.close() }
        let host = GamaHostView(frame: frame)
        window.contentView = host
        try host.install(app: StudioApp(model: model))
        let delegate = StudioAppDelegate()
        // Wired exactly as gama-studio's main.swift wires it.
        var redraws = 0
        delegate.attach(model: model, window: window, redraw: { redraws += 1; host.invalidate() })
        host.invalidate()
        window.orderFront(nil)
        #expect(window.makeFirstResponder(host))

        // Gama focus starts on "Add Box"; Enter activates it inside the
        // host's event dispatch, and the edit fires onDocumentChange.
        let count = model.session.document.count
        let enter = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        window.sendEvent(enter)
        #expect(model.session.document.count == count + 1)
        #expect(redraws == 0, "not from inside the host's dispatch")
        for _ in 0..<10 { await Task.yield() }
        #expect(redraws == 1, "but right after it")
        #expect(!host.currentDrawList.commands.isEmpty)
    }
}
#endif
