// Device.swift — Device and Adapter protocols for GamaCore
// Part of GamaCore

// MARK: - Adapter

/// Information about a GPU adapter (physical device).
public struct GPUAdapterInfo: Sendable {
    /// Human-readable name of the adapter.
    public var name: String
    /// Vendor name or identifier.
    public var vendor: String
    /// Whether this adapter is a discrete (dedicated) GPU.
    public var isDiscrete: Bool
    /// Maximum buffer allocation size in bytes.
    public var maxBufferSize: UInt64
    /// Maximum texture dimension (width or height).
    public var maxTextureSize: UInt32

    /// Creates adapter information.
    public init(
        name: String,
        vendor: String,
        isDiscrete: Bool,
        maxBufferSize: UInt64,
        maxTextureSize: UInt32
    ) {
        self.name = name
        self.vendor = vendor
        self.isDiscrete = isDiscrete
        self.maxBufferSize = maxBufferSize
        self.maxTextureSize = maxTextureSize
    }
}

/// A GPU adapter representing a physical GPU that can create devices.
public protocol GPUAdapter: Sendable {
    /// Information about this adapter.
    var info: GPUAdapterInfo { get }

    /// Request a logical device from this adapter.
    func requestDevice() throws -> any GPUDevice
}

// MARK: - Device

/// A logical GPU device that creates resources and queues.
public protocol GPUDevice: AnyObject, Sendable {
    /// Information about the adapter that created this device.
    var adapter: GPUAdapterInfo { get }

    /// Create a command queue.
    func createQueue() throws -> any GPUQueue

    /// Create a buffer of the given size and usage.
    func createBuffer(size: Int, usage: BufferUsage) throws -> any GPUBuffer

    /// Create a texture from a descriptor.
    func createTexture(descriptor: GPUTextureDescriptor) throws -> any GPUTexture

    /// Create a sampler from a descriptor.
    func createSampler(descriptor: GPUSamplerDescriptor) throws -> any GPUSampler

    /// Create a shader module from source code.
    func createShaderModule(source: String) throws -> any GPUShaderModule

    /// Create a render pipeline from a descriptor.
    func createRenderPipeline(descriptor: GPURenderPipelineDescriptor) throws -> any GPURenderPipeline

    /// Create a compute pipeline from a descriptor.
    func createComputePipeline(descriptor: GPUComputePipelineDescriptor) throws -> any GPUComputePipeline

    /// Create a bind group layout from entries.
    func createBindGroupLayout(entries: [GPUBindGroupLayoutEntry], label: String?) throws -> any GPUBindGroupLayout

    /// Create a bind group from a layout and entries.
    func createBindGroup(layout: any GPUBindGroupLayout, entries: [GPUBindGroupEntry]) throws -> any GPUBindGroup

    /// Create a compiled depth-stencil state object from a descriptor.
    func createDepthStencilState(descriptor: GPUDepthStencilDescriptor) throws -> any GPUDepthStencilStateObject
}

// MARK: - Default Parameter Values

extension GPUDevice {
    /// Create a bind group layout from entries with no label.
    public func createBindGroupLayout(entries: [GPUBindGroupLayoutEntry], label: String? = nil) throws -> any GPUBindGroupLayout {
        try createBindGroupLayout(entries: entries, label: label)
    }
}
