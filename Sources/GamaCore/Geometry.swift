//  Geometry.swift — GamaCore
//  Pure value geometry in integer cell/pixel space. No Foundation.

@inline(__always)
private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    guard overflow else { return value }
    return rhs >= 0 ? .max : .min
}

@inline(__always)
private func saturatingSubtract(_ lhs: Int, _ rhs: Int) -> Int {
    let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
    guard overflow else { return value }
    return rhs >= 0 ? .min : .max
}

/// A position in integer cell space: origin at the top-left, x growing
/// rightward, y growing downward. Arithmetic saturates at `Int` bounds
/// instead of trapping.
public struct Point: Hashable, Sendable {
    /// Column offset from the left edge, in cells.
    public var x: Int
    /// Row offset from the top edge, in cells; larger values are lower.
    public var y: Int
    /// Creates a point from a column (`x`) and row (`y`) offset.
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    /// The top-left origin of the coordinate space.
    public static let zero = Point(x: 0, y: 0)

    /// Componentwise sum; saturates at `Int` bounds rather than overflowing.
    public static func + (l: Point, r: Point) -> Point {
        Point(x: saturatingAdd(l.x, r.x), y: saturatingAdd(l.y, r.y))
    }
    /// Componentwise difference; saturates at `Int` bounds rather than overflowing.
    public static func - (l: Point, r: Point) -> Point {
        Point(x: saturatingSubtract(l.x, r.x), y: saturatingSubtract(l.y, r.y))
    }
}

/// An extent in integer cells, produced by the measure pass and consumed
/// when placing frames.
public struct Size: Hashable, Sendable {
    /// Horizontal extent in cells.
    public var width: Int
    /// Vertical extent in cells (rows).
    public var height: Int
    /// Creates an extent from cell counts; values are stored as given,
    /// negatives included — consumers clamp where it matters.
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    /// The empty extent — what `.empty` content measures to.
    public static let zero = Size(width: 0, height: 0)

    /// Limits both axes to `0...max`, treating negative bounds as zero;
    /// used to keep measured content inside its container during placement.
    public func clamped(to max: Size) -> Size {
        Size(
            width: Swift.max(0, Swift.min(width, Swift.max(0, max.width))),
            height: Swift.max(0, Swift.min(height, Swift.max(0, max.height)))
        )
    }
}

/// An axis-aligned region of cell space. The `min` edges are inclusive and
/// the `max` edges exclusive, so a rect of width w covers columns
/// `minX ..< minX + w`.
public struct Rect: Hashable, Sendable {
    /// Top-left corner of the region.
    public var origin: Point
    /// Extent from `origin`; the edge accessors read negative components as zero.
    public var size: Size
    /// Creates a region from its top-left corner and extent.
    public init(origin: Point, size: Size) { self.origin = origin; self.size = size }
    /// Convenience over `init(origin:size:)` taking loose components.
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }
    /// The empty region at the origin — also what `intersection(_:)`
    /// returns for non-overlapping rects.
    public static let zero = Rect(origin: .zero, size: .zero)

    /// Leftmost column (inclusive).
    public var minX: Int { origin.x }
    /// Topmost row (inclusive).
    public var minY: Int { origin.y }
    /// First column past the right edge (exclusive); negative widths read
    /// as zero and the sum saturates.
    public var maxX: Int { saturatingAdd(origin.x, max(0, size.width)) }
    /// First row past the bottom edge (exclusive); negative heights read
    /// as zero and the sum saturates.
    public var maxY: Int { saturatingAdd(origin.y, max(0, size.height)) }

    /// Whether `p` lies inside the region. The `max` edges are exclusive,
    /// so a zero-area rect contains no point — this is the pointer
    /// hit-test predicate.
    public func contains(_ p: Point) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    /// The overlapping region of the two rects, or `.zero` when they do
    /// not overlap.
    public func intersection(_ other: Rect) -> Rect {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        guard x1 > x0, y1 > y0 else { return .zero }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Shrinks the region inward by `e` on each edge — how padding and
    /// borders carve out their child's bounds. The resulting size floors
    /// at zero; it never goes negative.
    public func inset(by e: EdgeInsets) -> Rect {
        let x = saturatingAdd(minX, e.leading)
        let y = saturatingAdd(minY, e.top)
        let horizontal = saturatingAdd(e.leading, e.trailing)
        let vertical = saturatingAdd(e.top, e.bottom)
        return Rect(
            x: x,
            y: y,
            width: max(0, saturatingSubtract(max(0, size.width), horizontal)),
            height: max(0, saturatingSubtract(max(0, size.height), vertical))
        )
    }
}

