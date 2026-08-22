import GamaCore

public struct KeyParser: Sendable {
    var buffer: [UInt8] = []

    public init() {}

    public mutating func push(_ bytes: [UInt8]) -> [Event] {
        buffer.append(contentsOf: bytes)
        var events: [Event] = []
        while let event = popEvent() {
            events.append(event)
        }
        return events
    }

    mutating func popEvent() -> Event? {
        guard let first = buffer.first else { return nil }
        if first == 0x1b {
            return popEscape()
        }
        buffer.removeFirst()
        switch first {
        case 0x0d, 0x0a: return .key(.enter)
        case 0x09: return .key(.tab)
        case 0x03: return .key(.ctrlC)
        case 0x7f, 0x08: return .key(.backspace)
        case 0x1b: return .key(.escape)
        default:
            if first < 0x80 {
                if let scalar = Unicode.Scalar(UInt32(first)), scalar.isASCII {
                    let ch = Character(scalar)
                    if ch == " " || ch.isLetter || ch.isNumber || ch.isPunctuation || ch.isSymbol || !ch.isWhitespace {
                        return .key(.character(ch))
                    }
                }
                return .key(.character(Character(Unicode.Scalar(first))))
            }
            return popUTF8Leading(first)
        }
    }

    mutating func popEscape() -> Event? {
        if buffer.count == 1 { return nil }
        if buffer.count >= 3, buffer[1] == 0x5b { // CSI
            if buffer[2] == 0x5a {
                buffer.removeFirst(3)
                return .key(.backTab)
            }
            if buffer[2] == 0x3c { // SGR mouse
                return popSGRMouse()
            }
            if buffer.count >= 3 {
                switch buffer[2] {
                case 0x41:
                    buffer.removeFirst(3)
                    return .key(.up)
                case 0x42:
                    buffer.removeFirst(3)
                    return .key(.down)
                case 0x43:
                    buffer.removeFirst(3)
                    return .key(.right)
                case 0x44:
                    buffer.removeFirst(3)
                    return .key(.left)
                default:
                    break
                }
            }
            return nil
        }
        buffer.removeFirst()
        return .key(.escape)
    }

    mutating func popSGRMouse() -> Event? {
        // ESC [ < b ; x ; y M/m
        guard let end = buffer.firstIndex(where: { $0 == 0x4d || $0 == 0x6d }) else { return nil }
        let payload = buffer[2..<end] // starts at '<'
        let kind: Mouse.Kind = buffer[end] == 0x4d ? .press : .release
        buffer.removeFirst(end + 1)
        let text = String(decoding: payload.dropFirst(), as: UTF8.self) // drop '<'
        let parts = text.split(separator: ";")
        guard parts.count == 3,
              let btn = Int(parts[0]),
              let x1 = Int(parts[1]),
              let y1 = Int(parts[2]) else { return nil }
        return .mouse(Mouse(kind: kind, button: btn, x: max(0, x1 - 1), y: max(0, y1 - 1)))
    }

    mutating func popUTF8Leading(_ first: UInt8) -> Event? {
        let need: Int
        if first & 0xE0 == 0xC0 { need = 2 }
        else if first & 0xF0 == 0xE0 { need = 3 }
        else if first & 0xF8 == 0xF0 { need = 4 }
        else { return nil }
        if buffer.count < need - 1 {
            buffer.insert(first, at: 0)
            return nil
        }
        var bytes = [first]
        for _ in 0..<(need - 1) {
            bytes.append(buffer.removeFirst())
        }
        let s = String(decoding: bytes, as: UTF8.self)
        if let ch = s.first, ch != "\u{FFFD}" || bytes.count == 1 {
            return .key(.character(ch))
        }
        return nil
    }
}
