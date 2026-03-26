// Buffer.swift — GPU buffer protocol and descriptor
// Part of GamaCore

// MARK: - Buffer Descriptor

/// Describes the properties of a GPU buffer to be created.
public struct GPUBufferDescriptor: Sendable {
    /// The size of the buffer in bytes.
    public var size: Int

    /// A bitmask specifying the intended usage of the buffer.
    ///
    /// `BufferUsage` is defined in `Types.swift`.
    public var usage: BufferUsage

    /// An optional label for debugging purposes.
    public var label: String?

    /// Creates a new buffer descriptor.
    /// - Parameters:
    ///   - size: The size of the buffer in bytes.
    ///   - usage: The intended usage flags for the buffer.
    ///   - label: An optional debug label.
    public init(size: Int, usage: BufferUsage, label: String? = nil) {
        self.size = size
        self.usage = usage
        self.label = label
    }
}

// MARK: - Buffer Protocol

/// A GPU-allocated memory buffer that can store vertex data, uniform data,
/// or other arbitrary bytes accessible by the GPU.
///
/// Concrete implementations are provided by backend modules (e.g., GamaMetal).
public protocol GPUBuffer: AnyObject, Sendable {
    /// The size of the buffer in bytes.
    var size: Int { get }

    /// The usage flags that were specified at buffer creation time.
    var usage: BufferUsage { get }

    /// An optional debug label for the buffer.
    var label: String? { get }

    /// Returns a raw pointer to the buffer's contents in CPU-accessible memory.
    ///
    /// The returned pointer is valid for the lifetime of the buffer. Writing
    /// through this pointer requires a subsequent call to ``didModifyRange(_:)``
    /// to inform the GPU of the changed region.
    ///
    /// - Returns: A mutable raw pointer to the buffer's backing store.
    func contents() -> UnsafeMutableRawPointer

    /// Notifies the GPU that a region of the buffer has been modified by the CPU.
    ///
    /// Call this after writing to the pointer returned by ``contents()`` so
    /// the backend can flush caches or schedule a synchronization as needed.
    ///
    /// - Parameter range: The byte range that was modified.
    func didModifyRange(_ range: Range<Int>)
}
