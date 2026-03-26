// SceneCamera.swift — Camera with projection and view matrices
// Part of GamaScene

import GamaMath
import simd

/// A camera that provides projection and view matrices for rendering.
///
/// Use the static factory methods ``perspective(fovY:aspectRatio:near:far:)``
/// and ``orthographic(left:right:bottom:top:near:far:)`` for common setups.
/// Projection matrices use Metal-style [0,1] depth range.
public struct SceneCamera: Sendable {
    // MARK: - Properties

    /// The projection matrix (perspective or orthographic).
    public var projectionMatrix: Mat4

    /// The view matrix (world-to-camera transform).
    public var viewMatrix: Mat4

    // MARK: - Initializers

    /// Creates a camera with explicit projection and view matrices.
    ///
    /// - Parameters:
    ///   - projectionMatrix: The projection matrix.
    ///   - viewMatrix: The view (camera) matrix.
    public init(
        projectionMatrix: Mat4 = .identity,
        viewMatrix: Mat4 = .identity
    ) {
        self.projectionMatrix = projectionMatrix
        self.viewMatrix = viewMatrix
    }

    // MARK: - Factory Methods

    /// Creates a perspective camera.
    ///
    /// Uses Metal-correct [0,1] depth range via `Camera.perspectiveProjection`.
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
        let projection = Camera.perspectiveProjection(
            fovY: fovY,
            aspect: aspectRatio,
            near: near,
            far: far
        )
        return SceneCamera(projectionMatrix: projection)
    }

    /// Creates an orthographic camera.
    ///
    /// Uses Metal-correct [0,1] depth range via `Camera.orthographicProjection`.
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
        let projection = Camera.orthographicProjection(
            left: left,
            right: right,
            bottom: bottom,
            top: top,
            near: near,
            far: far
        )
        return SceneCamera(projectionMatrix: projection)
    }

    /// Creates a look-at view matrix.
    ///
    /// - Parameters:
    ///   - eye: Camera position in world space.
    ///   - target: The point the camera looks at.
    ///   - up: The world up direction.
    /// - Returns: A 4x4 view matrix.
    public static func lookAt(
        eye: Vec3,
        target: Vec3,
        up: Vec3 = .up
    ) -> Mat4 {
        Camera.lookAt(eye: eye, target: target, up: up)
    }
}
