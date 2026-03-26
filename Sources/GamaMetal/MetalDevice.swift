// MetalDevice.swift — Metal adapter and device wrappers
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

// MARK: - MetalAdapter

/// A Metal adapter representing a physical GPU. Wraps an `MTLDevice`.
public final class MetalAdapter: GPUAdapter, @unchecked Sendable {
    /// The underlying Metal device.
    public let mtlDevice: MTLDevice

    /// Adapter information derived from the Metal device.
    public let info: GPUAdapterInfo

    /// Creates a Metal adapter wrapping the given Metal device.
    /// - Parameter device: The `MTLDevice` to wrap.
    public init(device: MTLDevice) {
        self.mtlDevice = device
        self.info = GPUAdapterInfo(
            name: device.name,
            vendor: "Apple",
            isDiscrete: !device.hasUnifiedMemory,
            maxBufferSize: UInt64(device.maxBufferLength),
            maxTextureSize: 16384 // Conservative default; actual limits depend on GPU family
        )
    }

    /// Request a logical device from this adapter.
    ///
    /// Metal devices are already logical devices, so this simply wraps
    /// the underlying `MTLDevice` in a `MetalDevice`.
    public func requestDevice() throws -> any GPUDevice {
        return MetalDevice(device: mtlDevice)
    }
}

// MARK: - MetalDevice

/// A logical Metal GPU device that creates resources and command queues.
///
/// Wraps an `MTLDevice`. Metal devices are internally thread-safe,
/// so this type is marked `@unchecked Sendable`.
public final class MetalDevice: GPUDevice, @unchecked Sendable {
    /// The underlying Metal device.
    public let mtlDevice: MTLDevice

    /// Information about the adapter that backs this device.
    public let adapter: GPUAdapterInfo

    /// Creates a Metal device wrapping the given `MTLDevice`.
    /// - Parameter device: The `MTLDevice` to wrap.
    public init(device: MTLDevice) {
        self.mtlDevice = device
        self.adapter = GPUAdapterInfo(
            name: device.name,
            vendor: "Apple",
            isDiscrete: !device.hasUnifiedMemory,
            maxBufferSize: UInt64(device.maxBufferLength),
            maxTextureSize: 16384
        )
    }

    // MARK: - Queue

    /// Create a Metal command queue.
    public func createQueue() throws -> any GPUQueue {
        guard let queue = mtlDevice.makeCommandQueue() else {
            throw GPUError.queueSubmissionFailed
        }
        return MetalQueue(queue: queue)
    }

    // MARK: - Buffer

    /// Create a Metal buffer with the given size and usage.
    public func createBuffer(size: Int, usage: BufferUsage) throws -> any GPUBuffer {
        guard let buffer = mtlDevice.makeBuffer(
            length: size,
            options: usage.mtlResourceOptions
        ) else {
            throw GPUError.bufferAllocationFailed(size: size)
        }
        return MetalBuffer(buffer: buffer, size: size, usage: usage)
    }

    // MARK: - Texture

    /// Create a Metal texture from a descriptor.
    public func createTexture(descriptor: GPUTextureDescriptor) throws -> any GPUTexture {
        let mtlDesc = MTLTextureDescriptor()
        mtlDesc.textureType = descriptor.dimension.mtlTextureType
        mtlDesc.pixelFormat = descriptor.format.mtlPixelFormat
        mtlDesc.width = Int(descriptor.width)
        mtlDesc.height = Int(descriptor.height)
        mtlDesc.depth = Int(descriptor.depth)
        mtlDesc.mipmapLevelCount = Int(descriptor.mipLevelCount)
        mtlDesc.sampleCount = Int(descriptor.sampleCount)
        mtlDesc.usage = descriptor.usage.mtlTextureUsage

        guard let texture = mtlDevice.makeTexture(descriptor: mtlDesc) else {
            throw GPUError.textureCreationFailed
        }
        return MetalTexture(texture: texture, descriptor: descriptor)
    }

    // MARK: - Sampler

    /// Create a Metal sampler from a descriptor.
    public func createSampler(descriptor: GPUSamplerDescriptor) throws -> any GPUSampler {
        let mtlDesc = MTLSamplerDescriptor()
        mtlDesc.minFilter = descriptor.minFilter.mtlSamplerMinMagFilter
        mtlDesc.magFilter = descriptor.magFilter.mtlSamplerMinMagFilter
        mtlDesc.mipFilter = descriptor.mipFilter.mtlSamplerMipFilter
        mtlDesc.sAddressMode = descriptor.addressModeU.mtlSamplerAddressMode
        mtlDesc.tAddressMode = descriptor.addressModeV.mtlSamplerAddressMode
        mtlDesc.rAddressMode = descriptor.addressModeW.mtlSamplerAddressMode
        mtlDesc.maxAnisotropy = Int(descriptor.maxAnisotropy)
        if let compare = descriptor.compareFunction {
            mtlDesc.compareFunction = compare.mtlCompareFunction
        }
        mtlDesc.label = descriptor.label

        guard let sampler = mtlDevice.makeSamplerState(descriptor: mtlDesc) else {
            throw GPUError.unsupportedOperation("Failed to create sampler state")
        }
        return MetalSampler(samplerState: sampler, label: descriptor.label)
    }

    // MARK: - Shader Module

    /// Create a Metal shader module from MSL source code.
    ///
    /// Compiles the given Metal Shading Language source into a library.
    public func createShaderModule(source: String) throws -> any GPUShaderModule {
        return try MetalShaderModule(source: source, device: mtlDevice)
    }

    // MARK: - Render Pipeline

    /// Create a Metal render pipeline from a descriptor.
    public func createRenderPipeline(descriptor: GPURenderPipelineDescriptor) throws -> any GPURenderPipeline {
        return try MetalRenderPipeline.make(descriptor: descriptor, device: mtlDevice)
    }

    // MARK: - Compute Pipeline

    /// Create a Metal compute pipeline from a descriptor.
    public func createComputePipeline(descriptor: GPUComputePipelineDescriptor) throws -> any GPUComputePipeline {
        return try MetalComputePipeline.make(descriptor: descriptor, device: mtlDevice)
    }

    // MARK: - Bind Groups

    /// Create a Metal bind group layout from entries.
    public func createBindGroupLayout(entries: [GPUBindGroupLayoutEntry], label: String?) throws -> any GPUBindGroupLayout {
        return MetalBindGroupLayout(entries: entries, label: label)
    }

    /// Create a Metal bind group from a layout and entries.
    public func createBindGroup(layout: any GPUBindGroupLayout, entries: [GPUBindGroupEntry]) throws -> any GPUBindGroup {
        return MetalBindGroup(layout: layout, entries: entries)
    }

    // MARK: - Depth-Stencil State

    /// Create a compiled Metal depth-stencil state from a descriptor.
    public func createDepthStencilState(descriptor: GPUDepthStencilDescriptor) throws -> any GPUDepthStencilStateObject {
        return try MetalDepthStencilState.make(descriptor: descriptor, device: mtlDevice)
    }
}

#endif
