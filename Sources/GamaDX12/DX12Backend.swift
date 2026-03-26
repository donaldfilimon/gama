// DX12Backend.swift — Backend factory for DirectX 12 (stub)
// Part of GamaDX12

import GamaCore

/// The DirectX 12 backend entry point.
///
/// This is a stub implementation. All methods throw or fatalError because
/// DirectX 12 is not yet available. The structure exists so the backend can
/// be filled in when targeting Windows.
public final class DX12Backend: Sendable {
    /// Shared singleton instance.
    public static let shared = DX12Backend()

    private init() {}

    /// Request the default DirectX 12 adapter.
    ///
    /// - Throws: `GPUError.backendNotAvailable` unconditionally.
    public func requestDefaultAdapter() throws -> DX12Adapter {
        throw GPUError.backendNotAvailable("DirectX 12")
    }
}
