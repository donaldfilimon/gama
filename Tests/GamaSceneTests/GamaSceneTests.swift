// GamaSceneTests.swift — Tests for GamaScene module
// Part of GamaSceneTests

import Testing
import simd
import GamaMath
@testable import GamaScene

// MARK: - Transform Tests

@Suite("Transform Tests")
struct TransformTests {
    @Test("Identity transform produces identity matrix")
    func identityMatrix() {
        let t = Transform.identity
        let m = t.modelMatrix
        let identity = Mat4.identity
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(m.storage[col][row] - identity.storage[col][row]) < 1e-6)
            }
        }
    }

    @Test("Translation-only transform")
    func translationOnly() {
        let t = Transform(position: Vec3(3, 4, 5))
        let m = t.modelMatrix
        #expect(abs(m.storage.columns.3.x - 3) < 1e-6)
        #expect(abs(m.storage.columns.3.y - 4) < 1e-6)
        #expect(abs(m.storage.columns.3.z - 5) < 1e-6)
    }

    @Test("Scale-only transform")
    func scaleOnly() {
        let t = Transform(scale: Vec3(2, 3, 4))
        let m = t.modelMatrix
        #expect(abs(m.storage.columns.0.x - 2) < 1e-6)
        #expect(abs(m.storage.columns.1.y - 3) < 1e-6)
        #expect(abs(m.storage.columns.2.z - 4) < 1e-6)
    }
}

// MARK: - Node Tests

@Suite("Node Tests")
struct NodeTests {
    @Test("Node default name")
    func defaultName() {
        let node = Node()
        #expect(node.name == "Node")
    }

    @Test("Node stores children")
    func childCount() {
        let child1 = Node(name: "A")
        let child2 = Node(name: "B")
        let parent = Node(name: "Parent", children: [child1, child2])
        #expect(parent.children.count == 2)
    }

    @Test("World transform propagates parent translation")
    func worldTransformPropagation() {
        let childTransform = Transform(position: Vec3(1, 0, 0))
        let child = Node(name: "Child", transform: childTransform)

        let parentTransform = Transform(position: Vec3(0, 5, 0))
        let parent = Node(name: "Parent", transform: parentTransform, children: [child])

        // Traverse and check the child's world position
        var childWorld: Mat4?
        parent.traverse { node, world in
            if node.name == "Child" {
                childWorld = world
            }
        }

        #expect(childWorld != nil)
        if let w = childWorld {
            // Child should be at (1, 5, 0) in world space
            #expect(abs(w.storage.columns.3.x - 1) < 1e-5)
            #expect(abs(w.storage.columns.3.y - 5) < 1e-5)
            #expect(abs(w.storage.columns.3.z - 0) < 1e-5)
        }
    }

    @Test("Nested hierarchy transform accumulation")
    func nestedHierarchy() {
        let grandchild = Node(
            name: "GC",
            transform: Transform(position: Vec3(0, 0, 1))
        )
        let child = Node(
            name: "C",
            transform: Transform(position: Vec3(0, 1, 0)),
            children: [grandchild]
        )
        let root = Node(
            name: "R",
            transform: Transform(position: Vec3(1, 0, 0)),
            children: [child]
        )

        var gcWorld: Mat4?
        root.traverse { node, world in
            if node.name == "GC" {
                gcWorld = world
            }
        }

        #expect(gcWorld != nil)
        if let w = gcWorld {
            #expect(abs(w.storage.columns.3.x - 1) < 1e-5)
            #expect(abs(w.storage.columns.3.y - 1) < 1e-5)
            #expect(abs(w.storage.columns.3.z - 1) < 1e-5)
        }
    }
}

// MARK: - Mesh Tests

@Suite("Mesh Tests")
struct MeshTests {
    @Test("Mesh vertex count matches positions")
    func vertexCount() {
        let mesh = Mesh(positions: [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
        ])
        #expect(mesh.vertexCount == 3)
    }

    @Test("Mesh optional attributes default to nil")
    func optionalDefaults() {
        let mesh = Mesh(positions: [SIMD3<Float>(0, 0, 0)])
        #expect(mesh.normals == nil)
        #expect(mesh.uvs == nil)
        #expect(mesh.indices == nil)
    }
}

// MARK: - Primitive Tests

@Suite("Primitive Tests")
struct PrimitiveTests {
    @Test("Cube has 24 vertices and 36 indices")
    func cubeGeometry() {
        let cube = Mesh.cube(size: 1)
        #expect(cube.vertexCount == 24)
        #expect(cube.indices?.count == 36)
        #expect(cube.normals?.count == 24)
        #expect(cube.uvs?.count == 24)
    }

