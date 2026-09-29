//  PointerBackendTests.swift — backend translation into `PointerEvent`
//  (ADR 0018, dock phase 2): the shared C/WASM wire decoder, the terminal
//  SGR decoder, the Windows console mouse translator, and the scroll sign
//  convention every backend must agree on.

import GamaCore
@testable import GamaDraw
@testable import GamaTUI
import Testing

@Suite("Pointer wire codes (C embed and WASM v3)")
struct PointerWireTests {
    @Test("every phase and kind code decodes, with location, scroll, modifiers and clock")
    func decodesEveryCode() {
        let phases: [PointerEvent.Phase] = [.down, .move, .up, .cancel, .hover, .scroll, .stationary]
        for (code, phase) in phases.enumerated() {
            let event = PointerWire.event(
                phase: Int32(code), kind: 0, button: 0, modifiers: 0,
                column: 3, row: 4, scrollColumns: 0, scrollRows: 0,
                pointerID: 0, timestampMillis: -1)
            #expect(event?.phase == phase)
        }
        let kinds: [PointerEvent.Kind] = [.mouse, .touch, .pen]
        for (code, kind) in kinds.enumerated() {
            let event = PointerWire.event(
                phase: 0, kind: Int32(code), button: 0, modifiers: 0,
                column: 0, row: 0, scrollColumns: 0, scrollRows: 0,
                pointerID: 0, timestampMillis: -1)
            #expect(event?.kind == kind)
        }
        let full = PointerWire.event(
            phase: 5, kind: 1, button: 2, modifiers: 0b1111,
            column: -1, row: 7, scrollColumns: -2, scrollRows: 3,
            pointerID: 9, timestampMillis: 1234)
        #expect(full == PointerEvent(
            phase: .scroll, location: Point(x: -1, y: 7), kind: .touch, button: 2,
            modifiers: [.shift, .control, .option, .command], scroll: Point(x: -2, y: 3),
            pointerID: 9, timestampMillis: 1234))
    }

    @Test("a negative timestamp means no clock")
    func negativeTimestampIsNoClock() {
        let event = PointerWire.event(
            phase: 0, kind: 0, button: 0, modifiers: 0, column: 0, row: 0,
            scrollColumns: 0, scrollRows: 0, pointerID: 0, timestampMillis: -5)
        #expect(event != nil)
        #expect(event?.timestampMillis == nil)
    }

    @Test("unknown phase, kind, button or modifier bits are rejected")
    func rejectsInvalidCodes() {
        func decode(phase: Int32 = 0, kind: Int32 = 0, button: Int32 = 0, modifiers: Int32 = 0) -> PointerEvent? {
            PointerWire.event(
                phase: phase, kind: kind, button: button, modifiers: modifiers,
                column: 0, row: 0, scrollColumns: 0, scrollRows: 0,
                pointerID: 0, timestampMillis: -1)
        }
        #expect(decode(phase: 7) == nil)
        #expect(decode(phase: -1) == nil)
        #expect(decode(kind: 3) == nil)
        #expect(decode(button: -1) == nil)
        #expect(decode(button: 32) == nil)
        #expect(decode(modifiers: 16) == nil)
        #expect(decode(modifiers: -1) == nil)
    }

    @Test("a JavaScript clock converts to milliseconds without trapping")
    func javaScriptClock() {
        #expect(PointerWire.timestampMillis(fromJavaScript: 1500.75) == 1500)
        #expect(PointerWire.timestampMillis(fromJavaScript: 0) == 0)
        #expect(PointerWire.timestampMillis(fromJavaScript: -1) == -1)
        #expect(PointerWire.timestampMillis(fromJavaScript: .nan) == -1)
        #expect(PointerWire.timestampMillis(fromJavaScript: .infinity) == -1)
        #expect(PointerWire.timestampMillis(fromJavaScript: 1e300) == -1)
    }

    @Test("a deadline beyond Int64 saturates for the C ABI")
    func deadlineSaturates() {
        #expect(PointerWire.deadline(nil) == -1)
        #expect(PointerWire.deadline(500) == 500)
        #expect(PointerWire.deadline(.max) == .max)
    }
}

@Suite("Terminal SGR mouse decoding")
struct SGRMouseTests {
    private func decode(_ params: String, release: Bool = false) -> InputEvent? {
        SGRMouse.decode(params, release: release)
    }

