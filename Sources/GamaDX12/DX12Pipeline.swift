// DX12Pipeline.swift — Stub pipeline types for DirectX 12
// Part of GamaDX12

import GamaCore

// MARK: - Shader Module

/// A DirectX 12 shader module (stub).
public final class DX12ShaderModule: GPUShaderModule, @unchecked Sendable {
    public var label: String? {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Render Pipeline

/// A DirectX 12 render pipeline (stub).
public final class DX12RenderPipeline: GPURenderPipeline, @unchecked Sendable {
    public var label: String? {
        fatalError("DirectX 12 backend not yet implemented")
    }
}

// MARK: - Compute Pipeline

/// A DirectX 12 compute pipeline (stub).
public final class DX12ComputePipeline: GPUComputePipeline, @unchecked Sendable {
    public var label: String? {
        fatalError("DirectX 12 backend not yet implemented")
    }
}