    @Test("Sphere has correct vertex and index count")
    func sphereGeometry() {
        let segments = 8
        let sphere = Mesh.sphere(radius: 1, segments: segments)
        let expectedVertices = (segments + 1) * (segments + 1)
        #expect(sphere.vertexCount == expectedVertices)
        #expect(sphere.indices != nil)
        #expect(sphere.indices!.count == segments * segments * 6)
        #expect(sphere.normals?.count == expectedVertices)
    }

    @Test("Plane has 4 vertices and 6 indices")
    func planeGeometry() {
        let plane = Mesh.plane(width: 2, height: 3)
        #expect(plane.vertexCount == 4)
        #expect(plane.indices?.count == 6)
        #expect(plane.normals?.count == 4)
        #expect(plane.uvs?.count == 4)
    }

    @Test("Cylinder produces valid geometry")
    func cylinderGeometry() {
        let cyl = Mesh.cylinder(radius: 1, height: 2, segments: 8)
        #expect(cyl.vertexCount > 0)
        #expect(cyl.indices != nil)
        #expect(cyl.indices!.count > 0)
        // All normals should be unit length (approximately)
        if let ns = cyl.normals {
            for n in ns {
                let len = simd_length(n)
                #expect(abs(len - 1.0) < 1e-5)
            }
        }
    }

    @Test("Primitives produce matching normal and position counts")
    func normalPositionParity() {
        let meshes = [
            Mesh.cube(),
            Mesh.sphere(),
            Mesh.plane(),
            Mesh.cylinder(),
        ]
        for mesh in meshes {
            #expect(mesh.normals?.count == mesh.vertexCount)
        }
    }
}

// MARK: - Material Tests

@Suite("Material Tests")
struct MaterialTests {
    @Test("Default material has expected values")
    func defaultMaterial() {
        let m = Material.default
        #expect(m.color == SIMD4<Float>(1, 1, 1, 1))
        #expect(m.roughness == 0.5)
        #expect(m.metallic == 0.0)
        #expect(m.texture == nil)
    }
}

// MARK: - SceneCamera Tests

@Suite("SceneCamera Tests")
struct SceneCameraTests {
    @Test("Default camera has identity matrices")
    func defaultCamera() {
        let cam = SceneCamera()
        let identity = Mat4.identity
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(cam.projectionMatrix.storage[col][row] - identity.storage[col][row]) < 1e-6)
                #expect(abs(cam.viewMatrix.storage[col][row] - identity.storage[col][row]) < 1e-6)
            }
        }
    }

    @Test("Perspective camera produces non-identity projection")
    func perspectiveCamera() {
        let cam = SceneCamera.perspective(
            fovY: Float.pi / 4,
            aspectRatio: 16.0 / 9.0,
            near: 0.1,
            far: 100
        )
        // Should not be identity
        #expect(cam.projectionMatrix.storage[0][0] != 1.0)
        // For Metal-style perspective, column 2 row 3 should be -1
        #expect(abs(cam.projectionMatrix.storage[2][3] - (-1)) < 1e-6)
    }

    @Test("Perspective camera uses Metal [0,1] depth range")
    func perspectiveMetalDepth() {
        let cam = SceneCamera.perspective(
            fovY: Float.pi / 4,
            aspectRatio: 1.0,
            near: 0.1,
            far: 100
        )
        // In Metal-style perspective, z maps to [0,1] not [-1,1].
        // Column 2, row 2 should be far/(near-far) which is negative
        // Column 3, row 2 should be (far*near)/(near-far) which is also negative
        let z22 = cam.projectionMatrix.storage[2][2]
        let z32 = cam.projectionMatrix.storage[3][2]
        // For Metal [0,1]: z22 = far/(near-far), z32 = near*far/(near-far)
        let expectedZ22: Float = 100.0 / (0.1 - 100.0)
        let expectedZ32: Float = (0.1 * 100.0) / (0.1 - 100.0)
        #expect(abs(z22 - expectedZ22) < 1e-4)
        #expect(abs(z32 - expectedZ32) < 1e-4)
    }

    @Test("Orthographic camera preserves parallel projection")
    func orthographicCamera() {
        let cam = SceneCamera.orthographic(
            left: -1, right: 1,
            bottom: -1, top: 1,
            near: 0.1, far: 10
        )
        // Last column, last row should be 1 for orthographic
        #expect(abs(cam.projectionMatrix.storage[3][3] - 1) < 1e-6)
    }
}

// MARK: - Scene Tests

@Suite("Scene Tests")
struct SceneTests {
    @Test("Scene default initialization")
    func defaultScene() {
        let scene = Scene()
        #expect(scene.rootNode.name == "Root")
        #expect(scene.backgroundColor.r == 0)
        #expect(scene.backgroundColor.a == 1)
    }
}
