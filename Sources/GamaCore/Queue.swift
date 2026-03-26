// Queue.swift — Command queue protocol for GamaCore

/// A GPU command queue that creates and submits command buffers.
public protocol GPUQueue: AnyObject, Sendable {
    /// Create a new command buffer for recording commands.
    func createCommandBuffer() throws -> any GPUCommandBuffer

    /// Submit a command buffer for execution on the GPU.
    func submit(_ commandBuffer: any GPUCommandBuffer) throws

    /// Wait until all submitted command buffers have completed execution.
    func waitUntilCompleted() async throws
}
