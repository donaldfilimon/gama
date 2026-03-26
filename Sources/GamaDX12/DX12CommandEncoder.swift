// DX12CommandEncoder.swift — Stub command types for DirectX 12
// Part of GamaDX12

import GamaCore

// MARK: - Queue

/// A DirectX 12 command queue (stub).
public final class DX12Queue: GPUQueue, @unchecked Sendable {
    public func createCommandBuffer() throws -> any GPUCommandBuffer {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func submit(_ commandBuffer: any GPUCommandBuffer) throws {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func waitUntilCompleted() async throws {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Command Buffer

/// A DirectX 12 command buffer (stub).
public final class DX12CommandBuffer: GPUCommandBuffer, @unchecked Sendable {
    public var label: String? {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func makeRenderCommandEncoder(descriptor: GPURenderPassDescriptor) throws -> any GPURenderCommandEncoder {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func makeComputeCommandEncoder() throws -> any GPUComputeCommandEncoder {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func commit() {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func waitUntilCompleted() async throws {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Render Command Encoder

/// A DirectX 12 render command encoder (stub).
public final class DX12RenderCommandEncoder: GPURenderCommandEncoder, @unchecked Sendable {
    public func setRenderPipeline(_ pipeline: any GPURenderPipeline) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func setVertexBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func setFragmentBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func setViewport(
        x: Float, y: Float,
        width: Float, height: Float,
        minDepth: Float, maxDepth: Float
    ) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func setScissorRect(x: Int, y: Int, width: Int, height: Int) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func draw(
        vertexCount: Int,
        instanceCount: Int,
        firstVertex: Int,
        firstInstance: Int
    ) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func drawIndexed(
        indexCount: Int,
        indexBuffer: any GPUBuffer,
        indexFormat: IndexFormat,
        instanceCount: Int,
        firstIndex: Int,
        baseVertex: Int,
        firstInstance: Int
    ) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func endEncoding() {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Compute Command Encoder

/// A DirectX 12 compute command encoder (stub).
public final class DX12ComputeCommandEncoder: GPUComputeCommandEncoder, @unchecked Sendable {
    public func setComputePipeline(_ pipeline: any GPUComputePipeline) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func setBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func dispatch(threadgroups: Extent3D, threadsPerThreadgroup: Extent3D) {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func endEncoding() {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Bind Group Layout

/// A DirectX 12 bind group layout (stub).
public final class DX12BindGroupLayout: GPUBindGroupLayout, @unchecked Sendable {
    public var entries: [GPUBindGroupLayoutEntry] {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Bind Group

/// A DirectX 12 bind group (stub).
public final class DX12BindGroup: GPUBindGroup, @unchecked Sendable {
    public var layout: any GPUBindGroupLayout {
        fatalError("DirectX 12 backend not yet implemented")
    }
}
