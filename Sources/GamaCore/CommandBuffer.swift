// CommandBuffer.swift — Command buffer protocol for GamaCore
// Part of GamaCore

// MARK: - Command Buffer Protocol

/// A buffer that stores encoded GPU commands for submission to a command queue.
///
/// Command buffers are single-use: once committed, they cannot be reused.
/// Create command encoders from this buffer to record rendering or compute work,
/// then call ``commit()`` to submit the buffer for execution.
///
/// Concrete implementations are provided by backend modules (e.g., GamaMetal).
///
/// - Note: ``GPURenderCommandEncoder`` and ``GPUComputeCommandEncoder`` are
///   defined in `CommandEncoder.swift`. ``GPURenderPassDescriptor`` is defined
///   in `RenderPassDescriptor.swift`.
public protocol GPUCommandBuffer: AnyObject, Sendable {
    /// An optional debug label for identifying this command buffer.
    var label: String? { get }

    /// Creates a new render command encoder configured with the given render pass.
    ///
    /// - Parameter descriptor: The render pass descriptor specifying attachments
    ///   and load/store actions.
    /// - Returns: A render command encoder ready to record draw calls.
    /// - Throws: ``GPUError/commandEncodingFailed`` if the encoder cannot be created.
    func makeRenderCommandEncoder(descriptor: GPURenderPassDescriptor) throws -> any GPURenderCommandEncoder

    /// Creates a new compute command encoder.
    ///
    /// - Returns: A compute command encoder ready to record dispatch calls.
    /// - Throws: ``GPUError/commandEncodingFailed`` if the encoder cannot be created.
    func makeComputeCommandEncoder() throws -> any GPUComputeCommandEncoder

    /// Submits the command buffer to the GPU for execution.
    ///
    /// After calling this method the command buffer is consumed and must not be
    /// reused. Use ``waitUntilCompleted()`` to asynchronously wait for the GPU
    /// to finish executing the recorded commands.
    func commit()

    /// Asynchronously waits until all commands in this buffer have finished
    /// executing on the GPU.
    ///
    /// - Throws: ``GPUError`` if execution encountered a fault.
    func waitUntilCompleted() async throws
}
