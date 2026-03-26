// CameraTests.swift — Tests for Camera projection and view matrices
// Part of GamaMathTests

import Testing
@testable import GamaMath

@Suite("Camera Tests")
struct CameraTests {
    @Test("Perspective projection matrix has correct near-plane mapping")
    func perspectiveNearPlane() {
        let proj = Camera.perspectiveProjection(
            fovY: .pi / 2,   // 90 degrees
            aspect: 1.0,
            near: 0.1,
            far: 100.0
        )
        // A point at the near plane center should map to z = 0 in clip space (Metal convention)
        let nearPoint = proj * Vec4(0, 0, -0.1, 1)
        let ndcZ = nearPoint.z / nearPoint.w
        #expect(abs(ndcZ - 0) < 1e-4)
    }

    @Test("Perspective projection matrix has correct far-plane mapping")
    func perspectiveFarPlane() {
        let proj = Camera.perspectiveProjection(
            fovY: .pi / 2,
            aspect: 1.0,
            near: 0.1,
            far: 100.0
        )
        // A point at the far plane should map to z = 1 in clip space (Metal convention)
        let farPoint = proj * Vec4(0, 0, -100, 1)
        let ndcZ = farPoint.z / farPoint.w
        #expect(abs(ndcZ - 1) < 1e-3)
    }

    @Test("Perspective projection preserves aspect ratio")
    func perspectiveAspect() {
        let proj = Camera.perspectiveProjection(
            fovY: .pi / 4,
            aspect: 2.0,
            near: 0.1,
            far: 100.0
        )
        // The x scale should be half the y scale for aspect 2:1
        let xScale = proj.storage[0][0]
        let yScale = proj.storage[1][1]
        #expect(abs(xScale - yScale / 2.0) < 1e-6)
    }

    @Test("Orthographic projection maps center to origin")
    func orthographicCenter() {
        let proj = Camera.orthographicProjection(
            left: -10, right: 10,
            bottom: -5, top: 5,
            near: 0.1, far: 100.0
        )
        // Center of the view volume should map to (0, 0, ...)
        let center = proj * Vec4(0, 0, -50, 1)
        #expect(abs(center.x / center.w) < 1e-4)
        #expect(abs(center.y / center.w) < 1e-4)
    }

    @Test("LookAt from origin along -Z produces near-identity view")
    func lookAtAlongNegZ() {
        let view = Camera.lookAt(
            eye: Vec3(0, 0, 0),
            target: Vec3(0, 0, -1),
            up: Vec3(0, 1, 0)
        )
        // The view matrix should be close to identity when looking along -Z from origin
        for col in 0..<4 {
            for row in 0..<4 {
                let expected: Float = (col == row) ? 1.0 : 0.0
                #expect(abs(view.storage[col][row] - expected) < 1e-5)
            }
        }
    }

    @Test("LookAt translates eye position")
    func lookAtTranslation() {
        let view = Camera.lookAt(
            eye: Vec3(0, 5, 10),
            target: Vec3(0, 0, 0),
            up: Vec3(0, 1, 0)
        )
        // Transforming the eye position should give the origin in view space
        let eyeInView = view * Vec4(0, 5, 10, 1)
        #expect(abs(eyeInView.x) < 1e-4)
        #expect(abs(eyeInView.y) < 1e-4)
        #expect(abs(eyeInView.z) < 1e-4)
    }
}
