// Mat4Tests.swift — Tests for Mat4 matrix operations
// Part of GamaMathTests

import Testing
@testable import GamaMath

@Suite("Mat4 Tests")
struct Mat4Tests {
    @Test("Identity matrix multiplied by identity gives identity")
    func identityMultiply() {
        let result = Mat4.identity * Mat4.identity
        #expect(result == Mat4.identity)
    }

    @Test("Identity matrix has determinant 1")
    func identityDeterminant() {
        #expect(abs(Mat4.identity.determinant - 1.0) < 1e-6)
    }

    @Test("Identity transforms a point without change")
    func identityTransformPoint() {
        let p = Vec3(1, 2, 3)
        let result = Mat4.identity.transformPoint(p)
        #expect(abs(result.x - 1) < 1e-6)
        #expect(abs(result.y - 2) < 1e-6)
        #expect(abs(result.z - 3) < 1e-6)
    }

    @Test("Translation matrix moves a point")
    func translationPoint() {
        let t = Mat4.translation(Vec3(10, 20, 30))
        let result = t.transformPoint(.zero)
        #expect(abs(result.x - 10) < 1e-6)
        #expect(abs(result.y - 20) < 1e-6)
        #expect(abs(result.z - 30) < 1e-6)
    }

    @Test("Translation does not affect directions")
    func translationDirection() {
        let t = Mat4.translation(Vec3(10, 20, 30))
        let dir = Vec3(1, 0, 0)
        let result = t.transformDirection(dir)
        #expect(abs(result.x - 1) < 1e-6)
        #expect(abs(result.y - 0) < 1e-6)
        #expect(abs(result.z - 0) < 1e-6)
    }

    @Test("Scale matrix scales a point")
    func scalePoint() {
        let s = Mat4.scale(Vec3(2, 3, 4))
        let result = s.transformPoint(Vec3(1, 1, 1))
        #expect(abs(result.x - 2) < 1e-6)
        #expect(abs(result.y - 3) < 1e-6)
        #expect(abs(result.z - 4) < 1e-6)
    }

    @Test("Rotation by 0 is identity")
    func rotationZero() {
        let r = Mat4.rotation(axis: .unitY, angle: 0)
        let result = r.transformPoint(Vec3(1, 0, 0))
        #expect(abs(result.x - 1) < 1e-6)
        #expect(abs(result.y - 0) < 1e-6)
        #expect(abs(result.z - 0) < 1e-6)
    }

    @Test("90-degree rotation around Y moves X to -Z")
    func rotation90Y() {
        let r = Mat4.rotationY(.pi / 2)
        let result = r.transformPoint(Vec3(1, 0, 0))
        #expect(abs(result.x - 0) < 1e-5)
        #expect(abs(result.y - 0) < 1e-5)
        #expect(abs(result.z - (-1)) < 1e-5)
    }

    @Test("Matrix inverse times original gives identity")
    func inverseTimesOriginal() {
        let t = Mat4.translation(Vec3(5, -3, 7))
        let r = Mat4.rotationZ(0.7)
        let m = t * r
        let result = m * m.inverse

        for col in 0..<4 {
            for row in 0..<4 {
                let expected: Float = (col == row) ? 1.0 : 0.0
                #expect(abs(result.storage[col][row] - expected) < 1e-4)
            }
        }
    }

    @Test("Transpose of identity is identity")
    func transposeIdentity() {
        #expect(Mat4.identity.transpose == Mat4.identity)
    }

    @Test("Composition: translate then scale")
    func composition() {
        let t = Mat4.translation(Vec3(1, 0, 0))
        let s = Mat4.scale(2.0)
        // Scale first, then translate: T * S
        let m = t * s
        let result = m.transformPoint(.zero)
        // zero scaled is zero, then translated by (1,0,0)
        #expect(abs(result.x - 1) < 1e-6)
        #expect(abs(result.y - 0) < 1e-6)
        #expect(abs(result.z - 0) < 1e-6)
    }

    @Test("Matrix-vector multiplication")
    func matVecMultiply() {
        let t = Mat4.translation(Vec3(1, 2, 3))
        let v = Vec4(0, 0, 0, 1)
        let result = t * v
        #expect(abs(result.x - 1) < 1e-6)
        #expect(abs(result.y - 2) < 1e-6)
        #expect(abs(result.z - 3) < 1e-6)
        #expect(abs(result.w - 1) < 1e-6)
    }
}
