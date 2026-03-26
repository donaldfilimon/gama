// AABB.swift — Axis-aligned bounding box for spatial queries
// Part of GamaMath

import simd

// MARK: - AABB

/// An axis-aligned bounding box defined by minimum and maximum corner points.
public struct AABB: Sendable, Equatable {
    /// The minimum corner of the bounding box.
    public var min: Vec3

    /// The maximum corner of the bounding box.
    public var max: Vec3

    // MARK: - Initializers

    /// Creates an AABB from minimum and maximum corners.
    @inlinable
    public init(min: Vec3, max: Vec3) {
        self.min = min
        self.max = max
    }

    /// Creates an AABB centered at a point with the given half-extents.
    @inlinable
    public init(center: Vec3, halfExtents: Vec3) {
        self.min = center - halfExtents
        self.max = center + halfExtents
    }

    // MARK: - Computed Properties

    /// The center point of the bounding box.
    @inlinable public var center: Vec3 {
        Vec3(simd_mix(min.storage, max.storage, simd_float3(repeating: 0.5)))
    }

    /// The size (extents) of the bounding box along each axis.
    @inlinable public var size: Vec3 {
        max - min
    }

    /// The half-extents of the bounding box.
    @inlinable public var halfExtents: Vec3 {
        size * 0.5
    }

    // MARK: - Queries

    /// Returns whether this AABB contains the given point.
    @inlinable
    public func contains(_ point: Vec3) -> Bool {
        point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y &&
        point.z >= min.z && point.z <= max.z
    }

    /// Returns whether this AABB intersects another AABB.
    @inlinable
    public func intersects(_ other: AABB) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x &&
        min.y <= other.max.y && max.y >= other.min.y &&
        min.z <= other.max.z && max.z >= other.min.z
    }

    /// Returns the AABB that encloses both this and another AABB.
    @inlinable
    public func union(_ other: AABB) -> AABB {
        AABB(
            min: Vec3(simd_min(min.storage, other.min.storage)),
            max: Vec3(simd_max(max.storage, other.max.storage))
        )
    }

    /// Returns the intersection of this and another AABB, or nil if they do not overlap.
    @inlinable
    public func intersection(_ other: AABB) -> AABB? {
        guard intersects(other) else { return nil }
        return AABB(
            min: Vec3(simd_max(min.storage, other.min.storage)),
            max: Vec3(simd_min(max.storage, other.max.storage))
        )
    }

    /// Tests whether a ray intersects this AABB, returning the entry parameter `t` if so.
    @inlinable
    public func intersects(ray: Ray) -> Float? {
        let invDir = Vec3(
            1.0 / ray.direction.x,
            1.0 / ray.direction.y,
            1.0 / ray.direction.z
        )

        let t1 = (min.x - ray.origin.x) * invDir.x
        let t2 = (max.x - ray.origin.x) * invDir.x
        let t3 = (min.y - ray.origin.y) * invDir.y
        let t4 = (max.y - ray.origin.y) * invDir.y
        let t5 = (min.z - ray.origin.z) * invDir.z
        let t6 = (max.z - ray.origin.z) * invDir.z

        let tmin = Swift.max(Swift.max(Swift.min(t1, t2), Swift.min(t3, t4)), Swift.min(t5, t6))
        let tmax = Swift.min(Swift.min(Swift.max(t1, t2), Swift.max(t3, t4)), Swift.max(t5, t6))

        if tmax < 0 || tmin > tmax {
            return nil
        }

        return tmin >= 0 ? tmin : tmax
    }
}

// MARK: - CustomStringConvertible

extension AABB: CustomStringConvertible {
    public var description: String {
        "AABB(min: \(min), max: \(max))"
    }
}
