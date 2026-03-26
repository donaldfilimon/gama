// MetalCommandEncoder.swift — Metal render and compute command encoder wrappers
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

// MARK: - MetalRenderCommandEncoder

/// A Metal render command encoder conforming to ``GPURenderCommandEncoder``.
///
/// Wraps an `MTLRenderCommandEncoder` and translates cross-platform draw calls
/// and state changes into Metal-specific API calls.
public final class MetalRenderCommandEncoder: GPURenderCommandEncoder, @unchecked Sendable {
    /// The underlying Metal render command encoder.
    public let mtlEncoder: MTLRenderCommandEncoder

    /// Creates a render command encoder wrapping the given Metal encoder.
    ///
    /// - Parameter encoder: The `MTLRenderCommandEncoder` to wrap.
    public init(encoder: MTLRenderCommandEncoder) {
        self.mtlEncoder = encoder
    }

    // MARK: Pipeline State

    /// Sets the render pipeline state for subsequent draw calls.
    public func setRenderPipeline(_ pipeline: any GPURenderPipeline) {
        guard let metalPipeline = pipeline as? MetalRenderPipeline else { return }
        mtlEncoder.setRenderPipelineState(metalPipeline.pipelineState)
    }

    // MARK: Vertex Buffers

    /// Binds a buffer to a vertex shader slot.
    public func setVertexBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        guard let metalBuffer = buffer as? MetalBuffer else { return }
        mtlEncoder.setVertexBuffer(metalBuffer.mtlBuffer, offset: offset, index: index)
    }

    // MARK: Fragment Buffers

    /// Binds a buffer to a fragment shader slot.
    public func setFragmentBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        guard let metalBuffer = buffer as? MetalBuffer else { return }
        mtlEncoder.setFragmentBuffer(metalBuffer.mtlBuffer, offset: offset, index: index)
    }

    // MARK: Bind Groups

    /// Binds a bind group at the given index.
    ///
    /// Metal does not have a native bind group concept. This method applies the
    /// individual resource bindings from the ``MetalBindGroup`` to the appropriate
    /// encoder slots, using the bind group index as a base buffer/texture index offset.
    public func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int) {
        guard let metalBindGroup = bindGroup as? MetalBindGroup else { return }
        for entry in metalBindGroup.entries {
            switch entry {
            case .buffer(let binding, let buffer, let offset, _):
                if let metalBuffer = buffer as? MetalBuffer {
                    mtlEncoder.setVertexBuffer(metalBuffer.mtlBuffer, offset: offset, index: Int(binding))
                    mtlEncoder.setFragmentBuffer(metalBuffer.mtlBuffer, offset: offset, index: Int(binding))
                }
            case .texture(let binding, let texture):
                if let metalTexture = texture as? MetalTexture {
                    mtlEncoder.setVertexTexture(metalTexture.mtlTexture, index: Int(binding))
                    mtlEncoder.setFragmentTexture(metalTexture.mtlTexture, index: Int(binding))
                }
            case .sampler(let binding, let sampler):
                if let metalSampler = sampler as? MetalSampler {
                    mtlEncoder.setVertexSamplerState(metalSampler.mtlSamplerState, index: Int(binding))
                    mtlEncoder.setFragmentSamplerState(metalSampler.mtlSamplerState, index: Int(binding))
                }
            }
        }
    }

    // MARK: Viewport & Scissor

    /// Sets the viewport for the rasterizer.
    public func setViewport(
        x: Float, y: Float,
        width: Float, height: Float,
        minDepth: Float, maxDepth: Float
    ) {
        let viewport = MTLViewport(
            originX: Double(x),
            originY: Double(y),
            width: Double(width),
            height: Double(height),
            znear: Double(minDepth),
            zfar: Double(maxDepth)
        )
        mtlEncoder.setViewport(viewport)
    }

    /// Sets the scissor rectangle for clipping.
    public func setScissorRect(x: Int, y: Int, width: Int, height: Int) {
        let rect = MTLScissorRect(x: x, y: y, width: width, height: height)
        mtlEncoder.setScissorRect(rect)
    }

    /// Sets the depth-stencil state.
    public func setDepthStencilState(_ state: any GPUDepthStencilStateObject) {
        guard let metalState = state as? MetalDepthStencilState else { return }
        mtlEncoder.setDepthStencilState(metalState.mtlDepthStencilState)
    }

    // MARK: Draw Calls

    /// Draws non-indexed primitives.
    public func draw(
        vertexCount: Int,
        instanceCount: Int,
        firstVertex: Int,
        firstInstance: Int
    ) {
        mtlEncoder.drawPrimitives(
            type: .triangle,
            vertexStart: firstVertex,
            vertexCount: vertexCount,
            instanceCount: instanceCount,
            baseInstance: firstInstance
        )
    }

    /// Draws indexed primitives.
    public func drawIndexed(
        indexCount: Int,
        indexBuffer: any GPUBuffer,
        indexFormat: IndexFormat,
        instanceCount: Int,
        firstIndex: Int,
        baseVertex: Int,
        firstInstance: Int
    ) {
        guard let metalBuffer = indexBuffer as? MetalBuffer else { return }

        let mtlIndexType: MTLIndexType
        let indexStride: Int
        switch indexFormat {
        case .uint16:
            mtlIndexType = .uint16
            indexStride = 2
        case .uint32:
            mtlIndexType = .uint32
            indexStride = 4
        }

        mtlEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: mtlIndexType,
            indexBuffer: metalBuffer.mtlBuffer,
            indexBufferOffset: firstIndex * indexStride,
            instanceCount: instanceCount,
            baseVertex: baseVertex,
            baseInstance: firstInstance
        )
    }

    // MARK: End Encoding

    /// Finalizes encoding and invalidates this encoder.
    public func endEncoding() {
        mtlEncoder.endEncoding()
    }
}

