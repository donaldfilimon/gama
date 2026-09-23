//  LookAt.swift — GamaStudioEditor
//
//  Look-at orientation for authored cameras and lights. The core
//  (`GamaAuthoring`) stays standard-library only and carries its own
//  `Rotation`, so the quaternion math that needs `simd` lives here, in the
//  editor, and hands the core a plain normalized `Rotation`.

public import GamaAuthoring
internal import simd

extension Rotation {
    /// The rotation that points an entity at `eye` toward `target`, using
    /// RealityKit's convention for cameras and lights: the entity looks down
    /// its local −Z, with local +Y as close to `up` as the view allows.
    ///
    /// When the view direction is parallel to `up` (looking straight up or
    /// down), world −Z (or +Z) stands in for `up` so the result stays
    /// defined. Returns ``Rotation/identity`` when `eye` and `target`
    /// coincide or any input is non-finite. The result is always a finite
    /// unit quaternion, so it passes `Transform.validate()`.
    public static func lookAt(
        _ target: SIMD3<Float>, from eye: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0)
    ) -> Rotation {
        let offset = target - eye
        let distance = simd_length(offset)
        guard distance.isFinite, distance > 1e-6, simd_length(up).isFinite else { return .identity }
        let forward = offset / distance
        var right = simd_cross(forward, up)
        if simd_length(right) < 1e-4 {
            // Straight up or down: keep screen-up pointing toward −Z when
            // looking down (and +Z when looking up), as a top view expects.
            right = simd_cross(forward, SIMD3(0, 0, forward.y < 0 ? -1 : 1))
        }
        right = simd_normalize(right)
        let trueUp = simd_cross(right, forward)
        let basis = simd_float3x3(columns: (right, trueUp, -forward))
        let q = simd_normalize(simd_quatf(basis)).vector
        let rotation = Rotation(x: q.x, y: q.y, z: q.z, w: q.w)
        return rotation.isFinite && rotation.isNormalized ? rotation : .identity
    }
}
