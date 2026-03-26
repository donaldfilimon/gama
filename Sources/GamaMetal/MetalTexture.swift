// MetalTexture.swift — Metal texture wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// A Metal texture that stores image data.
///
/// Wraps an `MTLTexture`. Metal textures are internally thread-safe for
/// read access, so this type is marked `@unchecked Sendable`.
public final class MetalTexture: GPUTexture, @unchecked Sendable {
    /// The underlying Metal texture.
    public let mtlTexture: MTLTexture

    /// The descriptor used to create this texture.
    public let descriptor: GPUTextureDescriptor

    /// The width of the texture in texels.
    public var width: UInt32 { UInt32(mtlTexture.width) }

    /// The height of the texture in texels.
    public var height: UInt32 { UInt32(mtlTexture.height) }

    /// The pixel format of the texture.
    public var format: PixelFormat { descriptor.format }

    /// Creates a Metal texture wrapper.
    /// - Parameters:
    ///   - texture: The `MTLTexture` to wrap.
    ///   - descriptor: The GamaCore descriptor used to create this texture.
    public init(texture: MTLTexture, descriptor: GPUTextureDescriptor) {
        self.mtlTexture = texture
        self.descriptor = descriptor
    }

    /// Replaces a region of the texture with data from CPU memory.
    ///
    /// Maps the GamaCore origin/size to a Metal `MTLRegion` and calls
    /// the underlying Metal texture's `replace` method.
    ///
    /// - Parameters:
    ///   - origin: The texel coordinate of the region's origin.
    ///   - size: The extent (width, height, depth) of the region to replace.
    ///   - mipLevel: The mipmap level to write into.
    ///   - data: A pointer to the source pixel data.
    ///   - bytesPerRow: The stride in bytes between rows of source data.
    public func replaceRegion(
        origin: Origin3D,
        size: Extent3D,
        mipLevel: UInt32,
        data: UnsafeRawPointer,
        bytesPerRow: Int
    ) {
        let mtlOrigin = MTLOrigin(
            x: Int(origin.x),
            y: Int(origin.y),
            z: Int(origin.z)
        )
        let mtlSize = MTLSize(
            width: Int(size.width),
            height: Int(size.height),
            depth: Int(size.depth)
        )
        let region = MTLRegion(origin: mtlOrigin, size: mtlSize)

        mtlTexture.replace(
            region: region,
            mipmapLevel: Int(mipLevel),
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
    }

    /// Creates a view into this texture, optionally reinterpreting format or selecting a mip/layer subset.
    public func createView(descriptor: GPUTextureViewDescriptor) throws -> any GPUTextureView {
        let pixelFormat = descriptor.format?.mtlPixelFormat ?? mtlTexture.pixelFormat
        let textureType = descriptor.dimension?.mtlTextureType ?? mtlTexture.textureType

        // Resolve 0 → "all remaining" for mip levels and array layers.
        let totalMipLevels = mtlTexture.mipmapLevelCount
        let mipCount = descriptor.mipLevelCount == 0
            ? totalMipLevels - Int(descriptor.baseMipLevel)
            : Int(descriptor.mipLevelCount)

        let totalArrayLayers = mtlTexture.arrayLength
        let layerCount = descriptor.arrayLayerCount == 0
            ? totalArrayLayers - Int(descriptor.baseArrayLayer)
            : Int(descriptor.arrayLayerCount)

        guard let viewTexture = mtlTexture.makeTextureView(
            pixelFormat: pixelFormat,
            textureType: textureType,
            levels: Int(descriptor.baseMipLevel)..<(Int(descriptor.baseMipLevel) + mipCount),
            slices: Int(descriptor.baseArrayLayer)..<(Int(descriptor.baseArrayLayer) + layerCount)
        ) else {
            throw GPUError.textureCreationFailed
        }

        if let label = descriptor.label {
            viewTexture.label = label
        }

        return MetalTextureView(mtlTexture: viewTexture, sourceTexture: self, label: descriptor.label)
    }
}

#endif
