// Sampler.swift — GPU sampler protocol, descriptor, and related enums
// Part of GamaCore

// MARK: - Sampler Address Mode

/// Determines how texture coordinates outside the [0, 1] range are handled.
public enum SamplerAddressMode: Sendable {
    /// Clamp the texture coordinate to the range [0, 1].
    case clampToEdge
    /// Tile the texture by wrapping coordinates.
    case `repeat`
    /// Tile the texture, mirroring on each integer boundary.
    case mirrorRepeat
    /// Out-of-range coordinates return transparent zero.
    case clampToZero
}

// MARK: - Sampler Filters

/// The filtering mode applied when the texture is sampled at a size
/// smaller or larger than the original texture resolution.
public enum SamplerMinMagFilter: Sendable {
    /// Select the single texel nearest to the sample point.
    case nearest
    /// Linearly interpolate between the four nearest texels.
    case linear
}

/// The filtering mode applied between mipmap levels.
public enum SamplerMipFilter: Sendable {
    /// Do not use mipmapping.
    case notMipmapped
    /// Select the nearest mipmap level.
    case nearest
    /// Linearly interpolate between the two nearest mipmap levels.
    case linear
}

// MARK: - Sampler Descriptor

/// Describes the properties of a GPU sampler to be created.
///
/// `CompareFunction` is defined in `Types.swift`.
public struct GPUSamplerDescriptor: Sendable {
    /// The minification filter.
    public var minFilter: SamplerMinMagFilter

    /// The magnification filter.
    public var magFilter: SamplerMinMagFilter

    /// The mipmap filtering mode.
    public var mipFilter: SamplerMipFilter

    /// The address mode for the U (horizontal / S) texture coordinate.
    public var addressModeU: SamplerAddressMode

    /// The address mode for the V (vertical / T) texture coordinate.
    public var addressModeV: SamplerAddressMode

    /// The address mode for the W (depth / R) texture coordinate.
    public var addressModeW: SamplerAddressMode

    /// The maximum anisotropy level. Must be at least 1.
    public var maxAnisotropy: UInt32

    /// An optional comparison function used for depth-comparison sampling.
    public var compareFunction: CompareFunction?

    /// An optional label for debugging purposes.
    public var label: String?

    /// Creates a new sampler descriptor.
    /// - Parameters:
    ///   - minFilter: The minification filter.
    ///   - magFilter: The magnification filter.
    ///   - mipFilter: The mipmap filtering mode (default `.notMipmapped`).
    ///   - addressModeU: Address mode for U coordinate (default `.clampToEdge`).
    ///   - addressModeV: Address mode for V coordinate (default `.clampToEdge`).
    ///   - addressModeW: Address mode for W coordinate (default `.clampToEdge`).
    ///   - maxAnisotropy: Maximum anisotropy level (default 1).
    ///   - compareFunction: Optional depth-comparison function (default `nil`).
    ///   - label: An optional debug label.
    public init(
        minFilter: SamplerMinMagFilter = .nearest,
        magFilter: SamplerMinMagFilter = .nearest,
        mipFilter: SamplerMipFilter = .notMipmapped,
        addressModeU: SamplerAddressMode = .clampToEdge,
        addressModeV: SamplerAddressMode = .clampToEdge,
        addressModeW: SamplerAddressMode = .clampToEdge,
        maxAnisotropy: UInt32 = 1,
        compareFunction: CompareFunction? = nil,
        label: String? = nil
    ) {
        self.minFilter = minFilter
        self.magFilter = magFilter
        self.mipFilter = mipFilter
        self.addressModeU = addressModeU
        self.addressModeV = addressModeV
        self.addressModeW = addressModeW
        self.maxAnisotropy = maxAnisotropy
        self.compareFunction = compareFunction
        self.label = label
    }
}

// MARK: - Sampler Protocol

/// A GPU sampler state object that defines how textures are sampled in shaders.
///
/// Concrete implementations are provided by backend modules (e.g., GamaMetal).
public protocol GPUSampler: AnyObject, Sendable {
    /// An optional debug label for the sampler.
    var label: String? { get }
}
