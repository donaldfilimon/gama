import Foundation

/// A 2D shape that you can use when drawing a view.
///
/// Shapes without an explicit fill or stroke get a default fill based on the
/// foreground color.
public protocol Shape: Sendable {
    /// Returns the path of this shape as a path in a rectangular coordinate
    /// space.
    ///
    /// - Parameter rect: The rectangle in which to draw the shape.
    /// - Returns: A path that describes this shape.
    func path(in rect: Rectangle) -> Path
}

extension Shape {
    /// Fills this shape with a color or gradient.
    ///
    /// - Parameter style: The color or gradient with which to fill this shape.
    /// - Returns: A shape filled with the specified style.
    @inlinable
    public func fill<S>(_ style: S) -> some View where S: ShapeStyle {
        modifier(FillModifier(style: style))
    }
    
    /// Fills this shape with a color.
    ///
    /// - Parameter color: The color with which to fill this shape.
    /// - Returns: A shape filled with the specified color.
    @inlinable
    public func fill(_ color: Color) -> some View {
        fill(color as ShapeStyle)
    }
    
    /// Traces the outline of this shape with a color or gradient.
    ///
    /// - Parameters:
    ///   - content: The color or gradient with which to stroke this shape.
    ///   - style: The stroke characteristics—width, line cap, line join, and
    ///     miter limit—that determine how to render the border.
    /// - Returns: A stroked shape.
    @inlinable
    public func stroke<S>(_ content: S, style: StrokeStyle = StrokeStyle()) -> some View where S: ShapeStyle {
        modifier(StrokeModifier(content: content, style: style))
    }
    
    /// Traces the outline of this shape with a color.
    ///
    /// - Parameters:
    ///   - content: The color with which to stroke this shape.
    ///   - lineWidth: The width of the stroke.
    /// - Returns: A stroked shape.
    @inlinable
    public func stroke(_ content: Color, lineWidth: CGFloat = 1) -> some View {
        stroke(content, style: StrokeStyle(lineWidth: lineWidth))
    }
}

/// A style that can be used to fill or stroke a shape.
public protocol ShapeStyle: Sendable {
    /// Resolves this style to a concrete color.
    func resolve(in environment: EnvironmentValues) -> Color
}

extension Color: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> Color {
        self
    }
}

/// A stroke style for rendering path lines.
public struct StrokeStyle: Sendable {
    public var lineWidth: CGFloat
    public var lineCap: LineCap
    public var lineJoin: LineJoin
    public var miterLimit: CGFloat
    
    public init(
        lineWidth: CGFloat = 1,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter,
        miterLimit: CGFloat = 10
    ) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
    }
}

/// Styles for rendering the endpoint of a stroked path.
public enum LineCap: Sendable {
    case butt
    case round
    case square
}

/// Styles for rendering the connection between two segments of a stroked path.
public enum LineJoin: Sendable {
    case miter
    case round
    case bevel
}

/// A rectangular shape aligned inside the frame of the view containing it.
public struct RectangleShape: Shape {
    public init() {}
    
    public func path(in rect: Rectangle) -> Path {
        var path = Path()
        path.move(to: Point(x: rect.left, y: rect.top))
        path.addLine(to: Point(x: rect.right, y: rect.top))
        path.addLine(to: Point(x: rect.right, y: rect.bottom))
        path.addLine(to: Point(x: rect.left, y: rect.bottom))
        path.closeSubpath()
        return path
    }
}

/// Note: RectangleShape is used here instead of Rectangle to avoid conflict
/// with the Rectangle struct in Core/Types.swift which represents bounds/rectangles.

/// A circular shape.
public struct Circle: Shape {
    public init() {}
    
    public func path(in rect: Rectangle) -> Path {
        let center = Point(
            x: (rect.left + rect.right) / 2,
            y: (rect.top + rect.bottom) / 2
        )
        let radius = min(rect.width, rect.height) / 2
        
        var path = Path()
        path.addArc(
            center: center,
            radius: CGFloat(radius),
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: false
        )
        return path
    }
}

/// An ellipse aligned inside the frame of the view containing it.
public struct Ellipse: Shape {
    public init() {}
    
    public func path(in rect: Rectangle) -> Path {
        let center = Point(
            x: (rect.left + rect.right) / 2,
            y: (rect.top + rect.bottom) / 2
        )
        let radiusX = CGFloat(rect.width) / 2
        let radiusY = CGFloat(rect.height) / 2
        
        var path = Path()
        path.addEllipse(center: center, radiusX: radiusX, radiusY: radiusY)
        return path
    }
}

/// A rectangular shape with rounded corners, aligned inside the frame of the
/// view containing it.
public struct RoundedRectangle: Shape {
    public var cornerRadius: CGFloat
    
    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }
    
    public init(cornerSize: Size) {
        self.cornerRadius = CGFloat(min(cornerSize.width, cornerSize.height))
    }
    
    public func path(in rect: Rectangle) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerRadius: cornerRadius)
        return path
    }
}

/// A capsule shape.
public struct Capsule: Shape {
    public init() {}
    
    public func path(in rect: Rectangle) -> Path {
        let radius = CGFloat(min(rect.width, rect.height)) / 2
        return RoundedRectangle(cornerRadius: radius).path(in: rect)
    }
}

/// Fill modifier implementation
private struct FillModifier<S: ShapeStyle>: ViewModifier {
    let style: S
    
    func body(content: Content) -> some View {
        // Fill modifier implementation would go here
        content
    }
}

/// Stroke modifier implementation
private struct StrokeModifier<S: ShapeStyle>: ViewModifier {
    let content: S
    let style: StrokeStyle
    
    func body(content: Content) -> some View {
        // Stroke modifier implementation would go here
        content
    }
}