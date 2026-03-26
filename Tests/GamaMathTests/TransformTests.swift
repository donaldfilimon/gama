// TransformTests.swift — Tests for Transform composition and inverse
// Part of GamaMathTests

import Testing
@testable import GamaMath

@Suite("Transform Tests")
struct TransformTests {
    @Test("Identity transform produces identity matrix")
    func identityMatrix() {
        let t = Transform.identity
        #expect(t.modelMatrix == Mat4.identity)
    }

    @Test("Position-only transform translates correctly")
    func positionOnly() {
        let t = Transform(position: Vec3(5, 10, 15))
        let result = t.transformPoint(.zero)
        #expect(abs(result.x - 5) < 1e-6)
        #expect(abs(result.y - 10) < 1e-6)
        #expect(abs(result.z - 15) < 1e-6)
    }

    @Test("Scale-only transform scales correctly")
    func scaleOnly() {
        let t = Transform(scale: Vec3(2, 3, 4))
        let result = t.transformPoint(Vec3(1, 1, 1))
        #expect(abs(result.x - 2) < 1e-6)
        #expect(abs(result.y - 3) < 1e-6)
        #expect(abs(result.z - 4) < 1e-6)
    }

    @Test("Forward direction of identity is negative Z")
    func forwardDirection() {
        let t = Transform.identity
        #expect(abs(t.forward.x - 0) < 1e-6)
        #expect(abs(t.forward.y - 0) < 1e-6)
        #expect(abs(t.forward.z - (-1)) < 1e-6)
    }

    @Test("Transform with rotation and translation")
    func rotationAndTranslation() {
        let t = Transform(
            position: Vec3(0, 0, 0),
            rotation: .fromAxisAngle(axis: .unitY, angle: .pi / 2)
        )
        // Forward should now point along negative X (rotated -Z by +90 degrees around Y in right-hand system)
        let forward = t.forward
        #expect(abs(forward.x - (-1)) < 1e-5)
        #expect(abs(forward.y - 0) < 1e-5)
        #expect(abs(forward.z - 0) < 1e-5)
    }

    @Test("Inverse of identity is identity")
    func inverseIdentity() {
        let inv = Transform.identity.inverse
        #expect(inv.modelMatrix == Mat4.identity)
    }
}
