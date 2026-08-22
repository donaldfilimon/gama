public struct Size: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public static let zero = Size(width: 0, height: 0)
    public var clampedNonNegative: Size {
        Size(width: max(0, width), height: max(0, height))
    }
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct Point: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct Rect: Equatable, Sendable {
    public var origin: Point
    public var size: Size
    public var minX: Int { origin.x }
    public var minY: Int { origin.y }
    public var maxX: Int { origin.x + size.width }
    public var maxY: Int { origin.y + size.height }
    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }
    public func contains(_ p: Point) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
}

public struct EdgeInsets: Equatable, Sendable {
    public var top: Int
    public var leading: Int
    public var bottom: Int
    public var trailing: Int
    public static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    public init(top: Int, leading: Int, bottom: Int, trailing: Int) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
    public static func all(_ v: Int) -> EdgeInsets {
        EdgeInsets(top: v, leading: v, bottom: v, trailing: v)
    }
}

public enum Axis: Equatable, Sendable {
    case horizontal
    case vertical
}

public enum Alignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}
