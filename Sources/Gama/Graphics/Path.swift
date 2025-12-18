import Foundation

/// A 2D path made of lines and curves.
///
/// A path is a sequence of drawing operations that you can use to draw
/// custom shapes. You create paths by moving to points, adding lines and
/// curves, and closing subpaths.
public struct Path: Sendable {
    internal var elements: [PathElement] = []
    
    /// Creates an empty path.
    public init() {}
    
    /// Creates a path from a closure that builds path elements.
    public init(_ closure: (inout Path) -> Void) {
        var path = Path()
        closure(&path)
        self = path
    }
    
    /// Moves to a point without drawing a line.
    ///
    /// - Parameter point: The destination point.
    public mutating func move(to point: Point) {
        elements.append(.moveTo(point))
    }
    
    /// Adds a line to a point.
    ///
    /// - Parameter point: The destination point.
    public mutating func addLine(to point: Point) {
        elements.append(.lineTo(point))
    }
    
    /// Adds a quadratic Bézier curve to a point.
    ///
    /// - Parameters:
    ///   - control: The control point of the curve.
    ///   - end: The end point of the curve.
    public mutating func addQuadCurve(to end: Point, control: Point) {
        elements.append(.quadCurveTo(end: end, control: control))
    }
    
    /// Adds a cubic Bézier curve to a point.
    ///
    /// - Parameters:
    ///   - control1: The first control point.
    ///   - control2: The second control point.
    ///   - end: The end point.
    public mutating func addCurve(to end: Point, control1: Point, control2: Point) {
        elements.append(.curveTo(end: end, control1: control1, control2: control2))
    }
    
    /// Adds an arc of a circle.
    ///
    /// - Parameters:
    ///   - center: The center of the arc's circle.
    ///   - radius: The radius of the arc's circle.
    ///   - startAngle: The starting angle of the arc.
    ///   - endAngle: The ending angle of the arc.
    ///   - clockwise: Whether the arc is drawn clockwise.
    public mutating func addArc(
        center: Point,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        clockwise: Bool
    ) {
        elements.append(.arc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        ))
    }
    
    /// Adds an ellipse.
    ///
    /// - Parameters:
    ///   - center: The center of the ellipse.
    ///   - radiusX: The horizontal radius.
    ///   - radiusY: The vertical radius.
    public mutating func addEllipse(center: Point, radiusX: CGFloat, radiusY: CGFloat) {
        elements.append(.ellipse(center: center, radiusX: radiusX, radiusY: radiusY))
    }
    
    /// Adds a rounded rectangle.
    ///
    /// - Parameters:
    ///   - rect: The rectangle to add.
    ///   - cornerRadius: The corner radius.
    public mutating func addRoundedRect(in rect: Rectangle, cornerRadius: CGFloat) {
        elements.append(.roundedRect(rect: rect, cornerRadius: cornerRadius))
    }
    
    /// Closes the current subpath.
    public mutating func closeSubpath() {
        elements.append(.closePath)
    }
    
    /// Returns a Boolean value indicating whether the path contains a point.
    ///
    /// - Parameter point: The point to test.
    /// - Returns: `true` if the path contains the point; otherwise, `false`.
    public func contains(_ point: Point) -> Bool {
        // Hit testing implementation would go here
        return false
    }
}

/// Path element types
internal enum PathElement: Sendable {
    case moveTo(Point)
    case lineTo(Point)
    case quadCurveTo(end: Point, control: Point)
    case curveTo(end: Point, control1: Point, control2: Point)
    case arc(center: Point, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool)
    case ellipse(center: Point, radiusX: CGFloat, radiusY: CGFloat)
    case roundedRect(rect: Rectangle, cornerRadius: CGFloat)
    case closePath
}