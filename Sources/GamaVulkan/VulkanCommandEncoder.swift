// VulkanCommandEncoder.swift — Stub command types for Vulkan
// Part of GamaVulkan

import GamaCore

// MARK: - Queue

/// A stub Vulkan command queue. All methods fatalError.
public final class VulkanQueue: GPUQueue, @unchecked Sendable {
    public func createCommandBuffer() throws -> any GPUCommandBuffer {
        fatalError("Vulkan backend not yet implemented")
    }

    public func submit(_ commandBuffer: any GPUCommandBuffer) throws {
        fatalError("Vulkan backend not yet implemented")
    }

    public func waitUntilCompleted() async throws {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Command Buffer

/// A stub Vulkan command buffer. All methods and properties fatalError.
public final class VulkanCommandBuffer: GPUCommandBuffer, @unchecked Sendable {
    public var label: String? {
        fatalError("Vulkan backend not yet implemented")
    }

    public func makeRenderCommandEncoder(descriptor: GPURenderPassDescriptor) throws -> any GPURenderCommandEncoder {
        fatalError("Vulkan backend not yet implemented")
    }

    public func makeComputeCommandEncoder() throws -> any GPUComputeCommandEncoder {
        fatalError("Vulkan backend not yet implemented")
    }

    public func commit() {
        fatalError("Vulkan backend not yet implemented")
    }

    public func waitUntilCompleted() async throws {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Render Command Encoder

/// A stub Vulkan render command encoder. All methods fatalError.
public final class VulkanRenderCommandEncoder: GPURenderCommandEncoder, @unchecked Sendable {
    public func setRenderPipeline(_ pipeline: any GPURenderPipeline) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func setVertexBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func setFragmentBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func setViewport(
        x: Float, y: Float,
        width: Float, height: Float,
        minDepth: Float, maxDepth: Float
    ) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func setScissorRect(x: Int, y: Int, width: Int, height: Int) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func draw(
        vertexCount: Int,
        instanceCount: Int,
        firstVertex: Int,
        firstInstance: Int
    ) {
        fatalError("Vulkan backend not yet implemented")
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
        fatalError("Vulkan backend not yet implemented")
    }

    public func endEncoding() {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Compute Command Encoder

/// A stub Vulkan compute command encoder. All methods fatalError.
public final class VulkanComputeCommandEncoder: GPUComputeCommandEncoder, @unchecked Sendable {
    public func setComputePipeline(_ pipeline: any GPUComputePipeline) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func setBuffer(_ buffer: any GPUBuffer, offset: Int, index: Int) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func setBindGroup(_ bindGroup: any GPUBindGroup, index: Int) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func dispatch(threadgroups: Extent3D, threadsPerThreadgroup: Extent3D) {
        fatalError("Vulkan backend not yet implemented")
    }

    public func endEncoding() {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Bind Group Layout

/// A stub Vulkan bind group layout. All properties fatalError.
public final class VulkanBindGroupLayout: GPUBindGroupLayout, @unchecked Sendable {
    public var entries: [GPUBindGroupLayoutEntry] {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Bind Group

/// A stub Vulkan bind group. All properties fatalError.
public final class VulkanBindGroup: GPUBindGroup, @unchecked Sendable {
    public var layout: any GPUBindGroupLayout {
        fatalError("Vulkan backend not yet implemented")
    }
}
