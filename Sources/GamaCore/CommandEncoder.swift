// CommandEncoder.swift — Render and compute command encoder protocols for GamaCore
// Part of GamaCore

// MARK: - Render Command Encoder

/// Encodes rendering commands into a command buffer.
///
/// A render command encoder is created from a ``GPUCommandBuffer`` with a
/// ``GPURenderPassDescriptor`` that specifies the render targets. Record draw
/// calls and state changes, then call ``endEncoding()`` to finalize.
///
/// Concrete implementations are provided by backend modules (e.g., GamaMetal).
///
/// - Note: ``GPURenderPipeline``, ``GPUBuffer``, ``GPUBindGroup``, and
///   ``IndexFormat`` are defined in other GamaCore source files.
public protocol GPURenderCommandEncoder: AnyObject, Sendable {
    /// Sets the render pipeline state for subsequent draw calls.
    ///
    /// - Parameter pipeline: The render pipeline to bind.
    func setRenderPipeline(_ pipeline: any GPURenderPipeline)

    /// Binds a buffer to a vertex shader slot.
    ///
    /// - Parameters:
    ///   - buffer: The buffer to bind.
    ///   - offset: The byte offset into the buffer.
    ///   - index: The binding slot index.
    func setVertexBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int)

    /// Binds a buffer to a fragment shader slot.
    ///
    /// - Parameters:
    ///   - buffer: The buffer to bind.
    ///   - offset: The byte offset into the buffer.
    ///   - index: The binding slot index.
    func setFragmentBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int)

    /// Binds a bind group (descriptor set) at the given index.
    ///
    /// - Parameters:
    ///   - bindGroup: The bind group to bind.
    ///   - index: The bind group slot index.
    func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int)

    /// Sets the viewport for the rasterizer.
    ///
    /// - Parameters:
    ///   - x: The x origin of the viewport in pixels.
    ///   - y: The y origin of the viewport in pixels.
    ///   - width: The width of the viewport in pixels.
    ///   - height: The height of the viewport in pixels.
    ///   - minDepth: The minimum depth value (default `0.0`).
    ///   - maxDepth: The maximum depth value (default `1.0`).
    func setViewport(
        x: Float, y: Float,
        width: Float, height: Float,
        minDepth: Float, maxDepth: Float
    )

    /// Sets the scissor rectangle for clipping.
    ///
    /// - Parameters:
    ///   - x: The x origin of the scissor rectangle in pixels.
    ///   - y: The y origin of the scissor rectangle in pixels.
    ///   - width: The width of the scissor rectangle in pixels.
    ///   - height: The height of the scissor rectangle in pixels.
    func setScissorRect(x: Int, y: Int, width: Int, height: Int)

    /// Sets the depth-stencil state for subsequent draw calls.
    ///
    /// - Parameter state: A compiled depth-stencil state object.
    func setDepthStencilState(_ state: any GPUDepthStencilStateObject)

    /// Draws non-indexed primitives.
    ///
    /// - Parameters:
    ///   - vertexCount: The number of vertices to draw.
    ///   - instanceCount: The number of instances to draw (default `1`).
    ///   - firstVertex: The index of the first vertex (default `0`).
    ///   - firstInstance: The index of the first instance (default `0`).
    func draw(
        vertexCount: Int,
        instanceCount: Int,
        firstVertex: Int,
        firstInstance: Int
    )

    /// Draws indexed primitives.
    ///
    /// - Parameters:
    ///   - indexCount: The number of indices to draw.
    ///   - indexBuffer: The buffer containing index data.
    ///   - indexFormat: The format of indices in the buffer.
    ///   - instanceCount: The number of instances to draw (default `1`).
    ///   - firstIndex: The offset into the index buffer (default `0`).
    ///   - baseVertex: The value added to each index before fetching (default `0`).
    ///   - firstInstance: The index of the first instance (default `0`).
    func drawIndexed(
        indexCount: Int,
        indexBuffer: any GPUBuffer,
        indexFormat: IndexFormat,
        instanceCount: Int,
        firstIndex: Int,
        baseVertex: Int,
        firstInstance: Int
    )

    /// Finalizes encoding and invalidates this encoder.
    ///
    /// No further calls may be made on this encoder after calling this method.
    func endEncoding()
}

// MARK: - Default Parameter Values

extension GPURenderCommandEncoder {
    /// Draws non-indexed primitives with default instance and offset values.
    public func draw(
        vertexCount: Int,
        instanceCount: Int = 1,
        firstVertex: Int = 0,
        firstInstance: Int = 0
    ) {
        draw(
            vertexCount: vertexCount,
            instanceCount: instanceCount,
            firstVertex: firstVertex,
            firstInstance: firstInstance
        )
    }

    /// Draws indexed primitives with default instance and offset values.
    public func drawIndexed(
        indexCount: Int,
        indexBuffer: any GPUBuffer,
        indexFormat: IndexFormat,
        instanceCount: Int = 1,
        firstIndex: Int = 0,
        baseVertex: Int = 0,
        firstInstance: Int = 0
    ) {
        drawIndexed(
            indexCount: indexCount,
            indexBuffer: indexBuffer,
            indexFormat: indexFormat,
            instanceCount: instanceCount,
            firstIndex: firstIndex,
            baseVertex: baseVertex,
            firstInstance: firstInstance
        )
    }
}

// MARK: - Compute Command Encoder

/// Encodes compute dispatch commands into a command buffer.
///
/// A compute command encoder is created from a ``GPUCommandBuffer`` via
/// ``GPUCommandBuffer/makeComputeCommandEncoder()``. Bind a compute pipeline
/// and resources, dispatch threadgroups, then call ``endEncoding()``.
///
/// Concrete implementations are provided by backend modules (e.g., GamaMetal).
///
/// - Note: ``GPUComputePipeline``, ``GPUBuffer``, ``GPUBindGroup``, and
///   ``Extent3D`` are defined in other GamaCore source files.
public protocol GPUComputeCommandEncoder: AnyObject, Sendable {
    /// Sets the compute pipeline state for subsequent dispatches.
    ///
    /// - Parameter pipeline: The compute pipeline to bind.
    func setComputePipeline(_ pipeline: any GPUComputePipeline)

    /// Binds a buffer to a compute shader slot.
    ///
    /// - Parameters:
    ///   - buffer: The buffer to bind.
    ///   - offset: The byte offset into the buffer.
    ///   - index: The binding slot index.
    func setBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int)

    /// Binds a bind group (descriptor set) at the given index.
    ///
    /// - Parameters:
    ///   - bindGroup: The bind group to bind.
    ///   - index: The bind group slot index.
    func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int)

    /// Dispatches compute work.
    ///
    /// - Parameters:
    ///   - threadgroups: The number of threadgroups in each dimension.
    ///   - threadsPerThreadgroup: The number of threads per threadgroup in each dimension.
    func dispatch(threadgroups: Extent3D, threadsPerThreadgroup: Extent3D)

    /// Finalizes encoding and invalidates this encoder.
    ///
    /// No further calls may be made on this encoder after calling this method.
    func endEncoding()
}
