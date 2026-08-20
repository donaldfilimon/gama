import GamaCore

public enum ANSIDiff {
    public static func encode(old: CellGrid, new: CellGrid) -> String {
        var out = ""
        if old.width != new.width || old.height != new.height {
            out += "\u{1b}[2J"
        }
        for y in 0..<new.height {
            for x in 0..<new.width {
                let cell = new[x, y]
                let prev = (x < old.width && y < old.height) ? old[x, y] : nil
                if let prev, prev == cell { continue }
                out += "\u{1b}[\(y + 1);\(x + 1)H"
                out += sgr(cell.style)
                out.append(Character(cell.scalar))
                out += "\u{1b}[0m"
            }
        }
        return out
    }

    static func sgr(_ style: TextStyle) -> String {
        var codes: [String] = ["0"]
        if style.bold { codes.append("1") }
        if style.underline { codes.append("4") }
        if style.inverse { codes.append("7") }
        if let fg = style.foreground.ansi256 {
            codes.append("38")
            codes.append("5")
            codes.append(String(fg))
        }
        if let bg = style.background.ansi256 {
            codes.append("48")
            codes.append("5")
            codes.append(String(bg))
        }
        return "\u{1b}[\(codes.joined(separator: ";"))m"
    }
}
