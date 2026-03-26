// Transform.swift — Composable 3D transform combining position, rotation, and scale
// Part of GamaMath

// MARK: - Transform

/// A 3D transform combining position, rotation, and scale.
///
/// The model matrix is computed as `Translation * Rotation * Scale`.
public struct Transform: Sendable, Equatable {
    /// The position in world space.
    public var position: Vec3

    /// The rotation as a quaternion.
    public var rotation: Quaternion

    /// The scale factor along each axis.
    public var scale: Vec3

    // MARK: - Initializers

    /// Creates a transform with the given position, rotation, and scale.
    @inlinable
    public init(
        position: Vec3 = .zero,
        rotation: Quaternion = .identity,
        scale: Vec3 = .one
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    // MARK: - Static Constants

    /// The identity transform (no translation, rotation, or scale).
    public static let identity = Transform()

    // MARK: - Computed Properties

    /// The 4x4 model matrix computed from position, rotation, and scale.
    ///
    /// Computed as `T * R * S`.
    @inlinable public var modelMatrix: Mat4 {
        let t = Mat4.translation(position)
        let r = rotation.toMat4()
        let s = Mat4.scale(scale)
        return t * r * s
    }

    /// The forward direction vector of this transform (negative z-axis rotated).
    @inlinable public var forward: Vec3 {
        rotation.rotate(Vec3.forward)
    }

    /// The up direction vector of this transform.
    @inlinable public var up: Vec3 {
        rotation.rotate(Vec3.up)
    }

    /// The right direction vector of this transform.
    @inlinable public var right: Vec3 {
        rotation.rotate(Vec3.right)
    }

    // MARK: - Operations

    /// Returns the inverse transform.
    @inlinable public var inverse: Transform {
        let invRotation = rotation.inverse
        let invScale = Vec3(1.0 / scale.x, 1.0 / scale.y, 1.0 / scale.z)
        let invPosition = invRotation.rotate(-position) * invScale
        return Transform(position: invPosition, rotation: invRotation, scale: invScale)
    }

    /// Transforms a point from local space to world space.
    @inlinable
    public func transformPoint(_ point: Vec3) -> Vec3 {
        modelMatrix.transformPoint(point)
    }

    /// Transforms a direction from local space to world space (ignores translation).
    @inlinable
    public func transformDirection(_ direction: Vec3) -> Vec3 {
        rotation.rotate(direction)
    }
}

// MARK: - CustomStringConvertible

extension Transform: CustomStringConvertible {
    public var description: String {
        "Transform(position: \(position), rotation: \(rotation), scale: \(scale))"
    }
}
