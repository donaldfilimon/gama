// VulkanResources.swift — Stub resource types for Vulkan
// Part of GamaVulkan

import GamaCore

// MARK: - Buffer

/// A stub Vulkan buffer. All methods and properties fatalError.
public final class VulkanBuffer: GPUBuffer, @unchecked Sendable {
    public var size: Int {
        fatalError("Vulkan backend not yet implemented")
    }

    public var usage: BufferUsage {
        fatalError("Vulkan backend not yet implemented")
    }

    public var label: String? {
        fatalError("Vulkan backend not yet implemented")
    }

    public func contents() -> UnsafeMutableRawPointer {
        fatalError("Vulkan backend not yet implemented")
    }

    public func didModifyRange(_ range: Range<Int>) {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Texture

/// A stub Vulkan texture. All methods and properties fatalError.
public final class VulkanTexture: GPUTexture, @unchecked Sendable {
    public var descriptor: GPUTextureDescriptor {
        fatalError("Vulkan backend not yet implemented")
    }

    public var width: UInt32 {
        fatalError("Vulkan backend not yet implemented")
    }

    public var height: UInt32 {
        fatalError("Vulkan backend not yet implemented")
    }

    public var format: PixelFormat {
        fatalError("Vulkan backend not yet implemented")
    }

    public func replaceRegion(
        origin: Origin3D,
        size: Extent3D,
        mipLevel: UInt32,
        data: UnsafeRawPointer,
        bytesPerRow: Int
    ) {
        fatalError("Vulkan backend not yet implemented")
    }
}

// MARK: - Sampler

/// A stub Vulkan sampler. All properties fatalError.
public final class VulkanSampler: GPUSampler, @unchecked Sendable {
    public var label: String? {
        fatalError("Vulkan backend not yet implemented")
    }
}
