// ComputePipeline.swift — Compute pipeline protocol and descriptor
// Part of GamaCore

// MARK: - Compute Pipeline Descriptor

/// A description of a compute pipeline's configuration.
///
/// Use this to create a ``GPUComputePipeline`` from a ``GPUDevice``.
public struct GPUComputePipelineDescriptor: Sendable {
    /// The compute shader function to execute.
    public var computeFunction: GPUShaderFunction

    /// An optional debug label for the pipeline.
    public var label: String?

    /// Creates a compute pipeline descriptor.
    /// - Parameters:
    ///   - computeFunction: The compute shader function.
    ///   - label: An optional debug label.
    public init(computeFunction: GPUShaderFunction, label: String? = nil) {
        self.computeFunction = computeFunction
        self.label = label
    }
}

// MARK: - Compute Pipeline Protocol

/// A compiled compute pipeline state object.
///
/// Created from a ``GPUComputePipelineDescriptor`` via a ``GPUDevice``.
/// Backend modules provide concrete implementations.
public protocol GPUComputePipeline: AnyObject, Sendable {
    /// An optional debug label for the pipeline.
    var label: String? { get }
}
