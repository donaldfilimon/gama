// Camera.swift — Projection and view matrix utilities for 3D cameras
// Part of GamaMath

import simd

// MARK: - Camera

/// Provides static methods for constructing common camera matrices.
public enum Camera: Sendable {

    // MARK: - Projection Matrices

    /// Creates a perspective projection matrix.
    ///
    /// - Parameters:
    ///   - fovY: Vertical field of view in radians.
    ///   - aspect: Width-to-height aspect ratio.
    ///   - near: Distance to the near clipping plane (must be > 0).
    ///   - far: Distance to the far clipping plane (must be > near).
    /// - Returns: A perspective projection matrix.
    @inlinable
    public static func perspectiveProjection(
        fovY: Float,
        aspect: Float,
        near: Float,
        far: Float
    ) -> Mat4 {
        let y = 1.0 / tanf(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return Mat4(columns:
            Vec4(x, 0, 0, 0),
            Vec4(0, y, 0, 0),
            Vec4(0, 0, z, -1),
            Vec4(0, 0, z * near, 0)
        )
    }

    /// Creates an orthographic projection matrix.
    ///
    /// - Parameters:
    ///   - left: Left edge of the view volume.
    ///   - right: Right edge of the view volume.
    ///   - bottom: Bottom edge of the view volume.
    ///   - top: Top edge of the view volume.
    ///   - near: Distance to the near clipping plane.
    ///   - far: Distance to the far clipping plane.
    /// - Returns: An orthographic projection matrix.
    @inlinable
    public static func orthographicProjection(
        left: Float,
        right: Float,
        bottom: Float,
        top: Float,
        near: Float,
        far: Float
    ) -> Mat4 {
        let width = right - left
        let height = top - bottom
        let depth = far - near
        return Mat4(columns:
            Vec4(2.0 / width, 0, 0, 0),
            Vec4(0, 2.0 / height, 0, 0),
            Vec4(0, 0, -1.0 / depth, 0),
            Vec4(-(right + left) / width, -(top + bottom) / height, -near / depth, 1)
        )
    }

    // MARK: - View Matrix

    /// Creates a look-at view matrix.
    ///
    /// - Parameters:
    ///   - eye: The camera position.
    ///   - target: The point the camera is looking at.
    ///   - up: The world up direction.
    /// - Returns: A view matrix that transforms world space to camera space.
    @inlinable
    public static func lookAt(eye: Vec3, target: Vec3, up: Vec3) -> Mat4 {
        let forward = (target - eye).normalized
        let right = Vec3.cross(forward, up).normalized
        let camUp = Vec3.cross(right, forward)

        return Mat4(columns:
            Vec4(right.x, camUp.x, -forward.x, 0),
            Vec4(right.y, camUp.y, -forward.y, 0),
            Vec4(right.z, camUp.z, -forward.z, 0),
            Vec4(-Vec3.dot(right, eye), -Vec3.dot(camUp, eye), Vec3.dot(forward, eye), 1)
        )
    }
}
