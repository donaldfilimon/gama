// Ray.swift — Ray type for picking and intersection tests
// Part of GamaMath

// MARK: - Ray

/// A ray defined by an origin point and a direction vector.
public struct Ray: Sendable, Equatable {
    /// The origin point of the ray.
    public var origin: Vec3

    /// The direction of the ray (should be normalized for correct distance calculations).
    public var direction: Vec3

    // MARK: - Initializers

    /// Creates a ray with the given origin and direction.
    ///
    /// The direction is not automatically normalized; callers should provide a unit vector
    /// for correct distance-based calculations.
    @inlinable
    public init(origin: Vec3, direction: Vec3) {
        self.origin = origin
        self.direction = direction
    }

    // MARK: - Operations

    /// Returns the point at parameter `t` along the ray: `origin + t * direction`.
    @inlinable
    public func point(at t: Float) -> Vec3 {
        origin + direction * t
    }
}

// MARK: - CustomStringConvertible

extension Ray: CustomStringConvertible {
    public var description: String {
        "Ray(origin: \(origin), direction: \(direction))"
    }
}
