import Foundation
#if os(macOS) || os(iOS) || os(tvOS)
import CoreGraphics
#endif

/// Apple Core Graphics wrapper - provides drawing capabilities using CGContext
#if os(macOS) || os(iOS) || os(tvOS)
public class AppleGraphics {
    private var context: CGContext?

    /// Initialize with a CGContext
    public init(context: CGContext) {
        self.context = context
    }

    /// Initialize with a bitmap context
    public convenience init(width: Int, height: Int, bitsPerComponent: Int = 8, bytesPerRow: Int? = nil, colorSpace: CGColorSpace? = nil, bitmapInfo: CGBitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue) {
        let actualBytesPerRow = bytesPerRow ?? (width * 4) // Assume RGBA
        let actualColorSpace = colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: bitsPerComponent,
                                    bytesPerRow: actualBytesPerRow,
                                    space: actualColorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            fatalError("Failed to create bitmap context")
        }

        self.init(context: context)
    }

    /// Get the underlying CGContext
    public var cgContext: CGContext? {
        return context
    }

    /// Check if graphics context is valid
    public var isValid: Bool {
        return context != nil
    }

    /// Save the current graphics state
    public func saveState() {
        context?.saveGState()
    }

    /// Restore the graphics state
    public func restoreState() {
        context?.restoreGState()
    }

    /// Set the current fill color
    public func setFillColor(_ color: Color) {
        context?.setFillColor(CGColor(red: CGFloat(color.r) / 255.0,
                                    green: CGFloat(color.g) / 255.0,
                                    blue: CGFloat(color.b) / 255.0,
                                    alpha: CGFloat(color.a) / 255.0))
    }

    /// Set the current stroke color
    public func setStrokeColor(_ color: Color) {
        context?.setStrokeColor(CGColor(red: CGFloat(color.r) / 255.0,
                                       green: CGFloat(color.g) / 255.0,
                                       blue: CGFloat(color.b) / 255.0,
                                       alpha: CGFloat(color.a) / 255.0))
    }

    /// Set the line width
    public func setLineWidth(_ width: CGFloat) {
        context?.setLineWidth(width)
    }

    /// Set the line cap style
    public func setLineCap(_ cap: CGLineCap) {
        context?.setLineCap(cap)
    }

    /// Set the line join style
    public func setLineJoin(_ join: CGLineJoin) {
        context?.setLineJoin(join)
    }

    /// Draw a line from point A to point B
    public func drawLine(from start: Point, to end: Point) {
        context?.move(to: CGPoint(x: CGFloat(start.x), y: CGFloat(start.y)))
        context?.addLine(to: CGPoint(x: CGFloat(end.x), y: CGFloat(end.y)))
        context?.strokePath()
    }

    /// Draw a rectangle
    public func drawRectangle(_ rect: Rectangle, fill: Bool = false) {
        let cgRect = CGRect(x: CGFloat(rect.left),
                          y: CGFloat(rect.top),
                          width: CGFloat(rect.width),
                          height: CGFloat(rect.height))

        if fill {
            context?.fill(cgRect)
        } else {
            context?.stroke(cgRect)
        }
    }

    /// Fill a rectangle
    public func fillRectangle(_ rect: Rectangle) {
        drawRectangle(rect, fill: true)
    }

    /// Stroke a rectangle
    public func strokeRectangle(_ rect: Rectangle) {
        drawRectangle(rect, fill: false)
    }

    /// Draw an ellipse (circle/oval)
    public func drawEllipse(in rect: Rectangle, fill: Bool = false) {
        let cgRect = CGRect(x: CGFloat(rect.left),
                          y: CGFloat(rect.top),
                          width: CGFloat(rect.width),
                          height: CGFloat(rect.height))

        if fill {
            context?.fillEllipse(in: cgRect)
        } else {
            context?.strokeEllipse(in: cgRect)
        }
    }

    /// Fill an ellipse
    public func fillEllipse(in rect: Rectangle) {
        drawEllipse(in: rect, fill: true)
    }

    /// Stroke an ellipse
    public func strokeEllipse(in rect: Rectangle) {
        drawEllipse(in: rect, fill: false)
    }

    /// Draw text at a point
    public func drawText(_ text: String, at point: Point, font: CGFont? = nil, fontSize: CGFloat = 12.0) {
        let attributedString = NSAttributedString(string: text, attributes: [
            .font: font ?? CGFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ])

        let line = CTLineCreateWithAttributedString(attributedString)
        let cgPoint = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))

        context?.textPosition = cgPoint
        CTLineDraw(line, context!)
    }

    /// Draw a path
    public func drawPath(_ path: CGPath, fill: Bool = false) {
        context?.addPath(path)

        if fill {
            context?.fillPath()
        } else {
            context?.strokePath()
        }
    }

    /// Create a new path
    public func createPath() -> CGMutablePath {
        return CGMutablePath()
    }

    /// Add a line to the current path
    public func addLine(to point: Point) {
        context?.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
    }

    /// Move to a point in the current path
    public func move(to point: Point) {
        context?.move(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
    }

    /// Close the current path
    public func closePath() {
        context?.closePath()
    }

    /// Begin a new path
    public func beginPath() {
        context?.beginPath()
    }

    /// Stroke the current path
    public func strokePath() {
        context?.strokePath()
    }

    /// Fill the current path
    public func fillPath() {
        context?.fillPath()
    }

    /// Clip to the current path
    public func clipToPath() {
        context?.clip()
    }

    /// Create an image from the graphics context
    public func createImage() -> CGImage? {
        return context?.makeImage()
    }

    /// Clear the entire context with a color
    public func clear(with color: Color) {
        guard let context = context else { return }

        let cgColor = CGColor(red: CGFloat(color.r) / 255.0,
                             green: CGFloat(color.g) / 255.0,
                             blue: CGFloat(color.b) / 255.0,
                             alpha: CGFloat(color.a) / 255.0)

        context.setFillColor(cgColor)
        context.fill(context.boundingBoxOfClipPath)
    }

    /// Flush any pending drawing operations
    public func flush() {
        context?.flush()
    }

    /// Get the size of the graphics context
    public var size: Size {
        guard let context = context else { return Size(width: 0, height: 0) }
        let rect = context.boundingBoxOfClipPath
        return Size(width: Int32(rect.width), height: Int32(rect.height))
    }

    /// Get the scale factor of the context
    public var scale: CGFloat {
        return context?.ctm.a ?? 1.0
    }

    /// Set the scale factor
    public func setScale(_ scale: CGFloat) {
        context?.scaleBy(x: scale, y: scale)
    }

    /// Translate the coordinate system
    public func translateBy(x: CGFloat, y: CGFloat) {
        context?.translateBy(x: x, y: y)
    }

    /// Rotate the coordinate system
    public func rotate(by angle: CGFloat) {
        context?.rotate(by: angle)
    }

    /// Apply a transformation
    public func transform(using transform: CGAffineTransform) {
        context?.concatenate(transform)
    }

    /// Push a new transformation state
    public func pushTransformation() {
        saveState()
    }

    /// Pop the transformation state
    public func popTransformation() {
        restoreState()
    }
}

