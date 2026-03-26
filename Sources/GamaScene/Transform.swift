// Transform.swift — Local transform composed of position, rotation, and scale
// Part of GamaScene

import simd

/// A local transform decomposed into translation, rotation, and scale.
///
/// Combines into a 4×4 matrix via `matrix` for scene-graph composition.
public struct Transform: Sendable {
    /// Position in local space.
    public var position: SIMD3<Float>

    /// Orientation as a unit quaternion.
    public var rotation: simd_quatf

    /// Non-uniform scale factors.
    public var scale: SIMD3<Float>

    /// Creates a transform with the given components.
    ///
    /// - Parameters:
    ///   - position: Translation vector. Defaults to the origin.
    ///   - rotation: Rotation quaternion. Defaults to identity.
    ///   - scale: Scale factors per axis. Defaults to uniform 1.
    public init(
        position: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    /// The identity transform (no translation, rotation, or scaling).
    public static let identity = Transform()

    /// The composed 4×4 matrix: `T * R * S`.
    public var matrix: simd_float4x4 {
        let s = simd_float4x4(diagonal: SIMD4<Float>(scale.x, scale.y, scale.z, 1))
        let r = simd_float4x4(rotation)
        var t = simd_float4x4(1) // identity
        t.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        return t * r * s
    }
}
