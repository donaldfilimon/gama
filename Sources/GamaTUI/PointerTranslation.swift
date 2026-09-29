//  PointerTranslation.swift — GamaTUI
//  Pure translation from terminal mouse reports to `PointerEvent` samples
//  (ADR 0018). Deliberately outside every platform `#if`: the SGR decoder is
//  what the POSIX terminal feeds, the Windows translators are what the
//  console backend feeds, and both are plain integer logic that compiles and
//  is unit-tested on every host. FrameHost, not this file, decides what a
//  sample means.
//
//  Scroll sign (shared by every backend): positive `scroll.y` reveals the
//  lines below, positive `scroll.x` the columns to the right.

import GamaCore

/// Decodes one SGR (`?1006`) mouse report: `CSI < b ; column ; row M` for a
/// press or motion, `m` for a release.
///
/// Bits of `b`: 0-1 the button (0 left, 1 middle, 2 right, 3 none), +4
/// shift, +8 alt, +16 ctrl, +32 motion, +64 the wheel (64 up, 65 down,
/// 66 left, 67 right). Extended buttons (+128) are not decoded. Terminals
/// report no clock, so samples carry no timestamp; the terminal idiom has no
/// long press anyway.
enum SGRMouse {
    /// The sample for `parameters` (the text between `CSI` and the final
    /// byte, starting with `<`), or `nil` for a malformed or unsupported
    /// report. `release` is `true` for the `m` final byte.
    static func decode(_ parameters: String, release: Bool) -> InputEvent? {
        guard parameters.hasPrefix("<") else { return nil }
        let fields = parameters.dropFirst().split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count == 3, let code = Int(fields[0]), let column = Int(fields[1]),
            let row = Int(fields[2]), code >= 0, code < 128
        else { return nil }
        let location = Point(x: column - 1, y: row - 1)
        var modifiers: PointerEvent.Modifiers = []
        if code & 4 != 0 { modifiers.insert(.shift) }
        if code & 8 != 0 { modifiers.insert(.option) }
        if code & 16 != 0 { modifiers.insert(.control) }
        let low = code & 3

        if code & 64 != 0 {
            // Wheels report presses only; a release report is not a scroll.
            guard !release else { return nil }
            let scroll: Point
            switch low {
            case 0: scroll = Point(x: 0, y: -1)
            case 1: scroll = Point(x: 0, y: 1)
            case 2: scroll = Point(x: -1, y: 0)
            default: scroll = Point(x: 1, y: 0)
            }
            return .pointerEvent(PointerEvent(
                phase: .scroll, location: location, modifiers: modifiers, scroll: scroll))
        }
        if code & 32 != 0 {
            guard low != 3 else {
                return .pointerEvent(PointerEvent(phase: .hover, location: location, modifiers: modifiers))
            }
            return .pointerEvent(PointerEvent(
                phase: .move, location: location, button: button(low), modifiers: modifiers))
        }
        // SGR names the released button, so a press or release without one
        // is not a report this decoder understands.
        guard low != 3 else { return nil }
        return .pointerEvent(PointerEvent(
            phase: release ? .up : .down, location: location, button: button(low),
            modifiers: modifiers))
    }

    /// SGR numbers the middle button 1 and the right button 2; Gama numbers
    /// the secondary (right) button 1 and the middle button 2.
    private static func button(_ low: Int) -> Int {
        switch low {
        case 1: return 2
        case 2: return 1
        default: return 0
        }
    }
}

/// Pure translation from Windows console key records to `InputEvent`s, kept
/// free of console handles (and of WinSDK names) so it can be exercised on
/// every host.
enum WindowsInputTranslator {
    static func key(virtualKey: UInt16, scalar: UInt16, controlState: UInt32) -> InputEvent? {
        let shift = controlState & 0x0010 != 0
        let ctrl = controlState & (0x0008 | 0x0004) != 0

        switch Int32(virtualKey) {
        case 0x25: return .key(.left)
        case 0x26: return .key(.up)
        case 0x27: return .key(.right)
        case 0x28: return .key(.down)
        case 0x0D: return .key(.enter)
        case 0x1B: return .key(.escape)
        case 0x09: return .key(shift ? .backTab : .tab)
        case 0x08: return .key(.backspace)
        case 0x2E: return .key(.delete)
        case 0x24: return .key(.home)
        case 0x23: return .key(.end)
        case 0x21: return .key(.pageUp)
        case 0x22: return .key(.pageDown)
        case 0x70...0x7B: return .key(.function(Int(virtualKey) - 0x70 + 1))
        default: break
        }

        guard scalar != 0, let unicode = Unicode.Scalar(UInt32(scalar)) else { return nil }
        let character = Character(unicode)
        if ctrl, character.isLetter {
            return .key(.ctrl(Character(character.lowercased())))
        }
        if scalar >= 0x01, scalar <= 0x1A, character != "\t", character != "\r" {
            return .key(.ctrl(Character(UnicodeScalar(UInt8(scalar) + 0x60))))
        }
        return .key(.character(character))
    }
}

