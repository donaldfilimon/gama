// MetalCommandBuffer.swift — Metal command buffer wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// A Metal command buffer conforming to ``GPUCommandBuffer``.
///
/// Wraps an `MTLCommandBuffer` and provides factory methods for creating
/// render and compute command encoders. The buffer is single-use: once
/// committed, it cannot be reused.
public final class MetalCommandBuffer: GPUCommandBuffer, @unchecked Sendable {
    /// The underlying Metal command buffer.
    public let mtlCommandBuffer: MTLCommandBuffer

    /// An optional debug label for this command buffer.
    public var label: String? { mtlCommandBuffer.label }

    /// Creates a command buffer wrapping the given Metal command buffer.
    ///
    /// - Parameter commandBuffer: The `MTLCommandBuffer` to wrap.
    public init(commandBuffer: MTLCommandBuffer) {
        self.mtlCommandBuffer = commandBuffer
    }

    // MARK: - Render Command Encoder

    /// Creates a render command encoder configured with the given render pass descriptor.
    ///
    /// Translates a cross-platform ``GPURenderPassDescriptor`` into an
    /// `MTLRenderPassDescriptor` and creates a Metal render command encoder.
    ///
    /// - Parameter descriptor: The render pass descriptor specifying attachments and load/store actions.
    /// - Returns: A ``MetalRenderCommandEncoder`` ready to record draw calls.
    /// - Throws: ``GPUError/commandEncodingFailed`` if the encoder cannot be created.
    public func makeRenderCommandEncoder(
        descriptor: GPURenderPassDescriptor
    ) throws -> any GPURenderCommandEncoder {
        let mtlRPDesc = MTLRenderPassDescriptor()

        // Color attachments
        for (index, colorAttachment) in descriptor.colorAttachments.enumerated() {
            guard let mtlTexture = metalTexture(from: colorAttachment.texture) else {
                throw GPUError.commandEncodingFailed
            }
            let mtlAttachment = mtlRPDesc.colorAttachments[index]!
            mtlAttachment.texture = mtlTexture
            mtlAttachment.loadAction = colorAttachment.loadAction.mtlLoadAction
            mtlAttachment.storeAction = colorAttachment.storeAction.mtlStoreAction
            mtlAttachment.clearColor = MTLClearColor(
                red: colorAttachment.clearColor.r,
                green: colorAttachment.clearColor.g,
                blue: colorAttachment.clearColor.b,
                alpha: colorAttachment.clearColor.a
            )
        }

        // Depth/stencil attachment
        if let depthStencil = descriptor.depthStencilAttachment {
            guard let mtlTexture = metalTexture(from: depthStencil.texture) else {
                throw GPUError.commandEncodingFailed
            }
            mtlRPDesc.depthAttachment.texture = mtlTexture
            mtlRPDesc.depthAttachment.loadAction = depthStencil.depthLoadAction.mtlLoadAction
            mtlRPDesc.depthAttachment.storeAction = depthStencil.depthStoreAction.mtlStoreAction
            mtlRPDesc.depthAttachment.clearDepth = Double(depthStencil.clearDepth)

            mtlRPDesc.stencilAttachment.texture = mtlTexture
            mtlRPDesc.stencilAttachment.loadAction = depthStencil.stencilLoadAction.mtlLoadAction
            mtlRPDesc.stencilAttachment.storeAction = depthStencil.stencilStoreAction.mtlStoreAction
            mtlRPDesc.stencilAttachment.clearStencil = depthStencil.clearStencil
        }

        guard let encoder = mtlCommandBuffer.makeRenderCommandEncoder(descriptor: mtlRPDesc) else {
            throw GPUError.commandEncodingFailed
        }
        encoder.label = descriptor.label

        return MetalRenderCommandEncoder(encoder: encoder)
    }

    // MARK: - Compute Command Encoder

    /// Creates a compute command encoder.
    ///
    /// - Returns: A ``MetalComputeCommandEncoder`` ready to record dispatch calls.
    /// - Throws: ``GPUError/commandEncodingFailed`` if the encoder cannot be created.
    public func makeComputeCommandEncoder() throws -> any GPUComputeCommandEncoder {
        guard let encoder = mtlCommandBuffer.makeComputeCommandEncoder() else {
            throw GPUError.commandEncodingFailed
        }
        return MetalComputeCommandEncoder(encoder: encoder)
    }

    // MARK: - Submission

    /// Commits the command buffer for execution on the GPU.
    ///
    /// After calling this method the command buffer is consumed and must not be reused.
    public func commit() {
        mtlCommandBuffer.commit()
    }

    // MARK: - Helpers

    /// Extracts the underlying `MTLTexture` from a `GPUTexture`.
    ///
    /// Handles both ``MetalTexture`` (device-created textures) and
    /// ``MetalDrawableTexture`` (surface drawable textures).
    private func metalTexture(from texture: any GPUTexture) -> MTLTexture? {
        if let metalTexture = texture as? MetalTexture {
            return metalTexture.mtlTexture
        }
        if let drawableTexture = texture as? MetalDrawableTexture {
            return drawableTexture.mtlTexture
        }
        return nil
    }

    /// Asynchronously waits until all commands in this buffer have finished executing.
    ///
    /// Uses Metal's async `completed()` API which suspends until the GPU
    /// finishes processing this command buffer.
    ///
    /// - Throws: ``GPUError/commandEncodingFailed`` if the GPU reports an error.
    public func waitUntilCompleted() async throws {
        await mtlCommandBuffer.completed()
        if let error = mtlCommandBuffer.error {
            throw error
        }
    }
}

#endif
