import Foundation

/// A unified graphics context that provides platform-agnostic drawing operations.
///
/// This context abstracts platform-specific graphics APIs (GDI, Core Graphics,
/// Cairo, Canvas) behind a common interface inspired by browser Canvas 2D API.
@MainActor
public struct GraphicsContext: Sendable {
    internal let _platformContext: AnyGraphicsContext
    
    internal init(platformContext: AnyGraphicsContext) {
        self._platformContext = platformContext
    }
    
    // MARK: - Drawing State
    
    /// Sets the fill style to a color.
    ///
    /// - Parameter color: The color to use for filling shapes.
    public func setFillStyle(_ color: Color) {
        _platformContext.setFillStyle(color)
    }
    
    /// Sets the stroke style to a color.
    ///
    /// - Parameter color: The color to use for stroking shapes.
    public func setStrokeStyle(_ color: Color) {
        _platformContext.setStrokeStyle(color)
    }
    
    /// Sets the line width for stroking.
    ///
    /// - Parameter width: The line width in points.
    public func setLineWidth(_ width: CGFloat) {
        _platformContext.setLineWidth(width)
    }
    
    // MARK: - Transform Operations (Canvas 2D API style)
    
    /// Saves the current drawing state (transform, fill style, stroke style, etc.)
    public func save() {
        _platformContext.save()
    }
    
    /// Restores the drawing state to the last saved state.
    public func restore() {
        _platformContext.restore()
    }
    
    /// Translates the coordinate system.
    ///
    /// - Parameters:
    ///   - x: The horizontal translation.
    ///   - y: The vertical translation.
    public func translate(x: CGFloat, y: CGFloat) {
        _platformContext.translate(x: x, y: y)
    }
    
