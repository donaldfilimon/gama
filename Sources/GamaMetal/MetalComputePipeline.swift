// MetalComputePipeline.swift — Metal compute pipeline wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// A compiled Metal compute pipeline state conforming to ``GPUComputePipeline``.
///
/// Wraps an `MTLComputePipelineState` built from a ``GPUComputePipelineDescriptor``.
public final class MetalComputePipeline: GPUComputePipeline, @unchecked Sendable {
    /// The underlying Metal compute pipeline state.
    public let pipelineState: MTLComputePipelineState

    /// An optional debug label for this pipeline.
    public let label: String?

    /// Creates a compute pipeline wrapping an existing Metal compute pipeline state.
    ///
    /// - Parameters:
    ///   - pipelineState: The compiled `MTLComputePipelineState`.
    ///   - label: An optional debug label.
    public init(pipelineState: MTLComputePipelineState, label: String? = nil) {
        self.pipelineState = pipelineState
        self.label = label
    }

    /// Creates a Metal compute pipeline from a GamaCore compute pipeline descriptor.
    ///
    /// - Parameters:
    ///   - descriptor: The cross-platform compute pipeline descriptor.
    ///   - device: The Metal device to compile the pipeline on.
    /// - Throws: ``GPUError/pipelineCreationFailed(_:)`` if compilation fails.
    public static func make(
        descriptor: GPUComputePipelineDescriptor,
        device: MTLDevice
    ) throws -> MetalComputePipeline {
        guard let metalModule = descriptor.computeFunction.module as? MetalShaderModule else {
            throw GPUError.pipelineCreationFailed(
                "Compute shader module must be a MetalShaderModule"
            )
        }

        let entryPoint = descriptor.computeFunction.entryPoint
        guard let function = metalModule.makeFunction(name: entryPoint) else {
            throw GPUError.pipelineCreationFailed(
                "Compute entry point '\(entryPoint)' not found in shader module"
            )
        }

        do {
            let pipelineState = try device.makeComputePipelineState(function: function)
            return MetalComputePipeline(pipelineState: pipelineState, label: descriptor.label)
        } catch {
            throw GPUError.pipelineCreationFailed(error.localizedDescription)
        }
    }

    /// The maximum total number of threads per threadgroup for this pipeline.
    public var maxTotalThreadsPerThreadgroup: Int {
        pipelineState.maxTotalThreadsPerThreadgroup
    }

    /// The execution width (SIMD width) for this pipeline.
    public var threadExecutionWidth: Int {
        pipelineState.threadExecutionWidth
    }
}

#endif
