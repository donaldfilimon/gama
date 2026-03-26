// SceneCamera.swift — Camera with projection and view matrices
// Part of GamaScene

import simd

/// A camera that provides projection and view matrices for rendering.
///
/// Use the static factory methods ``perspective(fovY:aspectRatio:near:far:)``
/// and ``orthographic(left:right:bottom:top:near:far:)`` for common setups.
public struct SceneCamera: Sendable {
    // MARK: - Properties

    /// The projection matrix (perspective or orthographic).
    public var projectionMatrix: simd_float4x4

    /// The view matrix (world-to-camera transform).
    public var viewMatrix: simd_float4x4

    // MARK: - Initializers

    /// Creates a camera with explicit projection and view matrices.
    ///
    /// - Parameters:
    ///   - projectionMatrix: The projection matrix.
    ///   - viewMatrix: The view (camera) matrix.
    public init(
        projectionMatrix: simd_float4x4 = simd_float4x4(1),
        viewMatrix: simd_float4x4 = simd_float4x4(1)
    ) {
        self.projectionMatrix = projectionMatrix
        self.viewMatrix = viewMatrix
    }

    // MARK: - Factory Methods

    /// Creates a perspective camera.
    ///
    /// - Parameters:
    ///   - fovY: Vertical field of view in radians.
    ///   - aspectRatio: Width divided by height.
    ///   - near: Near clipping plane distance.
    ///   - far: Far clipping plane distance.
    /// - Returns: A camera configured with a perspective projection.
    public static func perspective(
        fovY: Float,
        aspectRatio: Float,
        near: Float,
        far: Float
    ) -> SceneCamera {
        let ys = 1 / tan(fovY * 0.5)
        let xs = ys / aspectRatio
        let zRange = far - near
        let zs = -(far + near) / zRange
        let ws = -(2 * far * near) / zRange

        let projection = simd_float4x4(rows: [
            SIMD4<Float>(xs,  0,  0,  0),
            SIMD4<Float>( 0, ys,  0,  0),
            SIMD4<Float>( 0,  0, zs, ws),
            SIMD4<Float>( 0,  0, -1,  0),
        ])

        return SceneCamera(projectionMatrix: projection)
    }

    /// Creates an orthographic camera.
    ///
    /// - Parameters:
    ///   - left: Left clipping plane.
    ///   - right: Right clipping plane.
    ///   - bottom: Bottom clipping plane.
    ///   - top: Top clipping plane.
    ///   - near: Near clipping plane.
    ///   - far: Far clipping plane.
    /// - Returns: A camera configured with an orthographic projection.
    public static func orthographic(
        left: Float,
        right: Float,
        bottom: Float,
        top: Float,
        near: Float,
        far: Float
    ) -> SceneCamera {
        let rl = right - left
        let tb = top - bottom
        let fn = far - near

        let projection = simd_float4x4(rows: [
            SIMD4<Float>(2 / rl,      0,       0, -(right + left) / rl),
            SIMD4<Float>(     0, 2 / tb,       0, -(top + bottom) / tb),
            SIMD4<Float>(     0,      0, -2 / fn, -(far + near) / fn),
            SIMD4<Float>(     0,      0,       0,  1),
        ])

        return SceneCamera(projectionMatrix: projection)
    }

    /// Creates a look-at view matrix.
    ///
    /// - Parameters:
    ///   - eye: Camera position in world space.
    ///   - target: The point the camera looks at.
    ///   - up: The world up direction.
    /// - Returns: A 4×4 view matrix.
    public static func lookAt(
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    ) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)

        return simd_float4x4(rows: [
            SIMD4<Float>( s.x,  s.y,  s.z, -simd_dot(s, eye)),
            SIMD4<Float>( u.x,  u.y,  u.z, -simd_dot(u, eye)),
            SIMD4<Float>(-f.x, -f.y, -f.z,  simd_dot(f, eye)),
            SIMD4<Float>(   0,    0,    0,   1),
        ])
    }
}
