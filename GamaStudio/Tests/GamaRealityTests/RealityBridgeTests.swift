import AppKit
import GamaAuthoring
import GamaReality
import RealityKit
import Testing

@MainActor
@Suite("Bridge convergence")
struct BridgeConvergenceTests {
    /// Seeds × drain cadence. Draining after every step checks single-change
    /// batches; draining every 7 steps checks long, mixed batches that include
    /// churn (created then deleted, deleted then restored) inside one batch.
    nonisolated static let runs: [(seed: UInt64, drainEvery: Int)] = [
        (1, 1), (2, 1), (3, 1), (42, 1), (1, 7), (2, 7), (1337, 7), (9001, 13),
    ]

    @Test(arguments: 0..<runs.count)
    func incrementalProjectionMatchesRebuild(_ run: Int) throws {
        let (seed, drainEvery) = Self.runs[run]
        var rng = SeededGenerator(seed: seed)
        var scene = try SampleScene()
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        _ = scene.session.drainChanges()

        var applied = 0
        for step in 1...300 {
            switch rng.below(12) {
            case 0: _ = try? scene.session.undo()
            case 1: _ = try? scene.session.redo()
            case 2:
                let commands = (0..<(2 + rng.below(3))).map { _ in randomCommand(&rng, scene.session.document) }
                _ = try? scene.session.transaction("Batch", commands)
            default:
                if (try? scene.session.execute(randomCommand(&rng, scene.session.document))) != nil {
                    applied += 1
                }
            }
            guard step % drainEvery == 0 else { continue }
            bridge.apply(scene.session.drainChanges(), from: scene.session.document)

            let reference = RealityBridge()
            reference.rebuild(from: scene.session.document)
            let got = snapshot(bridge), want = snapshot(reference)
            try #require(got == want, "seed \(seed) step \(step): \(got) != \(want)")
            #expect(bridge.count == scene.session.document.count)
        }
        #expect(applied > 100, "generator mostly produced refused commands")
    }
}

@MainActor
@Suite("Bridge incrementality")
struct BridgeIncrementalityTests {
    private func projected() throws -> (SampleScene, RealityBridge) {
        var scene = try SampleScene()
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        _ = scene.session.drainChanges()
        return (scene, bridge)
    }

    private func identities(_ bridge: RealityBridge, _ ids: [EntityID]) -> [ObjectIdentifier?] {
        ids.map { bridge.entity(for: $0).map(ObjectIdentifier.init) }
    }

    @Test func editsKeepEveryEntityObject() throws {
        var (scene, bridge) = try projected()
        let all = scene.session.document.entities.keys.sorted()
        let before = identities(bridge, all)
        try scene.session.execute(SetComponent(scene.body, .transform(Transform(position: SIMD3(2.5, 0, 0)))))
        try scene.session.execute(RenameEntity(scene.hair, to: "Bun"))
        try scene.session.execute(ReparentEntity(scene.hair, to: scene.ground))
        try scene.session.execute(RemoveComponent(scene.body, .mesh))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        #expect(identities(bridge, all) == before)
        #expect(bridge.entity(for: scene.body)?.position == SIMD3(2.5, 0, 0))
        #expect(bridge.entity(for: scene.hair)?.parent === bridge.entity(for: scene.ground))
        #expect(bridge.entity(for: scene.hair)?.name == "Bun")
    }

    @Test func createThenDeleteInOneBatchLeavesNothing() throws {
        var (scene, bridge) = try projected()
        let id = scene.session.document.nextEntityID
        try scene.session.execute(CreateEntity(name: "Temp", parent: scene.world, components: [.mesh(.cone)]))
        try scene.session.execute(DeleteEntity(id))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        #expect(bridge.entity(for: id) == nil)
        #expect(bridge.count == 6)
    }

    @Test func deleteThenUndoInOneBatchRestoresTheSameIdentity() throws {
        var (scene, bridge) = try projected()
        try scene.session.execute(DeleteEntity(scene.character))
        try scene.session.undo()
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        let restored = try #require(bridge.entity(for: scene.hair))
        #expect(bridge.id(for: restored) == scene.hair)
        #expect(restored.parent === bridge.entity(for: scene.character))
        #expect(bridge.count == 6)
    }
}

