// VulkanPipeline.swift — Stub pipeline types for Vulkan
// Part of GamaVulkan

import GamaCore

// MARK: - Shader Module

/// A stub Vulkan shader module. All properties fatalError.
public final class VulkanShaderModule: GPUShaderModule, @unchecked Sendable {
    public var label: String? {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Render Pipeline

/// A stub Vulkan render pipeline. All properties fatalError.
public final class VulkanRenderPipeline: GPURenderPipeline, @unchecked Sendable {
    public var label: String? {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Compute Pipeline

/// A stub Vulkan compute pipeline. All properties fatalError.
public final class VulkanComputePipeline: GPUComputePipeline, @unchecked Sendable {
    public var label: String? {
        fatalError("Vulkan backend not yet implemented")
    }
}
