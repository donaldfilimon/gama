// Vec3.swift — 3D vector type wrapping simd_float3
// Part of GamaMath

import simd

// MARK: - Vec3

/// A 3D vector backed by `simd_float3`.
public struct Vec3: Sendable, Equatable, Hashable {
    /// The underlying SIMD storage.
    public var storage: simd_float3

    // MARK: - Initializers

    /// Creates a vector from x, y, and z components.
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float) {
        storage = simd_float3(x, y, z)
    }

    /// Creates a vector from a SIMD value.
    @inlinable
    public init(_ simdValue: simd_float3) {
        storage = simdValue
    }

    /// Creates a vector with all components set to the same value.
    @inlinable
    public init(repeating value: Float) {
        storage = simd_float3(repeating: value)
    }

    /// Creates a Vec3 from a Vec2 and a z component.
    @inlinable
    public init(_ xy: Vec2, _ z: Float) {
        storage = simd_float3(xy.storage, z)
    }

    // MARK: - Static Constants

    /// The zero vector (0, 0, 0).
    public static let zero = Vec3(0, 0, 0)

    /// The one vector (1, 1, 1).
    public static let one = Vec3(1, 1, 1)

    /// Unit vector along the x-axis.
    public static let unitX = Vec3(1, 0, 0)

    /// Unit vector along the y-axis.
    public static let unitY = Vec3(0, 1, 0)

    /// Unit vector along the z-axis.
    public static let unitZ = Vec3(0, 0, 1)

    /// Shorthand for the up direction (0, 1, 0).
    public static let up = Vec3.unitY

    /// Shorthand for the forward direction (0, 0, -1).
    public static let forward = Vec3(0, 0, -1)

    /// Shorthand for the right direction (1, 0, 0).
    public static let right = Vec3.unitX

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

    // MARK: - Swizzle Accessors

    /// The xy components as a Vec2.
    @inlinable public var xy: Vec2 {
        Vec2(x, y)
    }

    /// The xz components as a Vec2.
    @inlinable public var xz: Vec2 {
        Vec2(x, z)
    }

    /// The yz components as a Vec2.
    @inlinable public var yz: Vec2 {
        Vec2(y, z)
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
    @inlinable public var normalized: Vec3 {
        Vec3(simd_normalize(storage))
    }

    // MARK: - Operations

    /// Returns the dot product of two vectors.
    @inlinable
    public static func dot(_ a: Vec3, _ b: Vec3) -> Float {
        simd_dot(a.storage, b.storage)
    }

    /// Returns the cross product of two vectors.
    @inlinable
    public static func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
        Vec3(simd_cross(a.storage, b.storage))
    }

    /// Returns the linear interpolation between two vectors.
    @inlinable
    public static func lerp(_ a: Vec3, _ b: Vec3, t: Float) -> Vec3 {
        Vec3(simd_mix(a.storage, b.storage, simd_float3(repeating: t)))
    }

    /// Returns the distance between two points.
    @inlinable
    public static func distance(_ a: Vec3, _ b: Vec3) -> Float {
        simd_distance(a.storage, b.storage)
    }

    // MARK: - Operators

    @inlinable
    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.storage + rhs.storage)
    }

    @inlinable
    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.storage - rhs.storage)
    }

    @inlinable
    public static func * (lhs: Vec3, rhs: Float) -> Vec3 {
        Vec3(lhs.storage * rhs)
    }

    @inlinable
    public static func * (lhs: Float, rhs: Vec3) -> Vec3 {
        Vec3(lhs * rhs.storage)
    }

    @inlinable
    public static func * (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.storage * rhs.storage)
    }

    @inlinable
    public static prefix func - (v: Vec3) -> Vec3 {
        Vec3(-v.storage)
    }
}

// MARK: - CustomStringConvertible

extension Vec3: CustomStringConvertible {
    public var description: String {
        "Vec3(\(x), \(y), \(z))"
    }
}