/// Apple-specific graphics extensions
public extension AppleGraphics {
    /// Draw a rounded rectangle
    func drawRoundedRectangle(_ rect: Rectangle, cornerRadius: CGFloat, fill: Bool = false) {
        let cgRect = CGRect(x: CGFloat(rect.left),
                          y: CGFloat(rect.top),
                          width: CGFloat(rect.width),
                          height: CGFloat(rect.height))

        let path = CGPath(roundedRect: cgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        drawPath(path, fill: fill)
    }

    /// Draw an arc
    func drawArc(center: Point, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool = false) {
        let cgCenter = CGPoint(x: CGFloat(center.x), y: CGFloat(center.y))
        context?.addArc(center: cgCenter, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
        context?.strokePath()
    }

    /// Draw a bezier curve
    func drawCurve(from start: Point, to end: Point, controlPoint1: Point, controlPoint2: Point) {
        let cgStart = CGPoint(x: CGFloat(start.x), y: CGFloat(start.y))
        let cgEnd = CGPoint(x: CGFloat(end.x), y: CGFloat(end.y))
        let cgControl1 = CGPoint(x: CGFloat(controlPoint1.x), y: CGFloat(controlPoint1.y))
        let cgControl2 = CGPoint(x: CGFloat(controlPoint2.x), y: CGFloat(controlPoint2.y))

        context?.move(to: cgStart)
        context?.addCurve(to: cgEnd, control1: cgControl1, control2: cgControl2)
        context?.strokePath()
    }

    /// Draw a quadratic bezier curve
    func drawQuadCurve(from start: Point, to end: Point, controlPoint: Point) {
        let cgStart = CGPoint(x: CGFloat(start.x), y: CGFloat(start.y))
        let cgEnd = CGPoint(x: CGFloat(end.x), y: CGFloat(end.y))
        let cgControl = CGPoint(x: CGFloat(controlPoint.x), y: CGFloat(controlPoint.y))

        context?.move(to: cgStart)
        context?.addQuadCurve(to: cgEnd, control: cgControl)
        context?.strokePath()
    }
}
#endif