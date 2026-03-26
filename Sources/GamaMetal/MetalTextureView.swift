#if canImport(Metal)
import Metal
import GamaCore

/// A Metal texture view wrapping an MTLTexture (which natively supports views).
public final class MetalTextureView: GPUTextureView, @unchecked Sendable {
    public let mtlTexture: MTLTexture
    public let texture: any GPUTexture
    public let label: String?

    public init(mtlTexture: MTLTexture, sourceTexture: any GPUTexture, label: String?) {
        self.mtlTexture = mtlTexture
        self.texture = sourceTexture
        self.label = label
    }
}
#endif
