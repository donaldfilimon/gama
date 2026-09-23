//  OrbitCameraTests.swift — GamaStudioEditorTests
//
//  The orbit camera's math, independent of RealityKit and of input devices.

import Foundation
import GamaStudioEditor
import Testing

private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tolerance: Float = 1e-4) -> Bool {
    let d = a - b
    return abs(d.x) <= tolerance && abs(d.y) <= tolerance && abs(d.z) <= tolerance
}

private func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

@Suite("Orbit camera")
struct OrbitCameraTests {
    @Test func lookingAtFromRoundTripsTheEye() {
        let eye = SIMD3<Float>(0, 3, 7)
        let camera = OrbitCamera(lookingAt: .zero, from: eye)
        #expect(close(camera.position, eye))
        #expect(abs(camera.distance - length(eye)) < 1e-4)
        #expect(abs(camera.yaw) < 1e-6)
    }

    @Test func orbitKeepsDistanceAndTarget() {
        var camera = OrbitCamera(lookingAt: SIMD3(1, 0, -2), from: SIMD3(1, 2, 3))
        let distance = camera.distance
        camera.orbit(yawBy: 0.7, pitchBy: -0.2)
        #expect(abs(length(camera.position - camera.target) - distance) < 1e-4)
        #expect(close(camera.target, SIMD3(1, 0, -2)))
    }

    @Test func quarterTurnMovesTheEyeFromFrontToSide() {
        var camera = OrbitCamera(target: .zero, yaw: 0, pitch: 0, distance: 5)
        #expect(close(camera.position, SIMD3(0, 0, 5)))
        camera.orbit(yawBy: .pi / 2, pitchBy: 0)
        #expect(close(camera.position, SIMD3(5, 0, 0)))
    }

    @Test func pitchIsClampedShortOfThePoles() {
        var camera = OrbitCamera(target: .zero, yaw: 0, pitch: 0, distance: 5)
        camera.orbit(yawBy: 0, pitchBy: 10)
        #expect(camera.pitch == OrbitCamera.pitchLimit)
        camera.orbit(yawBy: 0, pitchBy: -20)
        #expect(camera.pitch == -OrbitCamera.pitchLimit)
        #expect(OrbitCamera.pitchLimit < .pi / 2)
    }

    @Test func zoomScalesDistanceWithinItsRange() {
        var camera = OrbitCamera(target: .zero, yaw: 0, pitch: 0, distance: 10)
        camera.zoom(scale: 0.5)
        #expect(camera.distance == 5)
        camera.zoom(scale: 0.0001)
        #expect(camera.distance == OrbitCamera.distanceRange.lowerBound)
        camera.zoom(scale: 1e6)
        #expect(camera.distance == OrbitCamera.distanceRange.upperBound)
        camera.zoom(scale: 0)      // non-positive and non-finite scales are ignored
        camera.zoom(scale: -2)
        camera.zoom(scale: .nan)
        #expect(camera.distance == OrbitCamera.distanceRange.upperBound)
    }

    @Test func panMovesTargetAndEyeTogetherAlongTheViewPlane() {
        var camera = OrbitCamera(target: .zero, yaw: 0, pitch: 0, distance: 5)
        let offset = camera.position - camera.target
        camera.pan(right: 2, up: 1)
        // Looking down -Z from +Z, "right" is +X and "up" is +Y.
        #expect(close(camera.target, SIMD3(2, 1, 0)))
        #expect(close(camera.position - camera.target, offset))

        var turned = OrbitCamera(target: .zero, yaw: .pi / 2, pitch: 0, distance: 5)
        turned.pan(right: 1, up: 0)
        // Looking from +X toward the origin, screen-right is world -Z.
        #expect(close(turned.target, SIMD3(0, 0, -1)))
    }

    @Test func basisIsOrthonormal() {
        let camera = OrbitCamera(target: SIMD3(0.5, 1, 0), yaw: 0.9, pitch: 0.6, distance: 4)
        let right = camera.right, up = camera.up
        let forward = (camera.target - camera.position) / camera.distance
        #expect(abs(length(right) - 1) < 1e-4)
        #expect(abs(length(up) - 1) < 1e-4)
        #expect(abs((right * up).sum()) < 1e-4)
        #expect(abs((right * forward).sum()) < 1e-4)
        #expect(abs((up * forward).sum()) < 1e-4)
        #expect(up.y > 0)
    }

    @Test func nonFiniteInputIsIgnored() {
        var camera = OrbitCamera(target: .zero, yaw: 0, pitch: 0, distance: 5)
        let before = camera
        camera.orbit(yawBy: .nan, pitchBy: 0)
        camera.orbit(yawBy: 0, pitchBy: .infinity)
        camera.pan(right: .nan, up: 1)
        #expect(camera == before)
    }

    @Test func framingCentersAndFitsTheSphere() {
        var camera = OrbitCamera(target: .zero, yaw: 0.4, pitch: 0.3, distance: 20)
        camera.frame(center: SIMD3(1, 2, 3), radius: 2, fieldOfViewDegrees: 60)
        #expect(close(camera.target, SIMD3(1, 2, 3)))
        #expect(camera.yaw == 0.4)
        #expect(camera.pitch == 0.3)
        let halfFOV: Float = 30 * .pi / 180
        // The whole sphere is inside the view cone...
        #expect(asin(2 / camera.distance) <= halfFOV + 1e-4)
        // ...with exactly the documented margin.
        #expect(abs(camera.distance - 2 / sin(halfFOV) * OrbitCamera.frameMargin) < 1e-3)
    }

    @Test func framingHandlesDegenerateInput() {
        var camera = OrbitCamera(target: .zero, yaw: 0, pitch: 0, distance: 5)
        camera.frame(center: SIMD3(1, 0, 0), radius: 0, fieldOfViewDegrees: 60)
        let minimum = OrbitCamera.frameMinimumRadius / sin(30 * Float.pi / 180) * OrbitCamera.frameMargin
        #expect(abs(camera.distance - max(minimum, OrbitCamera.distanceRange.lowerBound)) < 1e-4)
        camera.frame(center: SIMD3(1, 0, 0), radius: .nan, fieldOfViewDegrees: 60)
        #expect(abs(camera.distance - max(minimum, OrbitCamera.distanceRange.lowerBound)) < 1e-4)

        camera.frame(center: .zero, radius: 1e6, fieldOfViewDegrees: 60)
        #expect(camera.distance == OrbitCamera.distanceRange.upperBound)

        let before = camera
        camera.frame(center: SIMD3(.nan, 0, 0), radius: 1, fieldOfViewDegrees: 60)
        camera.frame(center: .zero, radius: 1, fieldOfViewDegrees: 0)
        camera.frame(center: .zero, radius: 1, fieldOfViewDegrees: 180)
        #expect(camera == before)
    }
}
