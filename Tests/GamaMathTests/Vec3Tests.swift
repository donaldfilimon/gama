// Vec3Tests.swift — Tests for Vec3 math operations
// Part of GamaMathTests

import Testing
@testable import GamaMath

@Suite("Vec3 Tests")
struct Vec3Tests {
    @Test("Zero vector has all zero components")
    func zero() {
        let v = Vec3.zero
        #expect(v.x == 0)
        #expect(v.y == 0)
        #expect(v.z == 0)
    }

    @Test("Component initializer")
    func components() {
        let v = Vec3(1, 2, 3)
        #expect(v.x == 1)
        #expect(v.y == 2)
        #expect(v.z == 3)
    }

    @Test("Addition")
    func addition() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(4, 5, 6)
        let c = a + b
        #expect(c.x == 5)
        #expect(c.y == 7)
        #expect(c.z == 9)
    }

    @Test("Subtraction")
    func subtraction() {
        let a = Vec3(4, 5, 6)
        let b = Vec3(1, 2, 3)
        let c = a - b
        #expect(c.x == 3)
        #expect(c.y == 3)
        #expect(c.z == 3)
    }

    @Test("Scalar multiplication")
    func scalarMultiply() {
        let v = Vec3(1, 2, 3) * 2
        #expect(v.x == 2)
        #expect(v.y == 4)
        #expect(v.z == 6)
    }

    @Test("Negation")
    func negation() {
        let v = -Vec3(1, -2, 3)
        #expect(v.x == -1)
        #expect(v.y == 2)
        #expect(v.z == -3)
    }

    @Test("Length of unit vector is 1")
    func unitLength() {
        let v = Vec3.unitX
        #expect(abs(v.length - 1.0) < 1e-6)
    }

    @Test("Normalization produces unit length")
    func normalization() {
        let v = Vec3(3, 4, 0).normalized
        #expect(abs(v.length - 1.0) < 1e-6)
    }

    @Test("Dot product")
    func dotProduct() {
        let a = Vec3(1, 0, 0)
        let b = Vec3(0, 1, 0)
        #expect(Vec3.dot(a, b) == 0)
        #expect(Vec3.dot(a, a) == 1)
    }

    @Test("Cross product of x and y gives z")
    func crossProduct() {
        let c = Vec3.cross(.unitX, .unitY)
        #expect(abs(c.x - 0) < 1e-6)
        #expect(abs(c.y - 0) < 1e-6)
        #expect(abs(c.z - 1) < 1e-6)
    }

    @Test("Swizzle xy returns correct Vec2")
    func swizzle() {
        let v = Vec3(1, 2, 3)
        let xy = v.xy
        #expect(xy.x == 1)
        #expect(xy.y == 2)
    }

    @Test("Lerp at t=0 returns start, t=1 returns end")
    func lerp() {
        let a = Vec3(0, 0, 0)
        let b = Vec3(10, 20, 30)
        let mid = Vec3.lerp(a, b, t: 0.5)
        #expect(abs(mid.x - 5) < 1e-6)
        #expect(abs(mid.y - 10) < 1e-6)
        #expect(abs(mid.z - 15) < 1e-6)
    }

    @Test("Distance between two points")
    func distance() {
        let a = Vec3(0, 0, 0)
        let b = Vec3(3, 4, 0)
        #expect(abs(Vec3.distance(a, b) - 5) < 1e-6)
    }
}
