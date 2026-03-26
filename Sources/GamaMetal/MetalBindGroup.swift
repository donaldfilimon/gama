// MetalBindGroup.swift — Metal bind group and bind group layout wrappers
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

// MARK: - MetalBindGroupLayout

/// A bind group layout conforming to ``GPUBindGroupLayout``.
///
/// Metal does not have a direct equivalent of bind group layouts. This type
/// stores the layout entries as a logical description so that ``MetalBindGroup``
/// instances can validate bindings against the expected layout at creation time.
public final class MetalBindGroupLayout: GPUBindGroupLayout, @unchecked Sendable {
    /// The entries that define each binding slot in this layout.
    public let entries: [GPUBindGroupLayoutEntry]

    /// An optional debug label for this layout.
    public let label: String?

    /// Creates a bind group layout with the given entries.
    ///
    /// - Parameters:
    ///   - entries: The binding slot descriptions.
    ///   - label: An optional debug label.
    public init(entries: [GPUBindGroupLayoutEntry], label: String? = nil) {
        self.entries = entries
        self.label = label
    }
}

// MARK: - MetalBindGroup

/// A set of bound resources conforming to ``GPUBindGroup``.
///
/// Metal does not have a native bind group (descriptor set) concept. This type
/// is a logical grouping of resources that gets applied to a command encoder
/// by iterating over the entries and binding each resource individually.
///
/// When ``MetalRenderCommandEncoder/setBindGroup(_:index:)`` or
/// ``MetalComputeCommandEncoder/setBindGroup(_:index:)`` is called, the
/// encoder walks ``entries`` and binds each buffer, texture, or sampler
/// to the corresponding Metal shader argument slot.
public final class MetalBindGroup: GPUBindGroup, @unchecked Sendable {
    /// The layout that this bind group conforms to.
    public let layout: any GPUBindGroupLayout

    /// The concrete resource bindings in this bind group.
    public let entries: [GPUBindGroupEntry]

    /// Creates a bind group with the given layout and resource entries.
    ///
    /// - Parameters:
    ///   - layout: The bind group layout this group conforms to.
    ///   - entries: The resource bindings.
    public init(layout: any GPUBindGroupLayout, entries: [GPUBindGroupEntry]) {
        self.layout = layout
        self.entries = entries
    }
}

#endif
