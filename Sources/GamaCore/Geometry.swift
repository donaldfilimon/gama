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

public struct Point: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public static let zero = Point(x: 0, y: 0)

    public static func + (l: Point, r: Point) -> Point {
        Point(x: saturatingAdd(l.x, r.x), y: saturatingAdd(l.y, r.y))
    }
    public static func - (l: Point, r: Point) -> Point {
        Point(x: saturatingSubtract(l.x, r.x), y: saturatingSubtract(l.y, r.y))
    }
}

public struct Size: Hashable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public static let zero = Size(width: 0, height: 0)

    public func clamped(to max: Size) -> Size {
        Size(
            width: Swift.max(0, Swift.min(width, Swift.max(0, max.width))),
            height: Swift.max(0, Swift.min(height, Swift.max(0, max.height)))
        )
    }
}

public struct Rect: Hashable, Sendable {
    public var origin: Point
    public var size: Size
    public init(origin: Point, size: Size) { self.origin = origin; self.size = size }
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }
    public static let zero = Rect(origin: .zero, size: .zero)

    public var minX: Int { origin.x }
    public var minY: Int { origin.y }
    public var maxX: Int { saturatingAdd(origin.x, max(0, size.width)) }
    public var maxY: Int { saturatingAdd(origin.y, max(0, size.height)) }

    public func contains(_ p: Point) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func intersection(_ other: Rect) -> Rect {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        guard x1 > x0, y1 > y0 else { return .zero }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

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

public struct EdgeInsets: Hashable, Sendable {
    public var top: Int
    public var leading: Int
    public var bottom: Int
    public var trailing: Int
    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init(all: Int) { self.init(top: all, leading: all, bottom: all, trailing: all) }
    public var horizontal: Int { saturatingAdd(leading, trailing) }
    public var vertical: Int { saturatingAdd(top, bottom) }
}

/// Size proposal for the layout pass. `nil` axis = unconstrained.
public struct ProposedSize: Hashable, Sendable {
    public var width: Int?
    public var height: Int?
    public init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }
    public static let unspecified = ProposedSize()

    public func replacingUnspecified(by s: Size) -> Size {
        Size(width: width ?? s.width, height: height ?? s.height)
    }
}

public enum Axis: Hashable, Sendable {
    case horizontal
    case vertical
}

public enum HorizontalAlignment: Hashable, Sendable { case leading, center, trailing }
public enum VerticalAlignment: Hashable, Sendable { case top, center, bottom }

public struct Alignment: Hashable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}
