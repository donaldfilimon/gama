/// A rotation stored as a unit quaternion `(x, y, z, w)`.
///
/// `simd_quatf` lives in the Apple `simd` module, which this standard-library-only
/// target may not import, so the core carries its own value. A runtime bridge
/// converts it at the boundary.
public struct Rotation: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float

    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    /// No rotation.
    public static let identity = Rotation(x: 0, y: 0, z: 0, w: 1)

    /// Whether every component is finite.
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }

    /// Whether the quaternion has unit length, within `1e-4` of 1 squared.
    public var isNormalized: Bool {
        let lengthSquared = x * x + y * y + z * z + w * w
        return abs(lengthSquared - 1) <= 1e-4
    }
}

/// Position, rotation, and scale of an entity relative to its parent.
public struct Transform: Hashable, Codable, Sendable {
    public var position: SIMD3<Float>
    public var rotation: Rotation
    public var scale: SIMD3<Float>

    public init(
        position: SIMD3<Float> = .zero,
        rotation: Rotation = .identity,
        scale: SIMD3<Float> = SIMD3(repeating: 1)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    /// The identity transform.
    public static let identity = Transform()

    /// Rejects non-finite values, a non-unit rotation, and a zero scale axis,
    /// each of which would make the runtime projection degenerate.
    public func validate() throws(AuthoringError) {
        for axis in 0..<3 {
            guard position[axis].isFinite else {
                throw .invalidTransform("position is not finite")
            }
            guard scale[axis].isFinite, scale[axis] != 0 else {
                throw .invalidTransform("scale must be finite and non-zero on every axis")
            }
        }
        guard rotation.isFinite, rotation.isNormalized else {
            throw .invalidTransform("rotation must be a finite unit quaternion")
        }
    }
}
