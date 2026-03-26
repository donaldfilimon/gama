// StyleTypes.swift — Color, Font, EdgeInsets, and Alignment types
// Part of GamaUI

// MARK: - Color

/// An RGBA color value.
public struct Color: Sendable, Equatable {
    /// Red component (0.0–1.0).
    public let red: Double
    /// Green component (0.0–1.0).
    public let green: Double
    /// Blue component (0.0–1.0).
    public let blue: Double
    /// Alpha component (0.0–1.0).
    public let alpha: Double

    /// Creates a color with the given RGBA components.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    // MARK: Named Colors

    /// Pure red.
    public static let red = Color(red: 1, green: 0, blue: 0)
    /// Pure green.
    public static let green = Color(red: 0, green: 1, blue: 0)
    /// Pure blue.
    public static let blue = Color(red: 0, green: 0, blue: 1)
    /// White.
    public static let white = Color(red: 1, green: 1, blue: 1)
    /// Black.
    public static let black = Color(red: 0, green: 0, blue: 0)
    /// Fully transparent.
    public static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)
    /// Yellow.
    public static let yellow = Color(red: 1, green: 1, blue: 0)
    /// Orange.
    public static let orange = Color(red: 1, green: 0.5, blue: 0)
    /// Purple.
    public static let purple = Color(red: 0.5, green: 0, blue: 0.5)
    /// Gray.
    public static let gray = Color(red: 0.5, green: 0.5, blue: 0.5)
}

// MARK: - Color + View

extension Color: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Color is a leaf view")
    }
}

// MARK: - Font

/// A font description with size and weight.
///
/// Actual text rendering is deferred to a future unit; this type
/// captures the declarative intent.
public struct Font: Sendable, Equatable {
    /// The point size of the font.
    public let size: Double

    /// The weight of the font.
    public let weight: Weight

    /// Creates a font with the given size and weight.
    public init(size: Double, weight: Weight = .regular) {
        self.size = size
        self.weight = weight
    }

    /// Font weight enumeration.
    public enum Weight: Sendable, Equatable {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black
    }

    // MARK: Convenience

    /// A system font at the given size with regular weight.
    public static func system(size: Double, weight: Weight = .regular) -> Font {
        Font(size: size, weight: weight)
    }

    /// Title font (28pt, bold).
    public static let title = Font(size: 28, weight: .bold)
    /// Headline font (17pt, semibold).
    public static let headline = Font(size: 17, weight: .semibold)
    /// Body font (17pt, regular).
    public static let body = Font(size: 17, weight: .regular)
    /// Caption font (12pt, regular).
    public static let caption = Font(size: 12, weight: .regular)
}

// MARK: - EdgeInsets

/// Padding values for each edge of a rectangular area.
public struct EdgeInsets: Sendable, Equatable {
    /// The inset from the top edge.
    public let top: Double
    /// The inset from the leading (left in LTR) edge.
    public let leading: Double
    /// The inset from the bottom edge.
    public let bottom: Double
    /// The inset from the trailing (right in LTR) edge.
    public let trailing: Double

    /// Creates edge insets with the given values.
    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// Creates uniform edge insets.
    public init(_ all: Double) {
        self.top = all
        self.leading = all
        self.bottom = all
        self.trailing = all
    }

    /// The total horizontal insets (leading + trailing).
    public var horizontal: Double { leading + trailing }

    /// The total vertical insets (top + bottom).
    public var vertical: Double { top + bottom }
}

// MARK: - Alignment

/// A two-dimensional alignment value.
public struct Alignment: Sendable, Equatable {
    /// The horizontal component.
    public let horizontal: HorizontalAlignment
    /// The vertical component.
    public let vertical: VerticalAlignment

    /// Creates an alignment from horizontal and vertical components.
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Center alignment on both axes.
    public static let center = Alignment(horizontal: .center, vertical: .center)
    /// Leading edge, vertically centered.
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    /// Trailing edge, vertically centered.
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    /// Top edge, horizontally centered.
    public static let top = Alignment(horizontal: .center, vertical: .top)
    /// Bottom edge, horizontally centered.
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    /// Top-leading corner.
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    /// Top-trailing corner.
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    /// Bottom-leading corner.
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    /// Bottom-trailing corner.
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

// MARK: - HorizontalAlignment

/// Horizontal alignment options.
public enum HorizontalAlignment: Sendable, Equatable {
    /// Align to the leading edge.
    case leading
    /// Align to the center.
    case center
    /// Align to the trailing edge.
    case trailing
}

// MARK: - VerticalAlignment

/// Vertical alignment options.
public enum VerticalAlignment: Sendable, Equatable {
    /// Align to the top edge.
    case top
    /// Align to the center.
    case center
    /// Align to the bottom edge.
    case bottom
}
