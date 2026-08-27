//  DrawList.swift — GamaDraw
//  Backend-neutral vector commands, run-merged from a CellBuffer.
//  GUI hosts (CoreGraphics, Canvas2D, Skia, NDK) scale by their cell
//  metrics; the C embed ABI ships the same list as a flat byte buffer.

import GamaCore

public enum DrawCommand: Hashable, Sendable {
    /// Grid-space rect (cells, not pixels) filled with a solid color.
    case fillRect(Rect, Color)
    /// A run of monospaced text at a grid position.
    case text(String, at: Point, style: TextStyle)
}

public struct DrawList: Hashable, Sendable {
    public var size: Size
    public var commands: [DrawCommand]

    public init(size: Size, commands: [DrawCommand] = []) {
        self.size = size
        self.commands = commands
    }

    /// Vectorize a painted CellBuffer: adjacent same-style cells merge
    /// into one background rect + one text run; blank default runs are
    /// skipped entirely, so a mostly-empty frame is a handful of commands.
    public static func from(_ buffer: CellBuffer) -> DrawList {
        var commands: [DrawCommand] = []
        buffer.forEachRun { row, col, width, text, style in
            let isBlankText = text.allSatisfy { $0 == " " }
            if !style.background.isDefault {
                commands.append(
                    .fillRect(Rect(x: col, y: row, width: width, height: 1), style.background))
            } else if isBlankText && style.foreground.isDefault && style.attributes.isEmpty {
                return  // fully default blank run — nothing to draw
            }
            if !isBlankText {
                // Leading blanks are always the space character (width 1),
                // so the character count IS the column offset.
                let leading = text.prefix(while: { $0 == " " }).count
                let visible = String(
                    text.dropFirst(leading).reversed().drop(while: { $0 == " " }).reversed()
                )
                if !visible.isEmpty {
                    commands.append(.text(visible, at: Point(x: col + leading, y: row), style: style))
                }
            }
        }
        return DrawList(size: buffer.size, commands: commands)
    }

