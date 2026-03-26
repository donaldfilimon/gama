// MetalQueue.swift — Metal command queue and command buffer wrappers
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

// MARK: - MetalQueue

/// A Metal command queue that creates and submits command buffers.
///
/// Wraps an `MTLCommandQueue`. Metal command queues are internally thread-safe,
/// so this type is marked `@unchecked Sendable`.
public final class MetalQueue: GPUQueue, @unchecked Sendable {
    /// The underlying Metal command queue.
    public let mtlQueue: MTLCommandQueue

    /// The most recently submitted command buffer, used for `waitUntilCompleted`.
    private var lastSubmittedBuffer: MTLCommandBuffer?

    /// Creates a Metal queue wrapping the given command queue.
    /// - Parameter queue: The `MTLCommandQueue` to wrap.
    public init(queue: MTLCommandQueue) {
        self.mtlQueue = queue
    }

    /// Create a new command buffer for recording commands.
    public func createCommandBuffer() throws -> any GPUCommandBuffer {
        guard let commandBuffer = mtlQueue.makeCommandBuffer() else {
            throw GPUError.commandEncodingFailed
        }
        return MetalCommandBuffer(commandBuffer: commandBuffer)
    }

    /// Submit a command buffer for execution on the GPU.
    ///
    /// - Parameter commandBuffer: The command buffer to submit. Must be a `MetalCommandBuffer`.
    public func submit(_ commandBuffer: any GPUCommandBuffer) throws {
        guard let metalCB = commandBuffer as? MetalCommandBuffer else {
            throw GPUError.queueSubmissionFailed
        }
        lastSubmittedBuffer = metalCB.mtlCommandBuffer
        metalCB.mtlCommandBuffer.commit()
    }

    /// Wait until the most recently submitted command buffer has completed execution.
    ///
    /// Uses Metal's async `completed()` API which suspends until the GPU
    /// finishes processing the command buffer.
    public func waitUntilCompleted() async throws {
        guard let buffer = lastSubmittedBuffer else { return }
        await buffer.completed()
        if let error = buffer.error {
            throw error
        }
    }
}

#endif
