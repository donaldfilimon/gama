// ShaderModule.swift — Shader module and function types for GamaCore
// Part of GamaCore

// MARK: - Shader Stage

/// A bitmask indicating which GPU pipeline stages a resource or entry point is visible to.
public struct ShaderStage: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// The vertex stage of the render pipeline.
    public static let vertex   = ShaderStage(rawValue: 1 << 0)

    /// The fragment stage of the render pipeline.
    public static let fragment = ShaderStage(rawValue: 1 << 1)

    /// The compute stage.
    public static let compute  = ShaderStage(rawValue: 1 << 2)
}

// MARK: - Shader Module Protocol

/// A compiled shader module containing one or more entry points.
///
/// Backend implementations wrap platform-specific shader libraries
/// (e.g., Metal libraries, SPIR-V modules) behind this protocol.
public protocol GPUShaderModule: AnyObject, Sendable {
    /// An optional debug label for the shader module.
    var label: String? { get }
}

// MARK: - Shader Function

/// A reference to a specific entry point within a shader module.
///
/// Combines a compiled ``GPUShaderModule`` with the name of the entry point
/// and the pipeline stage it targets.
public struct GPUShaderFunction: Sendable {
    /// The shader module containing the entry point.
    public var module: any GPUShaderModule

    /// The name of the entry point function within the module.
    public var entryPoint: String

    /// The pipeline stage this function targets.
    public var stage: ShaderStage

    /// Creates a shader function reference.
    /// - Parameters:
    ///   - module: The compiled shader module.
    ///   - entryPoint: The name of the entry point function.
    ///   - stage: The pipeline stage this function is used in.
    public init(module: any GPUShaderModule, entryPoint: String, stage: ShaderStage) {
        self.module = module
        self.entryPoint = entryPoint
        self.stage = stage
    }
}
