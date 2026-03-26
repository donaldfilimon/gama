// MetalShaderModule.swift — Metal shader module wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// A compiled Metal shader library conforming to ``GPUShaderModule``.
///
/// Wraps an `MTLLibrary` produced by compiling Metal Shading Language source
/// at runtime via `MTLDevice.makeLibrary(source:options:)`.
public final class MetalShaderModule: GPUShaderModule, @unchecked Sendable {
    /// The underlying Metal library containing compiled shader functions.
    public let library: MTLLibrary

    /// An optional debug label for this shader module.
    public var label: String? { library.label }

    /// Creates a shader module wrapping the given Metal library.
    ///
    /// - Parameter library: A compiled `MTLLibrary`.
    public init(library: MTLLibrary) {
        self.library = library
    }

    /// Creates a shader module by compiling MSL source on the given device.
    ///
    /// - Parameters:
    ///   - source: Metal Shading Language source code.
    ///   - device: The Metal device used for compilation.
    ///   - label: An optional debug label applied to the resulting library.
    /// - Throws: ``GPUError/shaderCompilationFailed(_:)`` if compilation fails.
    public convenience init(source: String, device: MTLDevice, label: String? = nil) throws {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw GPUError.shaderCompilationFailed(error.localizedDescription)
        }
        library.label = label
        self.init(library: library)
    }

    /// Look up a function by name in this shader module.
    ///
    /// - Parameter name: The entry point name.
    /// - Returns: The `MTLFunction`, or `nil` if not found.
    public func makeFunction(name: String) -> MTLFunction? {
        library.makeFunction(name: name)
    }

    /// All function names available in this shader module.
    public var functionNames: [String] {
        library.functionNames
    }
}

#endif
