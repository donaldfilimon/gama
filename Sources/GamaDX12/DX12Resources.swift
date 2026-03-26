// DX12Resources.swift — Stub resource types for DirectX 12
// Part of GamaDX12

import GamaCore

// MARK: - Buffer

/// A DirectX 12 GPU buffer (stub).
public final class DX12Buffer: GPUBuffer, @unchecked Sendable {
    public var size: Int {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public var usage: BufferUsage {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public var label: String? {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func contents() -> UnsafeMutableRawPointer {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func didModifyRange(_ range: Range<Int>) {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Texture

/// A DirectX 12 GPU texture (stub).
public final class DX12Texture: GPUTexture, @unchecked Sendable {
    public var descriptor: GPUTextureDescriptor {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public var width: UInt32 {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public var height: UInt32 {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public var format: PixelFormat {
        fatalError("DirectX 12 backend not yet implemented")
    }

    public func replaceRegion(
        origin: Origin3D,
        size: Extent3D,
        mipLevel: UInt32,
        data: UnsafeRawPointer,
        bytesPerRow: Int
    ) {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Sampler

/// A DirectX 12 GPU sampler (stub).
public final class DX12Sampler: GPUSampler, @unchecked Sendable {
    public var label: String? {
        fatalError("DirectX 12 backend not yet implemented")
    }
}
