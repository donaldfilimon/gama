// MetalSurface.swift — Metal surface wrapping CAMetalLayer
// Part of GamaMetal

#if canImport(Metal)
import Metal
import QuartzCore
import GamaCore

// MARK: - MetalSurface

/// A Metal surface conforming to ``GPUSurface``.
///
/// Wraps a `CAMetalLayer` to provide drawable textures for rendering to screen.
/// Create a `CAMetalLayer`, pass it to ``init(layer:)``, then configure and
/// render each frame.
public final class MetalSurface: GPUSurface, @unchecked Sendable {
    /// The underlying Core Animation Metal layer.
    public let metalLayer: CAMetalLayer

    /// The current drawable, valid between ``nextTexture()`` and ``present()`` calls.
    private var currentDrawable: CAMetalDrawable?

    /// Creates a Metal surface wrapping the given layer.
    /// - Parameter layer: The `CAMetalLayer` to wrap.
    public init(layer: CAMetalLayer) {
        self.metalLayer = layer
    }

    /// Configure the surface for rendering.
    public func configure(device: any GPUDevice, configuration: GPUSurfaceConfiguration) throws {
        guard let metalDevice = device as? MetalDevice else {
            throw GPUError.unsupportedOperation("MetalSurface requires a MetalDevice")
        }
        metalLayer.device = metalDevice.mtlDevice
        metalLayer.pixelFormat = configuration.format.mtlPixelFormat
        metalLayer.drawableSize = CGSize(
            width: CGFloat(configuration.width),
            height: CGFloat(configuration.height)
        )
        metalLayer.displaySyncEnabled = configuration.presentMode == .vsync
    }

    /// Get the next drawable texture for this frame.
    public func nextTexture() throws -> any GPUTexture {
        guard let drawable = metalLayer.nextDrawable() else {
            throw GPUError.textureCreationFailed
        }
        currentDrawable = drawable

        let desc = GPUTextureDescriptor(
            width: UInt32(drawable.texture.width),
            height: UInt32(drawable.texture.height),
            format: .bgra8Unorm,
            usage: .renderTarget
        )
        return MetalDrawableTexture(texture: drawable.texture, descriptor: desc)
    }

    /// Present the current drawable to the display.
    public func present() throws {
        guard let drawable = currentDrawable else {
            throw GPUError.unsupportedOperation("No drawable to present — call nextTexture() first")
        }
        drawable.present()
        currentDrawable = nil
    }

    /// Resize the surface.
    public func resize(width: UInt32, height: UInt32) {
        metalLayer.drawableSize = CGSize(
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

// MARK: - MetalDrawableTexture

/// A thin wrapper around a drawable's `MTLTexture` that conforms to ``GPUTexture``.
///
/// Unlike ``MetalTexture``, this does not own the texture — the drawable does.
/// The texture is only valid for the current frame.
final class MetalDrawableTexture: GPUTexture, @unchecked Sendable {
    /// The underlying Metal texture from the drawable.
    let mtlTexture: MTLTexture

    /// The descriptor describing this drawable texture.
    public let descriptor: GPUTextureDescriptor

    /// The width of the texture in texels.
    public var width: UInt32 { UInt32(mtlTexture.width) }

    /// The height of the texture in texels.
    public var height: UInt32 { UInt32(mtlTexture.height) }

    /// The pixel format of the texture.
    public var format: PixelFormat { descriptor.format }

    /// Creates a drawable texture wrapper.
    /// - Parameters:
    ///   - texture: The `MTLTexture` from a `CAMetalDrawable`.
    ///   - descriptor: The GamaCore descriptor describing this texture.
    init(texture: MTLTexture, descriptor: GPUTextureDescriptor) {
        self.mtlTexture = texture
        self.descriptor = descriptor
    }

    /// Drawable textures do not support region replacement.
    public func replaceRegion(
        origin: Origin3D, size: Extent3D, mipLevel: UInt32,
        data: UnsafeRawPointer, bytesPerRow: Int
    ) {
        fatalError("replaceRegion is not supported on drawable textures")
    }

    /// Drawable textures do not support creating views.
    public func createView(descriptor: GPUTextureViewDescriptor) throws -> any GPUTextureView {
        throw GPUError.unsupportedOperation("Drawable textures do not support creating views")
    }
}

#endif
