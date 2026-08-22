public struct Color: Equatable, Sendable {
    public var ansi256: UInt8?
    public static let `default` = Color(ansi256: nil)
    public init(ansi256: UInt8?) {
        self.ansi256 = ansi256
    }
}

public struct TextStyle: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    public var bold: Bool
    public var underline: Bool
    public var inverse: Bool
    public static let plain = TextStyle(
        foreground: .default,
        background: .default,
        bold: false,
        underline: false,
        inverse: false
    )
    public init(
        foreground: Color,
        background: Color,
        bold: Bool,
        underline: Bool,
        inverse: Bool
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.underline = underline
        self.inverse = inverse
    }
    public func inverted() -> TextStyle {
        var s = self
        s.inverse = true
        return s
    }
}

public struct Cell: Equatable, Sendable {
    public var scalar: Unicode.Scalar
    public var style: TextStyle
    public static let blank = Cell(scalar: " ", style: .plain)
}

public struct CellGrid: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var cells: [Cell]
    public init(width: Int, height: Int, fill: Cell = .blank) {
        let w = max(0, width)
        let h = max(0, height)
        self.width = w
        self.height = h
        self.cells = Array(repeating: fill, count: w * h)
    }
    public subscript(x: Int, y: Int) -> Cell {
        get {
            guard x >= 0, y >= 0, x < width, y < height else { return .blank }
            return cells[y * width + x]
        }
        set {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            cells[y * width + x] = newValue
        }
    }
    public mutating func put(x: Int, y: Int, scalar: Unicode.Scalar, style: TextStyle) {
        self[x, y] = Cell(scalar: scalar, style: style)
    }
    public func snapshot() -> String {
        guard height > 0 else { return "" }
        var lines: [String] = []
        lines.reserveCapacity(height)
        for y in 0..<height {
            var chars: [Character] = []
            for x in 0..<width {
                chars.append(Character(self[x, y].scalar))
            }
            var line = String(chars)
            while line.last == " " { line.removeLast() }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
