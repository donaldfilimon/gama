// Mat4.swift — 4x4 matrix type wrapping simd_float4x4
// Part of GamaMath

import simd

// MARK: - Mat4

/// A 4x4 matrix backed by `simd_float4x4`, suitable for 3D transformations.
public struct Mat4: Sendable, Equatable {
    /// The underlying SIMD storage.
    public var storage: simd_float4x4

    // MARK: - Initializers

    /// Creates a matrix from a SIMD value.
    @inlinable
    public init(_ simdValue: simd_float4x4) {
        storage = simdValue
    }

    /// Creates a matrix from four column vectors.
    @inlinable
    public init(columns c0: Vec4, _ c1: Vec4, _ c2: Vec4, _ c3: Vec4) {
        storage = simd_float4x4(c0.storage, c1.storage, c2.storage, c3.storage)
    }

    /// Creates a diagonal matrix with the given value on the diagonal.
    @inlinable
    public init(diagonal: Float) {
        storage = simd_float4x4(diagonal: simd_float4(repeating: diagonal))
    }

    // MARK: - Static Constants

    /// The 4x4 identity matrix.
    public static let identity = Mat4(diagonal: 1)

    // MARK: - Factory Methods

    /// Creates a translation matrix.
    @inlinable
    public static func translation(_ t: Vec3) -> Mat4 {
        Mat4(columns:
            Vec4(1, 0, 0, 0),
            Vec4(0, 1, 0, 0),
            Vec4(0, 0, 1, 0),
            Vec4(t, 1)
        )
    }

    /// Creates a uniform or non-uniform scale matrix.
    @inlinable
    public static func scale(_ s: Vec3) -> Mat4 {
        Mat4(simd_float4x4(diagonal: simd_float4(s.storage, 1)))
    }

    /// Creates a uniform scale matrix.
    @inlinable
    public static func scale(_ s: Float) -> Mat4 {
        scale(Vec3(s, s, s))
    }

    /// Creates a rotation matrix from an axis and angle (in radians).
    @inlinable
    public static func rotation(axis: Vec3, angle: Float) -> Mat4 {
        let q = simd_quatf(angle: angle, axis: simd_normalize(axis.storage))
        return Mat4(simd_float4x4(q))
    }

    /// Creates a rotation matrix around the x-axis.
    @inlinable
    public static func rotationX(_ angle: Float) -> Mat4 {
        rotation(axis: .unitX, angle: angle)
    }

    /// Creates a rotation matrix around the y-axis.
    @inlinable
    public static func rotationY(_ angle: Float) -> Mat4 {
        rotation(axis: .unitY, angle: angle)
    }

    /// Creates a rotation matrix around the z-axis.
    @inlinable
    public static func rotationZ(_ angle: Float) -> Mat4 {
        rotation(axis: .unitZ, angle: angle)
    }

    // MARK: - Column Access

    /// Accesses a column by index (0-3).
    @inlinable
    public subscript(column: Int) -> Vec4 {
        get { Vec4(storage[column]) }
        set { storage[column] = newValue.storage }
    }

    // MARK: - Computed Properties

    /// The inverse of this matrix.
    @inlinable public var inverse: Mat4 {
        Mat4(storage.inverse)
    }

    /// The transpose of this matrix.
    @inlinable public var transpose: Mat4 {
        Mat4(storage.transpose)
    }

    /// The determinant of this matrix.
    @inlinable public var determinant: Float {
        storage.determinant
    }

    // MARK: - Operators

    /// Matrix-matrix multiplication.
    @inlinable
    public static func * (lhs: Mat4, rhs: Mat4) -> Mat4 {
        Mat4(lhs.storage * rhs.storage)
    }

    /// Matrix-vector multiplication.
    @inlinable
    public static func * (lhs: Mat4, rhs: Vec4) -> Vec4 {
        Vec4(lhs.storage * rhs.storage)
    }

    /// Transforms a Vec3 as a point (w=1), returning the resulting Vec3.
    @inlinable
    public func transformPoint(_ p: Vec3) -> Vec3 {
        let result = storage * simd_float4(p.storage, 1)
        return Vec3(result.x, result.y, result.z)
    }

    /// Transforms a Vec3 as a direction (w=0), returning the resulting Vec3.
    @inlinable
    public func transformDirection(_ d: Vec3) -> Vec3 {
        let result = storage * simd_float4(d.storage, 0)
        return Vec3(result.x, result.y, result.z)
    }
}

// MARK: - CustomStringConvertible

extension Mat4: CustomStringConvertible {
    public var description: String {
        "Mat4(\(storage))"
    }
}