    // MARK: Flat binary encoding (C embed ABI)
    //
    // Little-endian stream:
    //   header:  u32 magic 'GAMA' (0x414D4147) · u32 version=1
    //            i32 gridW · i32 gridH · u32 commandCount
    //   command: u8 kind (0=fillRect, 1=text)
    //     fillRect: i32 x,y,w,h · u8 r,g,b · u8 flags(bit0=isDefault)
    //     text:     i32 x,y · style(fg rgb+flags, bg rgb+flags, u16 sgr)
    //               u32 byteLen · UTF-8 bytes
    // Hosts on any language decode with a 40-line reader; see README.

    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        // Header is 20 bytes; a text command averages well under 40.
        out.reserveCapacity(20 + commands.count * 40)
        Self.appendU32(&out, 0x414D_4147)
        Self.appendU32(&out, 1)
        Self.appendI32(&out, Self.clampedI32(size.width))
        Self.appendI32(&out, Self.clampedI32(size.height))
        Self.appendU32(&out, UInt32(commands.count))
        for c in commands {
            switch c {
            case .fillRect(let r, let color):
                out.append(0)
                Self.appendI32(&out, Self.clampedI32(r.minX))
                Self.appendI32(&out, Self.clampedI32(r.minY))
                Self.appendI32(&out, Self.clampedI32(r.size.width))
                Self.appendI32(&out, Self.clampedI32(r.size.height))
                Self.appendColor(&out, color)
            case .text(let s, let p, let style):
                out.append(1)
                Self.appendI32(&out, Self.clampedI32(p.x))
                Self.appendI32(&out, Self.clampedI32(p.y))
                Self.appendColor(&out, style.foreground)
                Self.appendColor(&out, style.background)
                Self.appendU16(&out, UInt16(style.attributes.rawValue))
                let bytes = Array(s.utf8)
                Self.appendU32(&out, UInt32(bytes.count))
                out.append(contentsOf: bytes)
            }
        }
        return out
    }

    /// Why ``decode(_:)`` rejected a payload — one case per distinct
    /// wire-format violation, so embedding hosts can report the actual
    /// fault instead of a bare nil.
    public enum DecodeError: Error, Hashable, Sendable {
        /// The payload ended before a complete header or command was read.
        case truncated
        /// The leading magic was not `GAMA`.
        case badMagic
        /// The header named a wire-format revision this decoder does not speak.
        case unsupportedVersion(UInt32)
        /// The grid dimensions were negative.
        case negativeDimensions
        /// The declared command count cannot fit in the remaining payload.
        case commandCountOverflow
        /// A command byte named an unknown kind.
        case unknownCommandKind(UInt8)
        /// A fill rect carried a negative width or height.
        case negativeRect
        /// A text payload was not valid UTF-8.
        case invalidUTF8
        /// Bytes remained after the declared command count was decoded.
        case trailingBytes
    }

    public static func decode(_ bytes: [UInt8]) throws(DecodeError) -> DrawList {
        // The smallest possible command is a 17-byte fill. Bounding command
        // count by the payload prevents hostile headers from forcing a huge
        // reserve before any command bytes have been validated.
        let headerSize = 20
        let minimumCommandSize = 17
        var i = 0
        func u8() -> UInt8? {
            guard i < bytes.count else { return nil }
            defer { i += 1 }
            return bytes[i]
        }
        func u16() -> UInt16? {
            guard let a = u8(), let b = u8() else { return nil }
            return UInt16(a) | (UInt16(b) << 8)
        }
        func u32() -> UInt32? {
            guard let a = u16(), let b = u16() else { return nil }
            return UInt32(a) | (UInt32(b) << 16)
        }
        func i32() -> Int32? { u32().map { Int32(bitPattern: $0) } }
        func color() -> Color? {
            guard let r = u8(), let g = u8(), let b = u8(), let flags = u8() else { return nil }
            return flags & 1 != 0 ? .default : Color(r: r, g: g, b: b)
        }

        guard let magic = u32() else { throw DecodeError.truncated }
        guard magic == 0x414D_4147 else { throw DecodeError.badMagic }
        guard let version = u32() else { throw DecodeError.truncated }
        guard version == 1 else { throw DecodeError.unsupportedVersion(version) }
        guard let w = i32(), let h = i32(), let count = u32() else {
            throw DecodeError.truncated
        }
        guard w >= 0, h >= 0 else { throw DecodeError.negativeDimensions }
        guard UInt64(count) <= UInt64((bytes.count - headerSize) / minimumCommandSize)
        else { throw DecodeError.commandCountOverflow }

        var commands: [DrawCommand] = []
        commands.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let kind = u8() else { throw DecodeError.truncated }
            switch kind {
            case 0:
                guard let x = i32(), let y = i32(), let cw = i32(), let ch = i32(),
                    let col = color()
                else { throw DecodeError.truncated }
                guard cw >= 0, ch >= 0 else { throw DecodeError.negativeRect }
                commands.append(
                    .fillRect(
                        Rect(x: Int(x), y: Int(y), width: Int(cw), height: Int(ch)), col))
            case 1:
                guard let x = i32(), let y = i32(),
                    let fg = color(), let bg = color(), let sgr = u16(),
                    let len = u32()
                else { throw DecodeError.truncated }
                guard UInt64(len) <= UInt64(bytes.count - i) else {
                    throw DecodeError.truncated
                }
                let payload = bytes[i..<(i + Int(len))]
                guard Self.isValidUTF8(payload) else { throw DecodeError.invalidUTF8 }
                let text = String(decoding: payload, as: UTF8.self)
                i += Int(len)
                var style = TextStyle(foreground: fg, background: bg)
                style.attributes = TextAttributes(rawValue: UInt8(truncatingIfNeeded: sgr))
                commands.append(.text(text, at: Point(x: Int(x), y: Int(y)), style: style))
            default:
                throw DecodeError.unknownCommandKind(kind)
            }
        }
        guard i == bytes.count else { throw DecodeError.trailingBytes }
        return DrawList(size: Size(width: Int(w), height: Int(h)), commands: commands)
    }

    // MARK: Little-endian appenders

    /// Strict RFC 3629 validation kept stdlib-only and available at the
    /// package's macOS 14 deployment floor.
    private static func isValidUTF8(_ slice: ArraySlice<UInt8>) -> Bool {
        // Validated in place; ArraySlice shares indices with its base, so
        // everything is offset from `start`, never from zero.
        let start = slice.startIndex
        let count = slice.count
        var index = 0
        func continuation(_ offset: Int) -> Bool {
            index + offset < count && (0x80...0xbf).contains(slice[start + index + offset])
        }
        while index < count {
            let first = slice[start + index]
            if first <= 0x7f { index += 1; continue }
            if (0xc2...0xdf).contains(first) {
                guard continuation(1) else { return false }
                index += 2
                continue
            }
            if (0xe0...0xef).contains(first) {
                guard continuation(1), continuation(2) else { return false }
                let second = slice[start + index + 1]
                if first == 0xe0 && second < 0xa0 { return false }
                if first == 0xed && second > 0x9f { return false }
                index += 3
                continue
            }
            if (0xf0...0xf4).contains(first) {
                guard continuation(1), continuation(2), continuation(3) else { return false }
                let second = slice[start + index + 1]
                if first == 0xf0 && second < 0x90 { return false }
                if first == 0xf4 && second > 0x8f { return false }
                index += 4
                continue
            }
            return false
        }
        return true
    }

    private static func clampedI32(_ value: Int) -> Int32 {
        if value > Int(Int32.max) { return .max }
        if value < Int(Int32.min) { return .min }
        return Int32(value)
    }

    private static func appendColor(_ out: inout [UInt8], _ c: Color) {
        out.append(c.r)
        out.append(c.g)
        out.append(c.b)
        out.append(c.isDefault ? 1 : 0)
    }
    private static func appendU16(_ out: inout [UInt8], _ v: UInt16) {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8(v >> 8))
    }
    private static func appendU32(_ out: inout [UInt8], _ v: UInt32) {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8((v >> 8) & 0xFF))
        out.append(UInt8((v >> 16) & 0xFF))
        out.append(UInt8((v >> 24) & 0xFF))
    }
    private static func appendI32(_ out: inout [UInt8], _ v: Int32) {
        appendU32(&out, UInt32(bitPattern: v))
    }

}