    /// Rotates the coordinate system.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotate(_ angle: CGFloat) {
        _platformContext.rotate(angle)
    }
    
    /// Scales the coordinate system.
    ///
    /// - Parameters:
    ///   - x: The horizontal scale factor.
    ///   - y: The vertical scale factor.
    public func scale(x: CGFloat, y: CGFloat) {
        _platformContext.scale(x: x, y: y)
    }
    
    /// Multiplies the current transformation matrix by the given matrix.
    ///
    /// - Parameter matrix: The transformation matrix to apply.
    public func transform(_ matrix: TransformMatrix) {
        _platformContext.transform(matrix)
    }
    
    // MARK: - Path Operations
    
    /// Begins a new path.
    public func beginPath() {
        _platformContext.beginPath()
    }
    
    /// Moves to a point in the current path.
    ///
    /// - Parameter point: The point to move to.
    public func moveTo(_ point: Point) {
        _platformContext.moveTo(point)
    }
    
    /// Adds a line to a point in the current path.
    ///
    /// - Parameter point: The point to draw a line to.
    public func lineTo(_ point: Point) {
        _platformContext.lineTo(point)
    }
    
    /// Adds a quadratic Bézier curve to the current path.
    ///
    /// - Parameters:
    ///   - cp: The control point.
    ///   - end: The end point.
    public func quadraticCurveTo(cp: Point, end: Point) {
        _platformContext.quadraticCurveTo(cp: cp, end: end)
    }
    
    /// Adds a cubic Bézier curve to the current path.
    ///
    /// - Parameters:
    ///   - cp1: The first control point.
    ///   - cp2: The second control point.
    ///   - end: The end point.
    public func bezierCurveTo(cp1: Point, cp2: Point, end: Point) {
        _platformContext.bezierCurveTo(cp1: cp1, cp2: cp2, end: end)
    }
    
    /// Adds an arc to the current path.
    ///
    /// - Parameters:
    ///   - center: The center of the arc.
    ///   - radius: The radius of the arc.
    ///   - startAngle: The starting angle in radians.
    ///   - endAngle: The ending angle in radians.
    ///   - anticlockwise: Whether to draw counter-clockwise.
    public func arc(center: Point, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, anticlockwise: Bool) {
        _platformContext.arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, anticlockwise: anticlockwise)
    }
    
    /// Closes the current path.
    public func closePath() {
        _platformContext.closePath()
    }
    
    // MARK: - Drawing Operations
    
    /// Fills the current path with the current fill style.
    public func fill() {
        _platformContext.fill()
    }
    
    /// Strokes the current path with the current stroke style.
    public func stroke() {
        _platformContext.stroke()
    }
    
    /// Fills and strokes the current path.
    public func fillAndStroke() {
        fill()
        stroke()
    }
    
    /// Draws a filled rectangle.
    ///
    /// - Parameter rect: The rectangle to fill.
    public func fillRect(_ rect: Rectangle) {
        _platformContext.fillRect(rect)
    }
    
    /// Draws a stroked rectangle.
    ///
    /// - Parameter rect: The rectangle to stroke.
    public func strokeRect(_ rect: Rectangle) {
        _platformContext.strokeRect(rect)
    }
    
    /// Clears the specified rectangle.
    ///
    /// - Parameter rect: The rectangle to clear.
    public func clearRect(_ rect: Rectangle) {
        _platformContext.clearRect(rect)
    }
    
    // MARK: - Clipping
    
    /// Creates a clipping region from the current path.
    public func clip() {
        _platformContext.clip()
    }
    
    // MARK: - Text Rendering
    
    /// Draws text at the specified point.
    ///
    /// - Parameters:
    ///   - text: The text to draw.
    ///   - point: The point at which to draw the text.
    public func fillText(_ text: String, at point: Point) {
        _platformContext.fillText(text, at: point)
    }
    
    /// Draws stroked text at the specified point.
    ///
    /// - Parameters:
    ///   - text: The text to draw.
    ///   - point: The point at which to draw the text.
    public func strokeText(_ text: String, at point: Point) {
        _platformContext.strokeText(text, at: point)
    }
    
    /// Sets the font for text rendering.
    ///
    /// - Parameter font: The font to use.
    public func setFont(_ font: Font) {
        _platformContext.setFont(font)
    }
    
    /// Sets the text alignment.
    ///
    /// - Parameter alignment: The text alignment.
    public func setTextAlign(_ alignment: TextAlign) {
        _platformContext.setTextAlign(alignment)
    }
    
    // MARK: - Image Rendering
    
    /// Draws an image at the specified point.
    ///
    /// - Parameters:
    ///   - image: The image to draw.
    ///   - point: The point at which to draw the image.
    public func drawImage(_ image: Image, at point: Point) {
        _platformContext.drawImage(image, at: point)
    }
    
    /// Draws an image in the specified rectangle.
    ///
    /// - Parameters:
    ///   - image: The image to draw.
    ///   - rect: The rectangle in which to draw the image.
    public func drawImage(_ image: Image, in rect: Rectangle) {
        _platformContext.drawImage(image, in: rect)
    }
}

/// Text alignment options
public enum TextAlign: Sendable {
    case left
    case center
    case right
    case start
    case end
}

/// A 2D transformation matrix.
public struct TransformMatrix: Sendable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var e: CGFloat
    public var f: CGFloat
    
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, e: CGFloat, f: CGFloat) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
    }
    
    public static var identity: TransformMatrix {
        TransformMatrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
    }
}

/// Internal protocol for platform-specific graphics contexts
internal protocol AnyGraphicsContext {
    func setFillStyle(_ color: Color)
    func setStrokeStyle(_ color: Color)
    func setLineWidth(_ width: CGFloat)
    func save()
    func restore()
    func translate(x: CGFloat, y: CGFloat)
    func rotate(_ angle: CGFloat)
    func scale(x: CGFloat, y: CGFloat)
    func transform(_ matrix: TransformMatrix)
    func beginPath()
    func moveTo(_ point: Point)
    func lineTo(_ point: Point)
    func quadraticCurveTo(cp: Point, end: Point)
    func bezierCurveTo(cp1: Point, cp2: Point, end: Point)
    func arc(center: Point, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, anticlockwise: Bool)
    func closePath()
    func fill()
    func stroke()
    func fillRect(_ rect: Rectangle)
    func strokeRect(_ rect: Rectangle)
    func clearRect(_ rect: Rectangle)
    func clip()
    func fillText(_ text: String, at point: Point)
    func strokeText(_ text: String, at point: Point)
    func setFont(_ font: Font)
    func setTextAlign(_ alignment: TextAlign)
    func drawImage(_ image: Image, at point: Point)
    func drawImage(_ image: Image, in rect: Rectangle)
}