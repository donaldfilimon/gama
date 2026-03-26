// Vec2.swift — 2D vector type wrapping simd_float2
// Part of GamaMath

import simd

// MARK: - Vec2

/// A 2D vector backed by `simd_float2`.
public struct Vec2: Sendable, Equatable, Hashable {
    /// The underlying SIMD storage.
    public var storage: simd_float2

    // MARK: - Initializers

    /// Creates a vector from x and y components.
    @inlinable
    public init(_ x: Float, _ y: Float) {
        storage = simd_float2(x, y)
    }

    /// Creates a vector from a SIMD value.
    @inlinable
    public init(_ simdValue: simd_float2) {
        storage = simdValue
    }

    /// Creates a vector with all components set to the same value.
    @inlinable
    public init(repeating value: Float) {
        storage = simd_float2(repeating: value)
    }

    // MARK: - Static Constants

    /// The zero vector (0, 0).
    public static let zero = Vec2(0, 0)

    /// The one vector (1, 1).
    public static let one = Vec2(1, 1)

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
    @inlinable public var normalized: Vec2 {
        Vec2(simd_normalize(storage))
    }

    // MARK: - Operations

    /// Returns the dot product of two vectors.
    @inlinable
    public static func dot(_ a: Vec2, _ b: Vec2) -> Float {
        simd_dot(a.storage, b.storage)
    }

    /// Returns the linear interpolation between two vectors.
    @inlinable
    public static func lerp(_ a: Vec2, _ b: Vec2, t: Float) -> Vec2 {
        Vec2(simd_mix(a.storage, b.storage, simd_float2(repeating: t)))
    }

    // MARK: - Operators

    @inlinable
    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(lhs.storage + rhs.storage)
    }

    @inlinable
    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(lhs.storage - rhs.storage)
    }

    @inlinable
    public static func * (lhs: Vec2, rhs: Float) -> Vec2 {
        Vec2(lhs.storage * rhs)
    }

    @inlinable
    public static func * (lhs: Float, rhs: Vec2) -> Vec2 {
        Vec2(lhs * rhs.storage)
    }

    @inlinable
    public static prefix func - (v: Vec2) -> Vec2 {
        Vec2(-v.storage)
    }
}

// MARK: - CustomStringConvertible

extension Vec2: CustomStringConvertible {
    public var description: String {
        "Vec2(\(x), \(y))"
    }
}
