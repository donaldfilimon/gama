// MetalRenderPipeline.swift — Metal render pipeline wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// A compiled Metal render pipeline state conforming to ``GPURenderPipeline``.
///
/// Wraps an `MTLRenderPipelineState` built from a ``GPURenderPipelineDescriptor``.
public final class MetalRenderPipeline: GPURenderPipeline, @unchecked Sendable {
    /// The underlying Metal render pipeline state.
    public let pipelineState: MTLRenderPipelineState

    /// An optional debug label for this pipeline.
    public let label: String?

    /// Creates a render pipeline wrapping an existing Metal pipeline state.
    ///
    /// - Parameters:
    ///   - pipelineState: The compiled `MTLRenderPipelineState`.
    ///   - label: An optional debug label.
    public init(pipelineState: MTLRenderPipelineState, label: String? = nil) {
        self.pipelineState = pipelineState
        self.label = label
    }

    /// Creates a Metal render pipeline from a GamaCore render pipeline descriptor.
    ///
    /// This factory method translates the cross-platform descriptor into Metal-specific
    /// objects: vertex/fragment functions, vertex descriptor, color attachment blending,
    /// and depth format.
    ///
    /// - Parameters:
    ///   - descriptor: The cross-platform render pipeline descriptor.
    ///   - device: The Metal device to compile the pipeline on.
    /// - Throws: ``GPUError/pipelineCreationFailed(_:)`` if compilation fails.
    public static func make(
        descriptor: GPURenderPipelineDescriptor,
        device: MTLDevice
    ) throws -> MetalRenderPipeline {
        let mtlDesc = MTLRenderPipelineDescriptor()
        mtlDesc.label = descriptor.label ?? "GamaPipeline"

        // --- Vertex function ---
        let vertexModule = descriptor.vertexFunction.module
        guard let metalVertexModule = vertexModule as? MetalShaderModule else {
            throw GPUError.pipelineCreationFailed(
                "Vertex shader module must be a MetalShaderModule"
            )
        }
        guard let vertexFunction = metalVertexModule.makeFunction(
            name: descriptor.vertexFunction.entryPoint
        ) else {
            throw GPUError.pipelineCreationFailed(
                "Vertex entry point '\(descriptor.vertexFunction.entryPoint)' not found"
            )
        }
        mtlDesc.vertexFunction = vertexFunction

        // --- Fragment function (optional) ---
        if let fragFunc = descriptor.fragmentFunction {
            guard let metalFragModule = fragFunc.module as? MetalShaderModule else {
                throw GPUError.pipelineCreationFailed(
                    "Fragment shader module must be a MetalShaderModule"
                )
            }
            guard let fragmentFunction = metalFragModule.makeFunction(
                name: fragFunc.entryPoint
            ) else {
                throw GPUError.pipelineCreationFailed(
                    "Fragment entry point '\(fragFunc.entryPoint)' not found"
                )
            }
            mtlDesc.fragmentFunction = fragmentFunction
        }

        // --- Vertex descriptor (from vertex buffer layouts) ---
        if !descriptor.vertexBufferLayouts.isEmpty {
            let vertexDesc = MTLVertexDescriptor()
            var attributeIndex = 0
            for (bufferIndex, layout) in descriptor.vertexBufferLayouts.enumerated() {
                vertexDesc.layouts[bufferIndex].stride = layout.stride
                vertexDesc.layouts[bufferIndex].stepFunction = layout.stepFunction.mtlVertexStepFunction
                vertexDesc.layouts[bufferIndex].stepRate = 1

                for attribute in layout.attributes {
                    vertexDesc.attributes[attributeIndex].format = attribute.format.mtlVertexFormat
                    vertexDesc.attributes[attributeIndex].offset = attribute.offset
                    vertexDesc.attributes[attributeIndex].bufferIndex = bufferIndex
                    attributeIndex += 1
                }
            }
            mtlDesc.vertexDescriptor = vertexDesc
        }

        // --- Color target states ---
        for (index, target) in descriptor.colorTargets.enumerated() {
            let attachment = mtlDesc.colorAttachments[index]!
            attachment.pixelFormat = target.format.mtlPixelFormat
            attachment.isBlendingEnabled = target.blendEnabled
            attachment.writeMask = target.writeMask.mtlColorWriteMask

            if target.blendEnabled {
                attachment.sourceRGBBlendFactor = target.sourceRGBBlendFactor.mtlBlendFactor
                attachment.destinationRGBBlendFactor = target.destinationRGBBlendFactor.mtlBlendFactor
                attachment.rgbBlendOperation = target.rgbBlendOperation.mtlBlendOperation
                attachment.sourceAlphaBlendFactor = target.sourceAlphaBlendFactor.mtlBlendFactor
                attachment.destinationAlphaBlendFactor = target.destinationAlphaBlendFactor.mtlBlendFactor
                attachment.alphaBlendOperation = target.alphaBlendOperation.mtlBlendOperation
            }
        }

        // --- Multisample state ---
        mtlDesc.rasterSampleCount = descriptor.sampleCount

        // --- Depth attachment format ---
        // depthStencilState takes precedence over the legacy depthStencilFormat field.
        if let dsState = descriptor.depthStencilState {
            mtlDesc.depthAttachmentPixelFormat = dsState.format.mtlPixelFormat
        } else if let depthFormat = descriptor.depthStencilFormat {
            mtlDesc.depthAttachmentPixelFormat = depthFormat.mtlPixelFormat
        }

        // --- Compile ---
        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: mtlDesc)
            return MetalRenderPipeline(pipelineState: pipelineState, label: descriptor.label)
        } catch {
            throw GPUError.pipelineCreationFailed(error.localizedDescription)
        }
    }
}

// MARK: - Conversion Helpers for Render Pipeline Types

extension VertexFormat {
    /// Convert a GamaCore `VertexFormat` to its Metal equivalent.
    var mtlVertexFormat: MTLVertexFormat {
        switch self {
        case .float:            return .float
        case .float2:           return .float2
        case .float3:           return .float3
        case .float4:           return .float4
        case .int:              return .int
        case .int2:             return .int2
        case .int3:             return .int3
        case .int4:             return .int4
        case .uchar4Normalized: return .uchar4Normalized
        }
    }
}

extension VertexStepFunction {
    /// Convert a GamaCore `VertexStepFunction` to its Metal equivalent.
    var mtlVertexStepFunction: MTLVertexStepFunction {
        switch self {
        case .perVertex:   return .perVertex
        case .perInstance: return .perInstance
        }
    }
}

extension BlendFactor {
    /// Convert a GamaCore `BlendFactor` to its Metal equivalent.
    var mtlBlendFactor: MTLBlendFactor {
        switch self {
        case .zero:                     return .zero
        case .one:                      return .one
        case .sourceAlpha:              return .sourceAlpha
        case .oneMinusSourceAlpha:      return .oneMinusSourceAlpha
        case .destinationAlpha:         return .destinationAlpha
        case .oneMinusDestinationAlpha: return .oneMinusDestinationAlpha
        }
    }
}

extension BlendOperation {
    /// Convert a GamaCore `BlendOperation` to its Metal equivalent.
    var mtlBlendOperation: MTLBlendOperation {
        switch self {
        case .add:             return .add
        case .subtract:        return .subtract
        case .reverseSubtract: return .reverseSubtract
        case .min:             return .min
        case .max:             return .max
        }
    }
}

#endif
