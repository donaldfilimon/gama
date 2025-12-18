import Foundation

/// The result of a rendering operation
public struct RenderResult: Sendable {
    public let success: Bool
    public let dirtyRect: Rectangle?
    
    public init(success: Bool, dirtyRect: Rectangle? = nil) {
        self.success = success
        self.dirtyRect = dirtyRect
    }
}

/// A protocol that defines the interface for platform-specific renderers.
///
/// Implementations of this protocol provide the rendering backend for the
/// unified graphics API. Each platform (Windows, macOS, Linux, Android) will
/// have its own implementation.
@MainActor
public protocol RendererProtocol: Sendable {
    /// The graphics context for this renderer.
    var graphicsContext: GraphicsContext { get }
    
    /// Renders a view into the specified rectangle.
    ///
    /// - Parameters:
    ///   - view: The root view to render.
    ///   - rect: The rectangle in which to render the view.
    /// - Returns: The result of the rendering operation.
    func render<V: View>(_ view: V, in rect: Rectangle) async -> RenderResult
    
    /// Prepares the renderer for a new frame.
    func beginFrame()
    
    /// Completes the current frame and presents it.
    func endFrame()
    
    /// Clears the rendering surface with the specified color.
    ///
    /// - Parameter color: The color to use for clearing.
    func clear(with color: Color)
}