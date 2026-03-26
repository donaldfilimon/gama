// VulkanBackend.swift — Backend factory for Vulkan (stub)
// Part of GamaVulkan

import GamaCore

/// The Vulkan backend entry point (stub).
///
/// All methods throw ``GPUError/backendNotAvailable(_:)`` until a real
/// Vulkan implementation is provided.
public final class VulkanBackend: Sendable {
    /// Shared singleton instance.
    public static let shared = VulkanBackend()

    private init() {}

    /// Request the default Vulkan adapter.
    ///
    /// - Throws: `GPUError.backendNotAvailable` — Vulkan is not yet implemented.
    public func requestDefaultAdapter() throws -> VulkanAdapter {
        throw GPUError.backendNotAvailable("Vulkan")
    }
}
