// Errors.swift — GPU error types for GamaCore

/// Errors that can occur during GPU operations.
public enum GPUError: Error, Sendable {
    /// Failed to create a GPU device.
    case deviceCreationFailed
    /// Failed to allocate a buffer of the given size in bytes.
    case bufferAllocationFailed(size: Int)
    /// Failed to create a texture.
    case textureCreationFailed
    /// Failed to create a pipeline with the given description.
    case pipelineCreationFailed(String)
    /// Shader compilation failed with the given diagnostic message.
    case shaderCompilationFailed(String)
    /// Failed to encode commands into a command buffer.
    case commandEncodingFailed
    /// Failed to submit a command buffer to the queue.
    case queueSubmissionFailed
    /// The GPU ran out of memory.
    case outOfMemory
    /// The requested operation is not supported by the current backend.
    case unsupportedOperation(String)
    /// The requested backend is not available on this platform.
    case backendNotAvailable(String)
}
