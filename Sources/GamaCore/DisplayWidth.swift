public enum DisplayWidth: Sendable {
    public static func of(_ string: String) -> Int {
        var total = 0
        for scalar in string.unicodeScalars {
            total += of(scalar)
        }
        return total
    }

    public static func of(_ scalar: Unicode.Scalar) -> Int {
        let v = scalar.value
        if v == 0x09 { return 1 }
        if v <= 0x1F { return 0 }
        if (0x0300...0x036F).contains(v) { return 0 }
        if (0x1100...0x115F).contains(v) { return 2 }
        if (0x2E80...0xA4CF).contains(v) && v != 0x303F { return 2 }
        if (0xAC00...0xD7A3).contains(v) { return 2 }
        if (0xF900...0xFAFF).contains(v) { return 2 }
        if (0xFE10...0xFE19).contains(v) { return 2 }
        if (0xFE30...0xFE6F).contains(v) { return 2 }
        if (0xFF00...0xFF60).contains(v) { return 2 }
        if (0xFFE0...0xFFE6).contains(v) { return 2 }
        return 1
    }
}
