// Surface.swift — GPU surface protocol for presentable rendering targets
// Part of GamaCore

// MARK: - Present Mode

/// Presentation mode for a surface.
public enum PresentMode: Sendable {
    /// Vertical sync — wait for display refresh.
    case vsync
    /// Immediate — present as soon as possible, may tear.
    case immediate
    /// Mailbox — like vsync but drops old frames.
    case mailbox
}

// MARK: - Surface Configuration

/// Describes a surface's configuration.
public struct GPUSurfaceConfiguration: Sendable {
    /// The pixel format for the surface.
    public var format: PixelFormat
    /// The width of the surface in pixels.
    public var width: UInt32
    /// The height of the surface in pixels.
    public var height: UInt32
    /// The presentation mode.
    public var presentMode: PresentMode
    /// The texture usage for surface textures.
    public var usage: TextureUsage

    /// Creates a surface configuration.
    /// - Parameters:
    ///   - format: The pixel format (default `.bgra8Unorm`).
    ///   - width: The width of the surface in pixels.
    ///   - height: The height of the surface in pixels.
    ///   - presentMode: The presentation mode (default `.vsync`).
    ///   - usage: The texture usage for surface textures (default `.renderTarget`).
    public init(
        format: PixelFormat = .bgra8Unorm,
        width: UInt32,
        height: UInt32,
        presentMode: PresentMode = .vsync,
        usage: TextureUsage = .renderTarget
    ) {
        self.format = format
        self.width = width
        self.height = height
        self.presentMode = presentMode
        self.usage = usage
    }
}

// MARK: - Surface Protocol

/// A presentable surface that provides drawable textures for rendering.
///
/// Surfaces represent the connection between the GPU and a display target
/// (e.g., a window, layer, or view). Each frame, call ``nextTexture()`` to
/// get the current drawable texture, render into it, then call ``present()``
/// to display it.
public protocol GPUSurface: AnyObject, Sendable {
    /// Configure the surface for rendering.
    ///
    /// - Parameters:
    ///   - device: The GPU device to associate with this surface.
    ///   - configuration: The surface configuration describing format, size, and present mode.
    func configure(device: any GPUDevice, configuration: GPUSurfaceConfiguration) throws

    /// Get the next drawable texture for rendering.
    ///
    /// This blocks until a drawable is available.
    /// - Returns: A texture to render into for the current frame.
    func nextTexture() throws -> any GPUTexture

    /// Present the current drawable to the display.
    func present() throws

    /// Resize the surface.
    ///
    /// - Parameters:
    ///   - width: The new width in pixels.
    ///   - height: The new height in pixels.
    func resize(width: UInt32, height: UInt32)
}
