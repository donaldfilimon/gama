// MetalBuffer.swift — Metal buffer wrapper
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// A Metal buffer that stores GPU-accessible data.
///
/// Wraps an `MTLBuffer`. Metal buffers are internally thread-safe for
/// read access, so this type is marked `@unchecked Sendable`.
public final class MetalBuffer: GPUBuffer, @unchecked Sendable {
    /// The underlying Metal buffer.
    public let mtlBuffer: MTLBuffer

    /// The size of the buffer in bytes.
    public let size: Int

    /// The usage flags for this buffer.
    public let usage: BufferUsage

    /// An optional debug label for the buffer.
    public var label: String? { mtlBuffer.label }

    /// Creates a Metal buffer wrapper.
    /// - Parameters:
    ///   - buffer: The `MTLBuffer` to wrap.
    ///   - size: The size of the buffer in bytes.
    ///   - usage: The usage flags that were specified at creation time.
    public init(buffer: MTLBuffer, size: Int, usage: BufferUsage) {
        self.mtlBuffer = buffer
        self.size = size
        self.usage = usage
    }

    /// Returns a raw pointer to the buffer's contents in CPU-accessible memory.
    ///
    /// The returned pointer is valid for the lifetime of the buffer. After
    /// writing through this pointer, call ``didModifyRange(_:)`` to inform
    /// the GPU of the changed region.
    public func contents() -> UnsafeMutableRawPointer {
        return mtlBuffer.contents()
    }

    /// Notifies the GPU that a region of the buffer has been modified by the CPU.
    ///
    /// On macOS with managed storage mode, this flushes the modified range.
    /// On shared storage mode (iOS / Apple Silicon), this is a no-op but
    /// is called for API consistency.
    ///
    /// - Parameter range: The byte range that was modified.
    public func didModifyRange(_ range: Range<Int>) {
        #if os(macOS)
        mtlBuffer.didModifyRange(range)
        #endif
    }
}

#endif