    private func sample(
        _ phase: PointerEvent.Phase, _ x: Int, _ y: Int, button: Int = 0,
        modifiers: PointerEvent.Modifiers = [], scroll: Point = .zero
    ) -> InputEvent {
        .pointerEvent(PointerEvent(
            phase: phase, location: Point(x: x, y: y), button: button,
            modifiers: modifiers, scroll: scroll))
    }

    @Test("presses and releases map buttons to primary, middle, secondary")
    func buttons() {
        #expect(decode("<0;10;5") == sample(.down, 9, 4))
        #expect(decode("<0;10;5", release: true) == sample(.up, 9, 4))
        #expect(decode("<1;1;1") == sample(.down, 0, 0, button: 2))
        #expect(decode("<2;1;1") == sample(.down, 0, 0, button: 1))
        #expect(decode("<2;1;1", release: true) == sample(.up, 0, 0, button: 1))
    }

    @Test("modifier bits: +4 shift, +8 alt, +16 ctrl")
    func modifiers() {
        #expect(decode("<4;2;2") == sample(.down, 1, 1, modifiers: .shift))
        #expect(decode("<8;2;2") == sample(.down, 1, 1, modifiers: .option))
        #expect(decode("<16;2;2") == sample(.down, 1, 1, modifiers: .control))
        #expect(decode("<28;2;2") == sample(.down, 1, 1, modifiers: [.shift, .option, .control]))
    }

    @Test("+32 is motion: a held button moves, no button hovers")
    func motion() {
        #expect(decode("<32;6;3") == sample(.move, 5, 2))
        #expect(decode("<34;6;3") == sample(.move, 5, 2, button: 1))
        #expect(decode("<35;6;3") == sample(.hover, 5, 2))
        #expect(decode("<36;6;3") == sample(.move, 5, 2, modifiers: .shift))
    }

    @Test("64-67 are the wheel: up, down, left, right")
    func wheel() {
        #expect(decode("<64;3;3") == sample(.scroll, 2, 2, scroll: Point(x: 0, y: -1)))
        #expect(decode("<65;3;3") == sample(.scroll, 2, 2, scroll: Point(x: 0, y: 1)))
        #expect(decode("<66;3;3") == sample(.scroll, 2, 2, scroll: Point(x: -1, y: 0)))
        #expect(decode("<67;3;3") == sample(.scroll, 2, 2, scroll: Point(x: 1, y: 0)))
        #expect(decode("<69;3;3") == sample(.scroll, 2, 2, modifiers: .shift, scroll: Point(x: 0, y: 1)))
        // A wheel never reports a release.
        #expect(decode("<64;3;3", release: true) == nil)
    }

    @Test("malformed or unsupported reports decode to nothing")
    func malformed() {
        #expect(decode("0;1;1") == nil)
        #expect(decode("<0;1") == nil)
        #expect(decode("<x;1;1") == nil)
        #expect(decode("<3;1;1") == nil)  // a press with no button
        #expect(decode("<128;1;1") == nil)  // extended buttons 8-11
    }
}

