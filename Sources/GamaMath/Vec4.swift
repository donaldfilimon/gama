// Vec4.swift — 4D vector type wrapping simd_float4
// Part of GamaMath

import simd

// MARK: - Vec4

/// A 4D vector backed by `simd_float4`.
public struct Vec4: Sendable, Equatable, Hashable {
    /// The underlying SIMD storage.
    public var storage: simd_float4

    // MARK: - Initializers

    /// Creates a vector from x, y, z, and w components.
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        storage = simd_float4(x, y, z, w)
    }

    /// Creates a vector from a SIMD value.
    @inlinable
    public init(_ simdValue: simd_float4) {
        storage = simdValue
    }

    /// Creates a vector with all components set to the same value.
    @inlinable
    public init(repeating value: Float) {
        storage = simd_float4(repeating: value)
    }

    /// Creates a Vec4 from a Vec3 and a w component.
    @inlinable
    public init(_ xyz: Vec3, _ w: Float) {
        storage = simd_float4(xyz.storage.x, xyz.storage.y, xyz.storage.z, w)
    }

    /// Creates a Vec4 from a Vec2 and z, w components.
    @inlinable
    public init(_ xy: Vec2, _ z: Float, _ w: Float) {
        storage = simd_float4(xy.storage.x, xy.storage.y, z, w)
    }

    // MARK: - Static Constants

    /// The zero vector (0, 0, 0, 0).
    public static let zero = Vec4(0, 0, 0, 0)

    /// The one vector (1, 1, 1, 1).
    public static let one = Vec4(1, 1, 1, 1)

    // MARK: - Components

    /// The x component.
    @inlinable public var x: Float {
        get { storage.x }
        set { storage.x = newValue }
    }

    /// The y component.
    @inlinable public var y: Float {
        get { storage.y }
        set { storage.y = newValue }
    }

    /// The z component.
    @inlinable public var z: Float {
        get { storage.z }
        set { storage.z = newValue }
    }

    /// The w component.
    @inlinable public var w: Float {
        get { storage.w }
        set { storage.w = newValue }
    }

    // MARK: - Swizzle Accessors

    /// The xyz components as a Vec3.
    @inlinable public var xyz: Vec3 {
        Vec3(x, y, z)
    }

    /// The xy components as a Vec2.
    @inlinable public var xy: Vec2 {
        Vec2(x, y)
    }

    // MARK: - Computed Properties

    /// The length (magnitude) of the vector.
    @inlinable public var length: Float {
        simd_length(storage)
    }

    /// The squared length of the vector, avoiding a square root.
    @inlinable public var lengthSquared: Float {
        simd_length_squared(storage)
    }

    /// A normalized copy of this vector.
    @inlinable public var normalized: Vec4 {
        Vec4(simd_normalize(storage))
    }

    // MARK: - Operations

    /// Returns the dot product of two vectors.
    @inlinable
    public static func dot(_ a: Vec4, _ b: Vec4) -> Float {
        simd_dot(a.storage, b.storage)
    }

    /// Returns the linear interpolation between two vectors.
    @inlinable
    public static func lerp(_ a: Vec4, _ b: Vec4, t: Float) -> Vec4 {
        Vec4(simd_mix(a.storage, b.storage, simd_float4(repeating: t)))
    }

    // MARK: - Operators

    @inlinable
    public static func + (lhs: Vec4, rhs: Vec4) -> Vec4 {
        Vec4(lhs.storage + rhs.storage)
    }

    @inlinable
    public static func - (lhs: Vec4, rhs: Vec4) -> Vec4 {
        Vec4(lhs.storage - rhs.storage)
    }

    @inlinable
    public static func * (lhs: Vec4, rhs: Float) -> Vec4 {
        Vec4(lhs.storage * rhs)
    }

    @inlinable
    public static func * (lhs: Float, rhs: Vec4) -> Vec4 {
        Vec4(lhs * rhs.storage)
    }

    @inlinable
    public static prefix func - (v: Vec4) -> Vec4 {
        Vec4(-v.storage)
    }
}

// MARK: - CustomStringConvertible

extension Vec4: CustomStringConvertible {
    public var description: String {
        "Vec4(\(x), \(y), \(z), \(w))"
    }
}
