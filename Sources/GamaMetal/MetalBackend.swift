// MetalBackend.swift — Backend factory for Metal
// Part of GamaMetal

#if canImport(Metal)
import Metal
import GamaCore

/// The Metal backend entry point. Provides adapter enumeration and default adapter selection.
public final class MetalBackend: Sendable {
    /// Shared singleton instance.
    public static let shared = MetalBackend()

    private init() {}

    /// Enumerate all available Metal GPU adapters on this system.
    ///
    /// On macOS this may return multiple adapters (integrated + discrete).
    /// On iOS/tvOS this typically returns a single adapter.
    public func enumerateAdapters() -> [MetalAdapter] {
        #if os(macOS)
        return MTLCopyAllDevices().map { MetalAdapter(device: $0) }
        #else
        if let device = MTLCreateSystemDefaultDevice() {
            return [MetalAdapter(device: device)]
        }
        return []
        #endif
    }

    /// Request the system default Metal adapter.
    ///
    /// - Throws: `GPUError.backendNotAvailable` if Metal is not supported.
    public func requestDefaultAdapter() throws -> MetalAdapter {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw GPUError.backendNotAvailable("Metal")
        }
        return MetalAdapter(device: device)
    }
}

#endif
