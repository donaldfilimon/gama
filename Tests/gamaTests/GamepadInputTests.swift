//  GamepadInputTests.swift — controller buttons reach the same semantic
//  operations as the keyboard: the d-pad routes through the focused node's
//  key handler before spatial focus navigation, and the confirm button
//  activates. A release, and a button with no mapping, do nothing.

import Testing

@testable import GamaCore

private struct PadNavApp: App {
    let text = Signal("")
    let counter = Signal(0)
    init() {}

    var scenes: some Scene {
        Window("Pad", id: "main", role: .primary) {
            VStack(spacing: 1) {
                TextField("Name", text: text.binding())
                Button("Go") { counter.update { $0 += 1 } }
            }
        }
    }
}

private struct PadButtonApp: App {
    let counter = Signal(0)
    init() {}

    var scenes: some Scene {
        Window("Pad", id: "main", role: .primary) {
            Button("Go") { counter.update { $0 += 1 } }
        }
    }
}

@Suite("Gamepad input")
struct GamepadInputTests {
    @Test("the confirm button activates the focused node like Enter")
    func confirmActivates() throws {
        let app = PadButtonApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.gamepad(.south, pressed: true))
        #expect(app.counter.get() == 1)
    }

    @Test("a button release performs no action")
    func releaseDoesNothing() throws {
        let app = PadButtonApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        let cleanAfterPump = host.needsFrame
        #expect(!cleanAfterPump)
        host.handle(.gamepad(.south, pressed: false))
        let dirtyAfterRelease = host.needsFrame
        #expect(!dirtyAfterRelease)
        #expect(app.counter.get() == 0)
    }

    @Test("a button with no host mapping performs no action")
    func unmappedButtonDoesNothing() throws {
        let app = PadButtonApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.gamepad(.start, pressed: true))
        #expect(app.counter.get() == 0)
        host.handle(.gamepad(.south, pressed: true))
        #expect(app.counter.get() == 1)
    }

    @Test("the d-pad moves focus spatially when the focused node declines it")
    func dpadMovesFocus() throws {
        let app = PadNavApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.gamepad(.dpadDown, pressed: true))
        _ = host.pump(size: Size(width: 40, height: 8))
        host.handle(.gamepad(.south, pressed: true))
        #expect(app.counter.get() == 1)
    }

    @Test("the d-pad moves the caret inside a focused TextField, not focus")
    func dpadMovesCaretInTextField() throws {
        let app = PadNavApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 8))
        for character in "abc" { host.handle(.key(.character(character))) }
        host.handle(.gamepad(.dpadLeft, pressed: true))
        host.handle(.key(.character("X")))
        // The field consumed the d-pad exactly as it consumes `.left`, so
        // the caret moved instead of focus leaving for the button.
        #expect(app.text.get() == "abXc")
        #expect(app.counter.get() == 0)
    }
}
