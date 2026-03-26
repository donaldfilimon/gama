// MetalDepthStencilState.swift — Metal depth-stencil state wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

// MARK: - MetalDepthStencilState

/// A compiled Metal depth-stencil state object conforming to ``GPUDepthStencilStateObject``.
///
/// Wraps an `MTLDepthStencilState` created from a ``GPUDepthStencilDescriptor``.
public final class MetalDepthStencilState: GPUDepthStencilStateObject, @unchecked Sendable {
    /// The underlying Metal depth-stencil state.
    public let mtlDepthStencilState: MTLDepthStencilState

    /// The descriptor used to create this state object.
    public let descriptor: GPUDepthStencilDescriptor

    /// Creates a Metal depth-stencil state wrapping the given Metal state.
    ///
    /// - Parameters:
    ///   - state: The `MTLDepthStencilState` to wrap.
    ///   - descriptor: The descriptor that was used to create this state.
    public init(state: MTLDepthStencilState, descriptor: GPUDepthStencilDescriptor) {
        self.mtlDepthStencilState = state
        self.descriptor = descriptor
    }
}

// MARK: - Factory Helpers

extension MetalDepthStencilState {
    /// Creates a Metal depth-stencil state from a descriptor and device.
    ///
    /// - Parameters:
    ///   - descriptor: The depth-stencil descriptor.
    ///   - device: The Metal device to create the state on.
    /// - Throws: ``GPUError/unsupportedOperation(_:)`` if the state cannot be created.
    /// - Returns: A compiled ``MetalDepthStencilState``.
    static func make(
        descriptor: GPUDepthStencilDescriptor,
        device: MTLDevice
    ) throws -> MetalDepthStencilState {
        let mtlDesc = MTLDepthStencilDescriptor()
        mtlDesc.depthCompareFunction = descriptor.depthCompare.mtlCompareFunction
        mtlDesc.isDepthWriteEnabled = descriptor.depthWriteEnabled
        mtlDesc.frontFaceStencil = descriptor.stencilFront.mtlStencilDescriptor
        mtlDesc.backFaceStencil = descriptor.stencilBack.mtlStencilDescriptor

        guard let state = device.makeDepthStencilState(descriptor: mtlDesc) else {
            throw GPUError.unsupportedOperation("Failed to create depth-stencil state")
        }
        return MetalDepthStencilState(state: state, descriptor: descriptor)
    }
}

#endif
