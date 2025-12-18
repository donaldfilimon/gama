import Foundation

/// A view that provides drawing capabilities using an immediate-mode API.
///
/// Use `Canvas` for custom drawing that doesn't require a full view hierarchy.
/// The drawing context provides Canvas 2D API-like operations:
///
/// ```swift
/// Canvas { context, size in
///     context.fillStyle = .blue
///     context.fillRect(x: 0, y: 0, width: size.width, height: size.height)
/// }
/// ```
@MainActor
public struct Canvas<Content>: View where Content: View {
    @ViewBuilder private let content: (GraphicsContext, Size) -> Content
    
    /// Creates a canvas with drawing content.
    ///
    /// - Parameter content: A view builder that receives a graphics context
    ///   and the canvas size.
    public init(@ViewBuilder content: @escaping (GraphicsContext, Size) -> Content) {
        self.content = content
    }
    
    public var body: some View {
        // Canvas rendering would be implemented here
        // This is a placeholder
        EmptyView()
    }
}

/// Extension for simpler canvas usage without return value
extension Canvas where Content == EmptyView {
    /// Creates a canvas with drawing operations.
    ///
    /// - Parameter content: A closure that receives a graphics context
    ///   and the canvas size.
    public init(content: @escaping (GraphicsContext, Size) -> Void) {
        self.content = { context, size in
            content(context, size)
            return EmptyView()
        }
    }
}