// MARK: - MetalComputeCommandEncoder

/// A Metal compute command encoder conforming to ``GPUComputeCommandEncoder``.
///
/// Wraps an `MTLComputeCommandEncoder` and translates cross-platform dispatch
/// calls into Metal-specific API calls.
public final class MetalComputeCommandEncoder: GPUComputeCommandEncoder, @unchecked Sendable {
    /// The underlying Metal compute command encoder.
    public let mtlEncoder: MTLComputeCommandEncoder

    /// Creates a compute command encoder wrapping the given Metal encoder.
    ///
    /// - Parameter encoder: The `MTLComputeCommandEncoder` to wrap.
    public init(encoder: MTLComputeCommandEncoder) {
        self.mtlEncoder = encoder
    }

    // MARK: Pipeline State

    /// Sets the compute pipeline state for subsequent dispatches.
    public func setComputePipeline(_ pipeline: any GPUComputePipeline) {
        guard let metalPipeline = pipeline as? MetalComputePipeline else { return }
        mtlEncoder.setComputePipelineState(metalPipeline.pipelineState)
    }

    // MARK: Buffers

    /// Binds a buffer to a compute shader slot.
    public func setBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        guard let metalBuffer = buffer as? MetalBuffer else { return }
        mtlEncoder.setBuffer(metalBuffer.mtlBuffer, offset: offset, index: index)
    }

    // MARK: Bind Groups

    /// Binds a bind group at the given index.
    ///
    /// Metal does not have a native bind group concept. This method applies the
    /// individual resource bindings from the ``MetalBindGroup`` to the compute encoder.
    public func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int) {
        guard let metalBindGroup = bindGroup as? MetalBindGroup else { return }
        for entry in metalBindGroup.entries {
            switch entry {
            case .buffer(let binding, let buffer, let offset, _):
                if let metalBuffer = buffer as? MetalBuffer {
                    mtlEncoder.setBuffer(metalBuffer.mtlBuffer, offset: offset, index: Int(binding))
                }
            case .texture(let binding, let texture):
                if let metalTexture = texture as? MetalTexture {
                    mtlEncoder.setTexture(metalTexture.mtlTexture, index: Int(binding))
                }
            case .sampler(let binding, let sampler):
                if let metalSampler = sampler as? MetalSampler {
                    mtlEncoder.setSamplerState(metalSampler.mtlSamplerState, index: Int(binding))
                }
            }
        }
    }

    // MARK: Dispatch

    /// Dispatches compute work with the given threadgroup configuration.
    ///
    /// Maps ``Extent3D`` values to `MTLSize` for the Metal dispatch call.
    public func dispatch(threadgroups: Extent3D, threadsPerThreadgroup: Extent3D) {
        let gridSize = MTLSize(
            width: Int(threadgroups.width),
            height: Int(threadgroups.height),
            depth: Int(threadgroups.depth)
        )
        let threadgroupSize = MTLSize(
            width: Int(threadsPerThreadgroup.width),
            height: Int(threadsPerThreadgroup.height),
            depth: Int(threadsPerThreadgroup.depth)
        )
        mtlEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
    }

    // MARK: End Encoding

    /// Finalizes encoding and invalidates this encoder.
    public func endEncoding() {
        mtlEncoder.endEncoding()
    }
}

#endif