@Suite("Windows console mouse translation")
struct WindowsMouseTranslatorTests {
    @Test("button transitions become down and up for the button that changed")
    func buttonTransitions() {
        var mouse = WindowsMouseTranslator()
        #expect(mouse.translate(x: 7, y: 4, buttonState: 0x1, controlState: 0, eventFlags: 0)
            == .pointerEvent(PointerEvent(phase: .down, location: Point(x: 7, y: 4))))
        #expect(mouse.translate(x: 7, y: 4, buttonState: 0x3, controlState: 0, eventFlags: 0)
            == .pointerEvent(PointerEvent(phase: .down, location: Point(x: 7, y: 4), button: 1)))
        #expect(mouse.translate(x: 7, y: 4, buttonState: 0x1, controlState: 0, eventFlags: 0)
            == .pointerEvent(PointerEvent(phase: .up, location: Point(x: 7, y: 4), button: 1)))
        #expect(mouse.translate(x: 7, y: 4, buttonState: 0x0, controlState: 0, eventFlags: 0)
            == .pointerEvent(PointerEvent(phase: .up, location: Point(x: 7, y: 4))))
        #expect(mouse.translate(x: 1, y: 1, buttonState: 0x4, controlState: 0, eventFlags: 0)
            == .pointerEvent(PointerEvent(phase: .down, location: Point(x: 1, y: 1), button: 2)))
    }

    @Test("a double-click record is the second press, not an ignored record")
    func doubleClick() {
        var mouse = WindowsMouseTranslator()
        _ = mouse.translate(x: 2, y: 2, buttonState: 0x1, controlState: 0, eventFlags: 0)
        _ = mouse.translate(x: 2, y: 2, buttonState: 0x0, controlState: 0, eventFlags: 0)
        #expect(mouse.translate(x: 2, y: 2, buttonState: 0x1, controlState: 0, eventFlags: 0x2)
            == .pointerEvent(PointerEvent(phase: .down, location: Point(x: 2, y: 2))))
    }

    @Test("MOUSE_MOVED moves while a button is held and hovers otherwise")
    func moved() {
        var mouse = WindowsMouseTranslator()
        #expect(mouse.translate(x: 3, y: 1, buttonState: 0, controlState: 0, eventFlags: 0x1)
            == .pointerEvent(PointerEvent(phase: .hover, location: Point(x: 3, y: 1))))
        _ = mouse.translate(x: 3, y: 1, buttonState: 0x1, controlState: 0, eventFlags: 0)
        #expect(mouse.translate(x: 5, y: 1, buttonState: 0x1, controlState: 0, eventFlags: 0x1)
            == .pointerEvent(PointerEvent(phase: .move, location: Point(x: 5, y: 1))))
    }

    @Test("MOUSE_WHEELED and MOUSE_HWHEELED scroll by notch, with modifiers")
    func wheel() {
        var mouse = WindowsMouseTranslator()
        let away = UInt32(120) << 16  // wheel rotated away from the user
        let toward = UInt32(UInt16(bitPattern: -240)) << 16
        #expect(mouse.translate(x: 0, y: 0, buttonState: away, controlState: 0, eventFlags: 0x4)
            == .pointerEvent(PointerEvent(phase: .scroll, location: .zero, scroll: Point(x: 0, y: -1))))
        #expect(mouse.translate(x: 0, y: 0, buttonState: toward, controlState: 0x10, eventFlags: 0x4)
            == .pointerEvent(PointerEvent(
                phase: .scroll, location: .zero, modifiers: .shift, scroll: Point(x: 0, y: 2))))
        #expect(mouse.translate(x: 0, y: 0, buttonState: away, controlState: 0, eventFlags: 0x8)
            == .pointerEvent(PointerEvent(phase: .scroll, location: .zero, scroll: Point(x: 1, y: 0))))
    }

    @Test("control-key state becomes modifiers")
    func modifiers() {
        var mouse = WindowsMouseTranslator()
        #expect(mouse.translate(x: 0, y: 0, buttonState: 0x1, controlState: 0x10 | 0x8 | 0x2, eventFlags: 0)
            == .pointerEvent(PointerEvent(
                phase: .down, location: .zero, modifiers: [.shift, .control, .option])))
    }
}

@Suite("Scroll sign convention across backends")
struct ScrollConventionTests {
    /// One physical gesture, "reveal the lines below", must reach FrameHost as
    /// the same `+1` row delta from every translator (ADR 0018: no fork).
    @Test("scrolling down is +1 row from SGR, Windows and the wire")
    func scrollDownAgrees() {
        let sgr = SGRMouse.decode("<65;1;1", release: false)
        var windows = WindowsMouseTranslator()
        let win = windows.translate(
            x: 0, y: 0, buttonState: UInt32(UInt16(bitPattern: -120)) << 16,
            controlState: 0, eventFlags: 0x4)
        let wire = PointerWire.event(
            phase: 5, kind: 0, button: 0, modifiers: 0, column: 0, row: 0,
            scrollColumns: 0, scrollRows: 1, pointerID: 0, timestampMillis: -1)
        for event in [sgr, win, wire.map(InputEvent.pointerEvent)] {
            guard case .pointerEvent(let sample)? = event else {
                Issue.record("expected a pointer sample, got \(String(describing: event))")
                continue
            }
            #expect(sample.phase == .scroll)
            #expect(sample.scroll == Point(x: 0, y: 1))
        }
    }
}

@Suite("Backend interaction idioms")
struct BackendIdiomTests {
    private struct QuietRenderer: Renderer {
        var size: Size { Size(width: 1, height: 1) }
        mutating func present(_ root: LaidOutNode) {}
        mutating func nextEvent(timeoutMillis: Int) -> InputEvent? { nil }
        mutating func begin() {}
        mutating func end() {}
    }

    @Test("a renderer is desktop-class unless it says otherwise; the TUI is a terminal")
    func idioms() {
        #expect(QuietRenderer().interactionIdiom == .desktop)
        #expect(TUIRenderer().interactionIdiom == .terminal)
    }
}
