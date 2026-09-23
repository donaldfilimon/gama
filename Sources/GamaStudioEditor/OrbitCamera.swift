//  OrbitCamera.swift — GamaStudioEditor
//
//  The viewport camera as a value: a target point and a spherical offset
//  (yaw, pitch, distance) from it. No RealityKit and no input devices here,
//  so the math is testable on its own; `ViewportController` maps drags,
//  scrolls and pinches onto it and applies `position`/`target` to the
//  RealityKit camera.
//
//  The camera is editor state, not authored state: it is not a document
//  command, so it is not undoable and not saved (ADR 0003).

internal import Foundation

/// An orbit camera: it always looks at ``target`` from ``distance`` away, at
/// ``yaw`` around the world Y axis and ``pitch`` above the horizontal.
///
/// Yaw 0 looks from +Z toward -Z; positive yaw turns the eye toward +X.
/// Pitch is clamped short of the poles (``pitchLimit``) so "up" stays
/// defined and the view never flips. Every mutator ignores non-finite input.
public struct OrbitCamera: Hashable, Sendable {
    /// The point the camera looks at and orbits around.
    public private(set) var target: SIMD3<Float>
    /// Rotation around world +Y, in radians.
    public private(set) var yaw: Float
    /// Elevation above the horizontal plane, in radians, within ±``pitchLimit``.
    public private(set) var pitch: Float
    /// Distance from ``target`` to the eye, within ``distanceRange``.
    public private(set) var distance: Float

    /// The largest pitch magnitude: 85°, short of straight up or down.
    public static let pitchLimit: Float = 85 * .pi / 180
    /// Allowed eye distances, in meters.
    public static let distanceRange: ClosedRange<Float> = 0.5...100

    /// Creates a camera from explicit spherical coordinates, clamping pitch
    /// and distance into range.
    public init(target: SIMD3<Float>, yaw: Float, pitch: Float, distance: Float) {
        self.target = target
        self.yaw = yaw
        self.pitch = min(max(pitch, -Self.pitchLimit), Self.pitchLimit)
        self.distance = min(max(distance, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }

    /// Creates the camera that looks at `target` from `eye`.
    public init(lookingAt target: SIMD3<Float>, from eye: SIMD3<Float>) {
        let offset = eye - target
        let distance = (offset * offset).sum().squareRoot()
        let horizontal = (offset.x * offset.x + offset.z * offset.z).squareRoot()
        self.init(
            target: target,
            yaw: atan2(offset.x, offset.z),
            pitch: atan2(offset.y, horizontal),
            distance: distance
        )
    }

    /// Where the eye is: ``target`` plus the spherical offset.
    public var position: SIMD3<Float> {
        target + distance * SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    /// The camera's screen-right direction, a unit vector in the horizontal plane.
    public var right: SIMD3<Float> { SIMD3(cos(yaw), 0, -sin(yaw)) }

    /// The camera's screen-up direction, a unit vector perpendicular to
    /// ``right`` and to the view direction.
    public var up: SIMD3<Float> {
        SIMD3(-sin(pitch) * sin(yaw), cos(pitch), -sin(pitch) * cos(yaw))
    }

    /// Turns the eye around ``target`` by the given angles, in radians.
    public mutating func orbit(yawBy deltaYaw: Float, pitchBy deltaPitch: Float) {
        guard deltaYaw.isFinite, deltaPitch.isFinite else { return }
        yaw = (yaw + deltaYaw).truncatingRemainder(dividingBy: 2 * .pi)
        pitch = min(max(pitch + deltaPitch, -Self.pitchLimit), Self.pitchLimit)
    }

    /// Moves ``target`` (and the eye with it) along the view plane: `right`
    /// and `up` are world-space meters along ``right`` and ``up``.
    public mutating func pan(right dx: Float, up dy: Float) {
        guard dx.isFinite, dy.isFinite else { return }
        target += dx * right + dy * up
    }

    /// Multiplies ``distance`` by `scale` (below 1 moves closer), clamped to
    /// ``distanceRange``. Non-positive or non-finite scales are ignored.
    public mutating func zoom(scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        distance = min(max(distance * scale, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }
}
