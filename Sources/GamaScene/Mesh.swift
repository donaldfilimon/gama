// Mesh.swift — Vertex data container for 3D geometry
// Part of GamaScene

import simd

/// A CPU-side mesh holding vertex attributes and optional index data.
///
/// Use the static factory methods on ``Primitives`` (or the convenience
/// extensions on `Mesh`) to generate common shapes.
public struct Mesh: Sendable {
    // MARK: - Vertex Attributes

    /// Per-vertex positions in local object space.
    public var positions: [SIMD3<Float>]

    /// Per-vertex normals (same count as `positions` when present).
    public var normals: [SIMD3<Float>]?

    /// Per-vertex texture coordinates (same count as `positions` when present).
    public var uvs: [SIMD2<Float>]?

    /// Optional index buffer for indexed drawing.
    public var indices: [UInt32]?

    // MARK: - Computed Properties

    /// The number of vertices in this mesh.
    public var vertexCount: Int { positions.count }

    // MARK: - Initializers

    /// Creates a mesh from raw vertex data.
    ///
    /// - Parameters:
    ///   - positions: Vertex positions (required).
    ///   - normals: Vertex normals (optional).
    ///   - uvs: Texture coordinates (optional).
    ///   - indices: Index buffer (optional).
    public init(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        uvs: [SIMD2<Float>]? = nil,
        indices: [UInt32]? = nil
    ) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
    }
}
