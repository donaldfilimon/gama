// TextureView.swift — Texture view protocol for GamaCore
// Part of GamaCore

// MARK: - Texture View Descriptor

/// Describes how to create a view into a texture.
public struct GPUTextureViewDescriptor: Sendable {
    /// The pixel format to reinterpret the texture as (nil = same as source).
    public var format: PixelFormat?
    /// The texture dimension for the view (nil = same as source).
    public var dimension: TextureDimension?
    /// The first mip level accessible to the view.
    public var baseMipLevel: UInt32
    /// The number of mip levels accessible (0 = all remaining).
    public var mipLevelCount: UInt32
    /// The first array layer accessible to the view.
    public var baseArrayLayer: UInt32
    /// The number of array layers accessible (0 = all remaining).
    public var arrayLayerCount: UInt32
    /// An optional debug label.
    public var label: String?

    public init(
        format: PixelFormat? = nil,
        dimension: TextureDimension? = nil,
        baseMipLevel: UInt32 = 0,
        mipLevelCount: UInt32 = 0,
        baseArrayLayer: UInt32 = 0,
        arrayLayerCount: UInt32 = 0,
        label: String? = nil
    ) {
        self.format = format
        self.dimension = dimension
        self.baseMipLevel = baseMipLevel
        self.mipLevelCount = mipLevelCount
        self.baseArrayLayer = baseArrayLayer
        self.arrayLayerCount = arrayLayerCount
        self.label = label
    }
}

// MARK: - Texture View Protocol

/// A view into a texture, potentially reinterpreting format or selecting a subset.
public protocol GPUTextureView: AnyObject, Sendable {
    /// The source texture this view was created from.
    var texture: any GPUTexture { get }
    /// An optional debug label.
    var label: String? { get }
}
