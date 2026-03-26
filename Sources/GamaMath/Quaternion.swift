// Quaternion.swift — Quaternion type wrapping simd_quatf
// Part of GamaMath

import simd

// MARK: - Quaternion

/// A quaternion backed by `simd_quatf`, used for rotation representation.
public struct Quaternion: Sendable, Equatable {
    /// The underlying SIMD storage.
    public var storage: simd_quatf

    // MARK: - Initializers

    /// Creates a quaternion from a SIMD quaternion.
    @inlinable
    public init(_ simdValue: simd_quatf) {
        storage = simdValue
    }

    /// Creates a quaternion from individual components (ix, iy, iz, r).
    @inlinable
    public init(ix: Float, iy: Float, iz: Float, r: Float) {
        storage = simd_quatf(ix: ix, iy: iy, iz: iz, r: r)
    }

    // MARK: - Static Constants

    /// The identity quaternion (no rotation).
    public static let identity = Quaternion(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))

    // MARK: - Factory Methods

    /// Creates a quaternion from an axis and angle (in radians).
    @inlinable
    public static func fromAxisAngle(axis: Vec3, angle: Float) -> Quaternion {
        Quaternion(simd_quatf(angle: angle, axis: simd_normalize(axis.storage)))
    }

    /// Creates a quaternion from Euler angles (pitch, yaw, roll) in radians.
    ///
    /// Rotation order: yaw (Y) * pitch (X) * roll (Z).
    @inlinable
    public static func fromEuler(pitch: Float, yaw: Float, roll: Float) -> Quaternion {
        let qx = simd_quatf(angle: pitch, axis: simd_float3(1, 0, 0))
        let qy = simd_quatf(angle: yaw, axis: simd_float3(0, 1, 0))
        let qz = simd_quatf(angle: roll, axis: simd_float3(0, 0, 1))
        return Quaternion(qy * qx * qz)
    }

    /// Creates a quaternion that rotates from one direction to another.
    @inlinable
    public static func fromTo(from: Vec3, to: Vec3) -> Quaternion {
        let f = simd_normalize(from.storage)
        let t = simd_normalize(to.storage)
        let dot = simd_dot(f, t)

        if dot >= 1.0 - 1e-6 {
            return .identity
        }

        let axis = simd_normalize(simd_cross(f, t))
        let angle = acos(simd_clamp(dot, -1, 1))
        return fromAxisAngle(axis: Vec3(axis), angle: angle)
    }

    // MARK: - Properties

    /// The axis of rotation.
    @inlinable public var axis: Vec3 {
        Vec3(storage.axis)
    }

    /// The angle of rotation in radians.
    @inlinable public var angle: Float {
        storage.angle
    }

    /// The conjugate (inverse for unit quaternions).
    @inlinable public var conjugate: Quaternion {
        Quaternion(storage.conjugate)
    }

    /// The inverse of this quaternion.
    @inlinable public var inverse: Quaternion {
        Quaternion(storage.inverse)
    }

    /// The length of the quaternion.
    @inlinable public var length: Float {
        storage.length
    }

    /// A normalized copy of this quaternion.
    @inlinable public var normalized: Quaternion {
        Quaternion(storage.normalized)
    }

    // MARK: - Operations

    /// Spherical linear interpolation between two quaternions.
    @inlinable
    public static func slerp(_ a: Quaternion, _ b: Quaternion, t: Float) -> Quaternion {
        Quaternion(simd_slerp(a.storage, b.storage, t))
    }

    /// Converts this quaternion to a 4x4 rotation matrix.
    @inlinable
    public func toMat4() -> Mat4 {
        Mat4(simd_float4x4(storage))
    }

    /// Rotates a vector by this quaternion.
    @inlinable
    public func rotate(_ v: Vec3) -> Vec3 {
        Vec3(storage.act(v.storage))
    }

    // MARK: - Operators

    /// Quaternion multiplication (composition of rotations).
    @inlinable
    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
        Quaternion(lhs.storage * rhs.storage)
    }
}

// MARK: - CustomStringConvertible

extension Quaternion: CustomStringConvertible {
    public var description: String {
        "Quaternion(ix: \(storage.imag.x), iy: \(storage.imag.y), iz: \(storage.imag.z), r: \(storage.real))"
    }
}
