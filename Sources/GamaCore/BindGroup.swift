// BindGroup.swift — Bind group protocols and supporting types
// Part of GamaCore

// MARK: - Binding Type

/// The type of resource bound in a bind group entry.
public enum GPUBindingType: Sendable {
    /// A uniform (constant) buffer binding.
    case uniformBuffer
    /// A storage buffer binding (read/write from shaders).
    case storageBuffer
    /// A sampler binding.
    case sampler
    /// A sampled texture binding (read-only).
    case texture
    /// A storage texture binding (read/write from shaders).
    case storageTexture
}

// MARK: - Bind Group Layout Entry

/// Describes a single binding slot within a bind group layout.
public struct GPUBindGroupLayoutEntry: Sendable {
    /// The binding index in the shader.
    public var binding: UInt32

    /// The shader stages that can access this binding.
    public var visibility: ShaderStage

    /// The type of resource expected at this binding.
    public var type: GPUBindingType

    /// Creates a bind group layout entry.
    /// - Parameters:
    ///   - binding: The binding index.
    ///   - visibility: The shader stages with access.
    ///   - type: The resource type.
    public init(binding: UInt32, visibility: ShaderStage, type: GPUBindingType) {
        self.binding = binding
        self.visibility = visibility
        self.type = type
    }
}

// MARK: - Bind Group Layout Protocol

/// Defines the layout of a bind group, specifying the expected bindings.
///
/// Backend modules provide concrete implementations.
public protocol GPUBindGroupLayout: AnyObject, Sendable {
    /// The entries that define each binding slot in this layout.
    var entries: [GPUBindGroupLayoutEntry] { get }
}

// MARK: - Bind Group Entry

/// A concrete resource binding within a bind group.
///
/// Each case associates a binding index with a specific GPU resource.
public enum GPUBindGroupEntry: Sendable {
    /// A buffer binding.
    /// - Parameters:
    ///   - binding: The binding index.
    ///   - buffer: The GPU buffer to bind.
    ///   - offset: The byte offset into the buffer.
    ///   - size: The number of bytes to bind.
    case buffer(binding: UInt32, buffer: any GPUBuffer, offset: Int, size: Int)

    /// A sampler binding.
    /// - Parameters:
    ///   - binding: The binding index.
    ///   - sampler: The GPU sampler to bind.
    case sampler(binding: UInt32, sampler: any GPUSampler)

    /// A texture binding.
    /// - Parameters:
    ///   - binding: The binding index.
    ///   - texture: The GPU texture to bind.
    case texture(binding: UInt32, texture: any GPUTexture)
}

// MARK: - Bind Group Protocol

/// A set of resources bound together for use in a shader pipeline.
///
/// Created from a ``GPUBindGroupLayout`` and a list of ``GPUBindGroupEntry`` values
/// via a device. Backend modules provide concrete implementations.
public protocol GPUBindGroup: AnyObject, Sendable {
    /// The layout that this bind group conforms to.
    var layout: any GPUBindGroupLayout { get }
}
