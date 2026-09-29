//  PointerWire.swift — GamaDraw
//  The integer wire form of a `PointerEvent` shared by the C embed ABI
//  (`gama_embed_v1_pointer_event`) and the WASM v3 export
//  (`gama_web_v3_pointer_event`). One decoder, so the two flat ABIs cannot
//  drift apart. Integer-only and stdlib-only: GamaDraw is in the portable
//  libm scan.

package import GamaCore

/// Decodes the flat integer pointer codes the C and WASM ABIs carry.
///
/// Codes (mirrored as `GAMA_EMBED_POINTER_*` in `GamaEmbed.h` and as a table
/// in the web host's `gama.js`):
/// - phase: 0 down, 1 move, 2 up, 3 cancel, 4 hover, 5 scroll, 6 stationary
/// - kind: 0 mouse, 1 touch, 2 pen
/// - button: 0 primary, 1 secondary, 2 middle, up to 31
/// - modifiers: bit 0 shift, 1 control, 2 option, 3 command
/// - timestamp: monotonic milliseconds, negative for no clock
package enum PointerWire {
    /// The largest button number the wire accepts.
    package static let maximumButton: Int32 = 31

    /// The decoded sample, or `nil` when a code is outside the tables above.
    package static func event(
        phase: Int32, kind: Int32, button: Int32, modifiers: Int32,
        column: Int32, row: Int32, scrollColumns: Int32, scrollRows: Int32,
        pointerID: Int32, timestampMillis: Int64
    ) -> PointerEvent? {
        let decodedPhase: PointerEvent.Phase
        switch phase {
        case 0: decodedPhase = .down
        case 1: decodedPhase = .move
        case 2: decodedPhase = .up
        case 3: decodedPhase = .cancel
        case 4: decodedPhase = .hover
        case 5: decodedPhase = .scroll
        case 6: decodedPhase = .stationary
        default: return nil
        }
        let decodedKind: PointerEvent.Kind
        switch kind {
        case 0: decodedKind = .mouse
        case 1: decodedKind = .touch
        case 2: decodedKind = .pen
        default: return nil
        }
        guard (0...maximumButton).contains(button), (0...0b1111).contains(modifiers) else {
            return nil
        }
        return PointerEvent(
            phase: decodedPhase,
            location: Point(x: Int(column), y: Int(row)),
            kind: decodedKind,
            button: Int(button),
            modifiers: PointerEvent.Modifiers(rawValue: UInt8(modifiers)),
            scroll: Point(x: Int(scrollColumns), y: Int(scrollRows)),
            pointerID: Int(pointerID),
            timestampMillis: timestampMillis < 0 ? nil : UInt64(timestampMillis))
    }

    /// A JavaScript clock reading (`performance.now()`, fractional
    /// milliseconds) as whole milliseconds, or `-1` when it is not a finite,
    /// non-negative value that fits: a float-to-integer conversion traps on
    /// NaN, infinity and overflow in wasm, so none of those reach it.
    package static func timestampMillis(fromJavaScript value: Double) -> Int64 {
        guard value.isFinite, value >= 0, value < 9_000_000_000_000_000_000 else { return -1 }
        return Int64(value)
    }

    /// A host deadline for the C ABI: `-1` for none, saturating at
    /// `Int64.max` rather than wrapping.
    package static func deadline(_ millis: UInt64?) -> Int64 {
        guard let millis else { return -1 }
        return millis > UInt64(Int64.max) ? .max : Int64(millis)
    }
}
