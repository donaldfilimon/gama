//  Style.swift — GamaCore
//  Backend-agnostic color + text attributes. RGB is the source of truth;
//  the TUI backend downsamples to 256/16-color terminals, GUI/MLIR
//  backends consume RGB directly.

public struct Color: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    /// `false` means "terminal default / inherit" — carried so TUI can
    /// emit SGR-reset instead of painting a literal color.
    public var isDefault: Bool

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b; self.isDefault = false
    }

    private init(default: ()) {
        self.r = 0; self.g = 0; self.b = 0; self.isDefault = true
    }

    public static let `default` = Color(default: ())
    public static let black = Color(r: 0, g: 0, b: 0)
    public static let white = Color(r: 255, g: 255, b: 255)
    public static let red = Color(r: 224, g: 64, b: 64)
    public static let green = Color(r: 64, g: 200, b: 100)
    public static let blue = Color(r: 80, g: 128, b: 255)
    public static let yellow = Color(r: 232, g: 200, b: 72)
    public static let cyan = Color(r: 72, g: 208, b: 208)
    public static let magenta = Color(r: 208, g: 96, b: 208)
    public static let gray = Color(r: 128, g: 128, b: 128)

    /// Nearest xterm-256 palette index (used by the TUI backend when
    /// truecolor is unavailable).
    public var xterm256: UInt8 {
        if isDefault { return 0 }
        // Grayscale ramp check
        if r == g, g == b {
            if r < 8 { return 16 }
            if r > 248 { return 231 }
            return UInt8(232 + ((Int(r) - 8) * 24) / 247)
        }
        func cube(_ v: UInt8) -> Int {
            v < 48 ? 0 : v < 114 ? 1 : Int((Int(v) - 35) / 40)
        }
        return UInt8(16 + 36 * cube(r) + 6 * cube(g) + cube(b))
    }
}
public struct TextAttributes: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let bold = TextAttributes(rawValue: 1 << 0)
    public static let dim = TextAttributes(rawValue: 1 << 1)
    public static let italic = TextAttributes(rawValue: 1 << 2)
    public static let underline = TextAttributes(rawValue: 1 << 3)
    public static let inverse = TextAttributes(rawValue: 1 << 4)
    public static let strikethrough = TextAttributes(rawValue: 1 << 5)
}

public struct TextStyle: Hashable, Sendable {
    public var foreground: Color
    public var background: Color
    public var attributes: TextAttributes

    public init(
        foreground: Color = .default,
        background: Color = .default,
        attributes: TextAttributes = []
    ) {
        self.foreground = foreground
        self.background = background
        self.attributes = attributes
    }

    public static let plain = TextStyle()

    /// Overlay semantics: non-default fields of `other` win.
    public func merging(_ other: TextStyle) -> TextStyle {
        TextStyle(
            foreground: other.foreground.isDefault ? foreground : other.foreground,
            background: other.background.isDefault ? background : other.background,
            attributes: attributes.union(other.attributes)
        )
    }
}

public enum BorderStyle: Hashable, Sendable {
    case single
    case double
    case rounded
    case heavy
    case ascii

    /// (topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight)
    public var glyphs: (Character, Character, Character, Character, Character, Character, Character, Character) {
        switch self {
        case .single: return ("┌", "─", "┐", "│", "│", "└", "─", "┘")
        case .double: return ("╔", "═", "╗", "║", "║", "╚", "═", "╝")
        case .rounded: return ("╭", "─", "╮", "│", "│", "╰", "─", "╯")
        case .heavy: return ("┏", "━", "┓", "┃", "┃", "┗", "━", "┛")
        case .ascii: return ("+", "-", "+", "|", "|", "+", "-", "+")
        }
    }
}
