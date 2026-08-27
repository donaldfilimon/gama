//  Style.swift — GamaCore
//  Backend-agnostic color + text attributes. RGB is the source of truth;
//  the TUI backend downsamples to 256/16-color terminals, GUI/MLIR
//  backends consume RGB directly.

/// A backend-agnostic RGB color, plus one out-of-band value: `default`,
/// which means "inherit the surface's own color" rather than paint.
/// RGB is the source of truth; the TUI backend downsamples via
/// `xterm256` when truecolor is unavailable.
public struct Color: Hashable, Sendable {
    /// Red channel, 0–255.
    public var r: UInt8
    /// Green channel, 0–255.
    public var g: UInt8
    /// Blue channel, 0–255.
    public var b: UInt8
    /// `false` means "terminal default / inherit" — carried so TUI can
    /// emit SGR-reset instead of painting a literal color.
    public var isDefault: Bool

    /// Creates a concrete (painted) color from its channels;
    /// `isDefault` is always `false` here — the inherit value is only
    /// reachable through `Color.default`.
    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b; self.isDefault = false
    }

    private init(default: ()) {
        self.r = 0; self.g = 0; self.b = 0; self.isDefault = true
    }

    /// The inherit value: paints nothing of its own, letting the
    /// surface's existing color show through. `TextStyle.merging`
    /// treats it as "unset".
    public static let `default` = Color(default: ())
    /// Painted black — a concrete color, unlike `default`.
    public static let black = Color(r: 0, g: 0, b: 0)
    /// Painted white — the bright end of the grayscale ramp.
    public static let white = Color(r: 255, g: 255, b: 255)
    /// The built-in palette's red — softened from the full primary.
    public static let red = Color(r: 224, g: 64, b: 64)
    /// The built-in palette's green — softened from the full primary.
    public static let green = Color(r: 64, g: 200, b: 100)
    /// The built-in palette's blue — softened from the full primary.
    public static let blue = Color(r: 80, g: 128, b: 255)
    /// The built-in palette's yellow — softened from the full primary.
    public static let yellow = Color(r: 232, g: 200, b: 72)
    /// The built-in palette's cyan — softened from the full primary.
    public static let cyan = Color(r: 72, g: 208, b: 208)
    /// The built-in palette's magenta — softened from the full primary.
    public static let magenta = Color(r: 208, g: 96, b: 208)
    /// Mid gray; being achromatic, it downsamples onto the xterm-256
    /// grayscale ramp rather than the color cube.
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
/// Per-glyph text decorations, one bit each. Attributes are additive:
/// `TextStyle.merging` unions them, so an inner style can add emphasis
/// but never remove what an outer style set.
public struct TextAttributes: OptionSet, Hashable, Sendable {
    /// The packed bit field; six of the eight bits are in use.
    public let rawValue: UInt8
    /// Creates a set from a packed bit field, as `OptionSet` requires.
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Heavier glyph weight.
    public static let bold = TextAttributes(rawValue: 1 << 0)
    /// Reduced intensity.
    public static let dim = TextAttributes(rawValue: 1 << 1)
    /// Slanted glyphs.
    public static let italic = TextAttributes(rawValue: 1 << 2)
    /// A line under the glyphs.
    public static let underline = TextAttributes(rawValue: 1 << 3)
    /// Foreground and background swapped.
    public static let inverse = TextAttributes(rawValue: 1 << 4)
    /// A line through the glyphs.
    public static let strikethrough = TextAttributes(rawValue: 1 << 5)
}

/// How a run of cells paints: foreground, background, and decorations.
/// Styles cascade down the render tree — the painter carries an
/// inherited style and combines it with each node's own via
/// `merging(_:)`, where `default` colors mean "not set here".
public struct TextStyle: Hashable, Sendable {
    /// Glyph color; `.default` inherits the enclosing style's foreground.
    public var foreground: Color
    /// Cell fill behind the glyphs; `.default` leaves the surface's
    /// background untouched.
    public var background: Color
    /// Additive decorations; merging unions these rather than replacing.
    public var attributes: TextAttributes

    /// Creates a style; every argument defaults to "unset", so
    /// `TextStyle()` is the same as `plain`.
    public init(
        foreground: Color = .default,
        background: Color = .default,
        attributes: TextAttributes = []
    ) {
        self.foreground = foreground
        self.background = background
        self.attributes = attributes
    }

    /// The all-unset style — the identity of `merging(_:)`: overlaying
    /// it changes nothing, and merging onto it yields the overlay.
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

/// The glyph family a `border` node draws its box with; `glyphs`
/// resolves each case to its eight corner and edge characters.
public enum BorderStyle: Hashable, Sendable {
    /// Light single-line box drawing.
    case single
    /// Double-line box drawing.
    case double
    /// Single-line box drawing with rounded corners.
    case rounded
    /// Thick single-line box drawing.
    case heavy
    /// Plain `+`/`-`/`|` — no Unicode box-drawing glyphs required.
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