/// Translates Windows console `MOUSE_EVENT_RECORD`s into pointer samples.
///
/// A console press or release record reports the *current* button state,
/// not which button changed, so the translator keeps the last state it saw.
/// One record yields at most one sample: when two buttons change in the same
/// record, the lowest changed bit is reported and the other is picked up by
/// the next press or release record. Flag and mask values are the WinCon.h
/// literals, spelled out so this compiles without WinSDK.
struct WindowsMouseTranslator {
    // dwEventFlags
    private static let mouseMoved: UInt32 = 0x0001
    private static let doubleClick: UInt32 = 0x0002
    private static let mouseWheeled: UInt32 = 0x0004
    private static let mouseHWheeled: UInt32 = 0x0008
    // dwButtonState: left, rightmost, second from left.
    private static let trackedButtons: UInt32 = 0x0007

    /// The button bits held as of the last press or release record.
    private(set) var buttons: UInt32 = 0

    /// Translates one record; `nil` when it carries no sample (a record
    /// whose tracked buttons did not change, or an unknown flag).
    mutating func translate(
        x: Int16, y: Int16, buttonState: UInt32, controlState: UInt32, eventFlags: UInt32
    ) -> InputEvent? {
        let location = Point(x: Int(x), y: Int(y))
        let modifiers = Self.modifiers(controlState)
        switch eventFlags {
        case 0, Self.doubleClick:
            // A double-click record is the second press of the pair.
            let changed = (buttonState ^ buttons) & Self.trackedButtons
            guard changed != 0 else { return nil }
            let bit = changed & (~changed &+ 1)
            buttons ^= bit
            return .pointerEvent(PointerEvent(
                phase: buttonState & bit != 0 ? .down : .up, location: location,
                button: Self.button(bit), modifiers: modifiers))
        case Self.mouseMoved:
            let held = buttons & Self.trackedButtons
            guard held != 0 else {
                return .pointerEvent(PointerEvent(phase: .hover, location: location, modifiers: modifiers))
            }
            return .pointerEvent(PointerEvent(
                phase: .move, location: location, button: Self.button(held & (~held &+ 1)),
                modifiers: modifiers))
        case Self.mouseWheeled, Self.mouseHWheeled:
            // The high word is the signed wheel delta: positive is away from
            // the user (scroll up) for the vertical wheel and to the right
            // for the horizontal one, in 120-unit notches.
            let delta = Int(Int16(truncatingIfNeeded: buttonState >> 16))
            guard delta != 0 else { return nil }
            let notches = delta / 120 != 0 ? delta / 120 : (delta > 0 ? 1 : -1)
            let scroll =
                eventFlags == Self.mouseWheeled ? Point(x: 0, y: -notches) : Point(x: notches, y: 0)
            return .pointerEvent(PointerEvent(
                phase: .scroll, location: location, modifiers: modifiers, scroll: scroll))
        default:
            return nil
        }
    }

    /// Left is primary (0), rightmost is secondary (1), second from left is
    /// middle (2).
    private static func button(_ bit: UInt32) -> Int {
        switch bit {
        case 0x0002: return 1
        case 0x0004: return 2
        default: return 0
        }
    }

    /// `dwControlKeyState`: shift 0x10, left/right ctrl 0x8/0x4, left/right
    /// alt 0x2/0x1.
    private static func modifiers(_ controlState: UInt32) -> PointerEvent.Modifiers {
        var modifiers: PointerEvent.Modifiers = []
        if controlState & 0x0010 != 0 { modifiers.insert(.shift) }
        if controlState & (0x0008 | 0x0004) != 0 { modifiers.insert(.control) }
        if controlState & (0x0002 | 0x0001) != 0 { modifiers.insert(.option) }
        return modifiers
    }
}