/// Per-edge spacing in cells, consumed by `padding` and `Rect.inset(by:)`.
public struct EdgeInsets: Hashable, Sendable {
    /// Cells of inset at the top edge.
    public var top: Int
    /// Cells of inset at the leading edge (the left edge in cell space).
    public var leading: Int
    /// Cells of inset at the bottom edge.
    public var bottom: Int
    /// Cells of inset at the trailing edge (the right edge in cell space).
    public var trailing: Int
    /// Creates insets edge by edge; unspecified edges default to zero.
    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    /// Uniform insets — the same amount on all four edges.
    public init(all: Int) { self.init(top: all, leading: all, bottom: all, trailing: all) }
    /// Combined leading + trailing inset; saturates at `Int` bounds.
    public var horizontal: Int { saturatingAdd(leading, trailing) }
    /// Combined top + bottom inset; saturates at `Int` bounds.
    public var vertical: Int { saturatingAdd(top, bottom) }
}

/// Size proposal for the layout pass. `nil` axis = unconstrained.
public struct ProposedSize: Hashable, Sendable {
    /// Proposed width in cells; `nil` leaves the axis unconstrained so
    /// content answers with its ideal width.
    public var width: Int?
    /// Proposed height in cells; `nil` leaves the axis unconstrained so
    /// content answers with its ideal height.
    public var height: Int?
    /// Creates a proposal; omitted axes stay unconstrained.
    public init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }
    /// Both axes unconstrained — asks content for its ideal size.
    public static let unspecified = ProposedSize()

    /// Resolves the proposal to a concrete `Size`, filling each
    /// unconstrained axis from `s`.
    public func replacingUnspecified(by s: Size) -> Size {
        Size(width: width ?? s.width, height: height ?? s.height)
    }
}

/// The main-axis selector for stacks (and the axis dividers resolve
/// against).
public enum Axis: Hashable, Sendable {
    /// Left-to-right — the main axis of `HStack`.
    case horizontal
    /// Top-to-bottom — the main axis of `VStack`.
    case vertical
}

/// Cross-axis placement inside a `VStack`; also the horizontal half of `Alignment`.
public enum HorizontalAlignment: Hashable, Sendable { case leading, center, trailing }
/// Cross-axis placement inside an `HStack`; also the vertical half of `Alignment`.
public enum VerticalAlignment: Hashable, Sendable { case top, center, bottom }

/// Two-axis placement of content inside larger bounds — used by frames,
/// overlays, and `ZStack` when the content measures smaller than the
/// space it is given.
public struct Alignment: Hashable, Sendable {
    /// Where content sits along the x axis when the bounds are wider than
    /// the content.
    public var horizontal: HorizontalAlignment
    /// Where content sits along the y axis when the bounds are taller than
    /// the content.
    public var vertical: VerticalAlignment
    /// Combines independent per-axis placements.
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
    /// Centered on both axes — the default for frames and `ZStack`.
    public static let center = Alignment(horizontal: .center, vertical: .center)
    /// Anchored at the origin corner (top-left in cell space).
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    /// Anchored at the corner diagonally opposite the origin (bottom-right
    /// in cell space).
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}
