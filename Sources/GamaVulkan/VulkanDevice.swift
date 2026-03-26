// VulkanDevice.swift — Stub adapter and device for Vulkan
// Part of GamaVulkan

import GamaCore

// MARK: - Adapter

/// A stub Vulkan adapter. All methods throw or fatalError.
public final class VulkanAdapter: GPUAdapter, @unchecked Sendable {
    public var info: GPUAdapterInfo {
        fatalError("Vulkan backend not yet implemented")
    }

    public func requestDevice() throws -> any GPUDevice {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Device

/// A stub Vulkan logical device. All factory methods fatalError.
public final class VulkanDevice: GPUDevice, @unchecked Sendable {
    public var adapter: GPUAdapterInfo {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createQueue() throws -> any GPUQueue {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createBuffer(size: Int, usage: BufferUsage) throws -> any GPUBuffer {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createTexture(descriptor: GPUTextureDescriptor) throws -> any GPUTexture {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createSampler(descriptor: GPUSamplerDescriptor) throws -> any GPUSampler {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createShaderModule(source: String) throws -> any GPUShaderModule {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createRenderPipeline(descriptor: GPURenderPipelineDescriptor) throws -> any GPURenderPipeline {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createComputePipeline(descriptor: GPUComputePipelineDescriptor) throws -> any GPUComputePipeline {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createBindGroupLayout(entries: [GPUBindGroupLayoutEntry], label: String?) throws -> any GPUBindGroupLayout {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createBindGroup(layout: any GPUBindGroupLayout, entries: [GPUBindGroupEntry]) throws -> any GPUBindGroup {
        fatalError("Vulkan backend not yet implemented")
    }

    public func createDepthStencilState(descriptor: GPUDepthStencilDescriptor) throws -> any GPUDepthStencilStateObject {
        fatalError("Vulkan backend not yet implemented")
    }
}
