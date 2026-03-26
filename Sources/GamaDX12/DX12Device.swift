// DX12Device.swift — Stub device and adapter for DirectX 12
// Part of GamaDX12

import GamaCore

// MARK: - Adapter

/// A DirectX 12 GPU adapter (stub).
public final class DX12Adapter: GPUAdapter, @unchecked Sendable {
    public var info: GPUAdapterInfo {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func requestDevice() throws -> any GPUDevice {
        throw GPUError.backendNotAvailable("DirectX 12")
    }
}

// MARK: - Device

/// A DirectX 12 logical device (stub).
public final class DX12Device: GPUDevice, @unchecked Sendable {
    public var adapter: GPUAdapterInfo {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createQueue() throws -> any GPUQueue {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createBuffer(size: Int, usage: BufferUsage) throws -> any GPUBuffer {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createTexture(descriptor: GPUTextureDescriptor) throws -> any GPUTexture {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createSampler(descriptor: GPUSamplerDescriptor) throws -> any GPUSampler {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createShaderModule(source: String) throws -> any GPUShaderModule {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createRenderPipeline(descriptor: GPURenderPipelineDescriptor) throws -> any GPURenderPipeline {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createComputePipeline(descriptor: GPUComputePipelineDescriptor) throws -> any GPUComputePipeline {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createBindGroupLayout(entries: [GPUBindGroupLayoutEntry], label: String?) throws -> any GPUBindGroupLayout {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createBindGroup(layout: any GPUBindGroupLayout, entries: [GPUBindGroupEntry]) throws -> any GPUBindGroup {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func createDepthStencilState(descriptor: GPUDepthStencilDescriptor) throws -> any GPUDepthStencilStateObject {
        fatalError("DirectX 12 backend not yet implemented")
    }
}
