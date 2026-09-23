/// The shape of a ``Light``'s falloff.
public enum LightKind: Hashable, Codable, Sendable {
    /// Parallel rays with no falloff, such as sunlight.
    case directional
    /// Radiates equally in all directions out to `attenuationRadius` meters.
    case point(attenuationRadius: Float)
    /// A directional cone between `innerAngleDegrees` (full intensity) and
    /// `outerAngleDegrees` (zero), out to `attenuationRadius` meters.
    case spot(innerAngleDegrees: Float, outerAngleDegrees: Float, attenuationRadius: Float)

    /// Rejects a non-finite or non-positive radius, and a spot whose angles
    /// are not finite, not ordered `0 < inner <= outer < 180`, or whose
    /// radius is not positive.
    public func validate() throws(AuthoringError) {
        switch self {
        case .directional:
            break
        case .point(let attenuationRadius):
            guard attenuationRadius.isFinite, attenuationRadius > 0 else {
                throw .invalidLight("point light attenuation radius must be finite and positive")
            }
        case .spot(let inner, let outer, let attenuationRadius):
            guard inner.isFinite, outer.isFinite else {
                throw .invalidLight("spot light angles must be finite")
            }
            guard inner > 0, inner <= outer, outer < 180 else {
                throw .invalidLight("spot light angles must satisfy 0 < inner <= outer < 180")
            }
            guard attenuationRadius.isFinite, attenuationRadius > 0 else {
                throw .invalidLight("spot light attenuation radius must be finite and positive")
            }
        }
    }
}

/// A light source authored on an entity.
public struct Light: Hashable, Codable, Sendable {
    /// The falloff shape and its parameters.
    public var kind: LightKind
    /// Linear RGB, each channel in `0...1`.
    public var color: SIMD3<Float>
    /// Brightness in the runtime projection's native unit: lux for
    /// ``LightKind/directional``, lumens for
    /// ``LightKind/point(attenuationRadius:)`` and
    /// ``LightKind/spot(innerAngleDegrees:outerAngleDegrees:attenuationRadius:)``.
    /// Finite and non-negative.
    public var intensity: Float

    public init(kind: LightKind, color: SIMD3<Float> = SIMD3(repeating: 1), intensity: Float) {
        self.kind = kind
        self.color = color
        self.intensity = intensity
    }

    /// A white directional light at intensity 3000, matching the editor's
    /// fallback light (`ViewportController.editorLight`, ADR 0004 decision 6).
    public static let defaultDirectional = Light(kind: .directional, intensity: 3000)

    /// A white point light with a 10 m attenuation radius, at an intensity
    /// close to RealityKit's own `PointLightComponent` default (26963.76
    /// lumens — a RealityKit unit, not a physical one), visible at a few
    /// meters.
    public static let defaultPoint = Light(kind: .point(attenuationRadius: 10), intensity: 26963.76)

    /// Rejects a non-finite or negative intensity, a color channel outside
    /// `0...1` (which also rejects NaN), and an invalid ``kind``.
    public func validate() throws(AuthoringError) {
        guard intensity.isFinite, intensity >= 0 else {
            throw .invalidLight("intensity must be finite and non-negative")
        }
        for axis in 0..<3 {
            guard (0...1).contains(color[axis]) else {
                throw .invalidLight("color channels must be in 0...1")
            }
        }
        try kind.validate()
    }
}

/// A camera authored on an entity; the entity's ``Transform`` supplies its
/// position and orientation.
public struct CameraSettings: Hashable, Codable, Sendable {
    /// Vertical field of view, in degrees, within `1...179`.
    public var fieldOfViewDegrees: Float
    /// The near clip plane distance, in meters. Finite and positive.
    public var near: Float
    /// The far clip plane distance, in meters. Finite and greater than
    /// ``near``.
    public var far: Float

    public init(fieldOfViewDegrees: Float = 60, near: Float = 0.01, far: Float = 1000) {
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.near = near
        self.far = far
    }

    /// The default camera: 60° field of view, near 0.01 m, far 1000 m.
    public static let `default` = CameraSettings()

    /// Rejects non-finite values, a field of view outside `1...179`, a
    /// non-positive `near`, and a `far` that does not exceed `near`.
    public func validate() throws(AuthoringError) {
        guard fieldOfViewDegrees.isFinite, (1...179).contains(fieldOfViewDegrees) else {
            throw .invalidCamera("field of view must be finite and in 1...179 degrees")
        }
        guard near.isFinite, near > 0 else {
            throw .invalidCamera("near must be finite and positive")
        }
        guard far.isFinite, far > near else {
            throw .invalidCamera("far must be finite and greater than near")
        }
    }
}
