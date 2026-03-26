// MetalSampler.swift — Metal sampler state wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// A Metal sampler state that defines texture sampling parameters.
///
/// Wraps an `MTLSamplerState`. Metal sampler states are immutable and
/// internally thread-safe, so this type is marked `@unchecked Sendable`.
public final class MetalSampler: GPUSampler, @unchecked Sendable {
    /// The underlying Metal sampler state.
    public let mtlSamplerState: MTLSamplerState

    /// An optional debug label for the sampler.
    public let label: String?

    /// Creates a Metal sampler wrapper.
    /// - Parameters:
    ///   - samplerState: The `MTLSamplerState` to wrap.
    ///   - label: An optional debug label.
    public init(samplerState: MTLSamplerState, label: String? = nil) {
        self.mtlSamplerState = samplerState
        self.label = label
    }
}

#endif
