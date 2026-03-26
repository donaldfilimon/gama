// Texture.swift — GPU texture protocol, descriptor, and dimension enum
// Part of GamaCore

// MARK: - Texture Dimension

/// The dimensionality of a texture resource.
public enum TextureDimension: Sendable {
    /// A one-dimensional texture.
    case d1
    /// A two-dimensional texture.
    case d2
    /// A three-dimensional texture.
    case d3
}

// MARK: - Texture Descriptor

/// Describes the properties of a GPU texture to be created.
///
/// Types referenced from `Types.swift`: ``PixelFormat``, ``TextureUsage``.
public struct GPUTextureDescriptor: Sendable {
    /// The width of the texture in texels.
    public var width: UInt32

    /// The height of the texture in texels.
    public var height: UInt32

    /// The depth of the texture in texels (for 3D textures).
    public var depth: UInt32

    /// The pixel format of the texture.
    public var format: PixelFormat

    /// A bitmask specifying the intended usage of the texture.
    public var usage: TextureUsage

    /// The dimensionality of the texture.
    public var dimension: TextureDimension

    /// The number of mipmap levels. Defaults to 1 (no mipmaps).
    public var mipLevelCount: UInt32

    /// The number of samples per texel for multisampled textures. Defaults to 1.
    public var sampleCount: UInt32

    /// An optional label for debugging purposes.
    public var label: String?

    /// Creates a new texture descriptor with full control over all parameters.
    /// - Parameters:
    ///   - width: The width of the texture in texels.
    ///   - height: The height of the texture in texels.
    ///   - depth: The depth of the texture in texels.
    ///   - format: The pixel format.
    ///   - usage: The intended usage flags.
    ///   - dimension: The dimensionality of the texture.
    ///   - mipLevelCount: The number of mipmap levels (default 1).
    ///   - sampleCount: The number of samples per texel (default 1).
    ///   - label: An optional debug label.
    public init(
        width: UInt32,
        height: UInt32,
        depth: UInt32,
        format: PixelFormat,
        usage: TextureUsage,
        dimension: TextureDimension,
        mipLevelCount: UInt32 = 1,
        sampleCount: UInt32 = 1,
        label: String? = nil
    ) {
        self.width = width
        self.height = height
        self.depth = depth
        self.format = format
        self.usage = usage
        self.dimension = dimension
        self.mipLevelCount = mipLevelCount
        self.sampleCount = sampleCount
        self.label = label
    }

    /// Convenience initializer for a common 2D texture.
    /// - Parameters:
    ///   - width: The width of the texture in texels.
    ///   - height: The height of the texture in texels.
    ///   - format: The pixel format.
    ///   - usage: The intended usage flags.
    ///   - mipLevelCount: The number of mipmap levels (default 1).
    ///   - sampleCount: The number of samples per texel (default 1).
    ///   - label: An optional debug label.
    public init(
        width: UInt32,
        height: UInt32,
        format: PixelFormat,
        usage: TextureUsage,
        mipLevelCount: UInt32 = 1,
        sampleCount: UInt32 = 1,
        label: String? = nil
    ) {
        self.init(
            width: width,
            height: height,
            depth: 1,
            format: format,
            usage: usage,
            dimension: .d2,
            mipLevelCount: mipLevelCount,
            sampleCount: sampleCount,
            label: label
        )
    }
}

// MARK: - Texture Protocol

/// A GPU texture resource that stores image data in a specific pixel format.
///
/// Concrete implementations are provided by backend modules (e.g., GamaMetal).
public protocol GPUTexture: AnyObject, Sendable {
    /// The descriptor used to create this texture.
    var descriptor: GPUTextureDescriptor { get }

    /// The width of the texture in texels.
    var width: UInt32 { get }

    /// The height of the texture in texels.
    var height: UInt32 { get }

    /// The pixel format of the texture.
    var format: PixelFormat { get }

    /// Replaces a region of the texture with data from CPU memory.
    ///
    /// - Parameters:
    ///   - origin: The texel coordinate of the region's origin.
    ///   - size: The extent (width, height, depth) of the region to replace.
    ///   - mipLevel: The mipmap level to write into.
    ///   - data: A pointer to the source pixel data.
    ///   - bytesPerRow: The stride in bytes between rows of source data.
    func replaceRegion(
        origin: Origin3D,
        size: Extent3D,
        mipLevel: UInt32,
        data: UnsafeRawPointer,
        bytesPerRow: Int
    )

    /// Create a view of this texture.
    func createView(descriptor: GPUTextureViewDescriptor) throws -> any GPUTextureView
}

extension GPUTexture {
    public func createView(descriptor: GPUTextureViewDescriptor = GPUTextureViewDescriptor()) throws -> any GPUTextureView {
        try createView(descriptor: descriptor)
    }
}