@MainActor
@Suite("Bridge mapping")
struct BridgeMappingTests {
    @Test(arguments: Primitive.allCases)
    func everyPrimitiveProjectsAUnitSizedModel(_ primitive: Primitive) throws {
        var session = EditorSession()
        let id = session.document.nextEntityID
        try session.execute(CreateEntity(name: "P", components: [.mesh(primitive)]))
        let bridge = RealityBridge()
        bridge.rebuild(from: session.document)
        let model = try #require(bridge.entity(for: id)?.components[ModelComponent.self])
        let extents = model.mesh.bounds.extents
        #expect(abs(max(extents.x, extents.y, extents.z) - 1) < 0.01)
    }

    @Test(arguments: Primitive.allCases)
    func everyPrimitiveProjectsMatchingCollision(_ primitive: Primitive) throws {
        var session = EditorSession()
        let id = session.document.nextEntityID
        try session.execute(CreateEntity(name: "P", components: [.mesh(primitive)]))
        let bridge = RealityBridge()
        bridge.rebuild(from: session.document)
        _ = session.drainChanges()

        let entity = try #require(bridge.entity(for: id))
        #expect(entity.components.has(ModelComponent.self))
        #expect(entity.components.has(CollisionComponent.self))

        try session.execute(RemoveComponent(id, .mesh))
        bridge.apply(session.drainChanges(), from: session.document)
        #expect(entity.components.has(ModelComponent.self) == false)
        #expect(entity.components.has(CollisionComponent.self) == false)

        try session.execute(SetComponent(id, .mesh(primitive)))
        bridge.apply(session.drainChanges(), from: session.document)
        #expect(entity.components.has(ModelComponent.self))
        #expect(entity.components.has(CollisionComponent.self))
    }

    @Test func pickingRoundTrips() throws {
        let scene = try SampleScene()
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        for id in scene.session.document.entities.keys {
            let entity = try #require(bridge.entity(for: id))
            #expect(bridge.id(for: entity) == id)
        }
        #expect(bridge.id(for: bridge.root) == nil)
        #expect(bridge.id(for: Entity()) == nil)
    }

    @Test func visibilityMeshAndMaterialProjection() throws {
        var scene = try SampleScene()
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        _ = scene.session.drainChanges()

        try scene.session.execute(SetComponent(scene.body, .visibility(Visibility(visible: false))))
        try scene.session.execute(SetComponent(scene.body, .material(Material(baseColor: SIMD4(1, 0, 0, 1), metallic: 0.9, roughness: 0.1))))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        let body = try #require(bridge.entity(for: scene.body))
        #expect(body.isEnabled == false)
        let material = try #require(body.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial)
        #expect(material.metallic.scale == 0.9)
        #expect(material.roughness.scale == 0.1)

        // Authored colors are linear. Pure red reads the same in linear and
        // gamma-encoded spaces, so a mid-grey is what pins the colour space.
        try scene.session.execute(SetComponent(scene.body, .material(Material(baseColor: SIMD4(0.5, 0.5, 0.5, 1)))))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        let grey = try #require(body.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial)
        let linearSpace = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB).flatMap(NSColorSpace.init(cgColorSpace:)))
        let linear = try #require(grey.baseColor.tint.usingColorSpace(linearSpace))
        #expect(abs(linear.redComponent - 0.5) < 0.01, "tint was \(linear.redComponent) in linear sRGB")

        try scene.session.execute(RemoveComponent(scene.body, .mesh))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        #expect(body.components.has(ModelComponent.self) == false)

        try scene.session.execute(RemoveComponent(scene.body, .visibility))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        #expect(body.isEnabled)
    }

    @Test func siblingOrderFollowsTheDocument() throws {
        var scene = try SampleScene()
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        _ = scene.session.drainChanges()
        try scene.session.execute(ReparentEntity(scene.hair, to: scene.character, at: 0))
        try scene.session.execute(ReparentEntity(scene.camera, to: nil, at: 0))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        let character = try #require(bridge.entity(for: scene.character))
        #expect(character.children.map { bridge.id(for: $0) } == [scene.hair, scene.body])
        #expect(bridge.root.children.map { bridge.id(for: $0) } == [scene.camera, scene.world])
    }

    @Test func rebuildReplacesAPreviousProjection() throws {
        let scene = try SampleScene()
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        let stale = try #require(bridge.entity(for: scene.body))
        bridge.rebuild(from: SceneDocument())
        #expect(bridge.count == 0)
        #expect(bridge.root.children.isEmpty)
        #expect(bridge.id(for: stale) == nil)
    }
}
