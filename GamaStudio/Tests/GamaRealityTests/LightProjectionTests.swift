import AppKit
import GamaAuthoring
import GamaReality
import RealityKit
import Testing

@MainActor
@Suite("Light and camera projection")
struct LightProjectionTests {
    nonisolated static let kinds: [LightKind] = [
        .directional,
        .point(attenuationRadius: 7),
        .spot(innerAngleDegrees: 20, outerAngleDegrees: 35, attenuationRadius: 12),
    ]

    private func session(with components: [GamaAuthoring.Component]) throws -> (EditorSession, EntityID, RealityBridge) {
        var session = EditorSession()
        let id = session.document.nextEntityID
        try session.execute(CreateEntity(name: "L", components: components))
        let bridge = RealityBridge()
        bridge.rebuild(from: session.document)
        _ = session.drainChanges()
        return (session, id, bridge)
    }

    private func expectedKind(_ kind: LightKind) -> LightSnapshot.Kind {
        switch kind {
        case .directional: .directional
        case .point: .point
        case .spot: .spot
        }
    }

    @Test(arguments: 0..<kinds.count)
    func eachLightKindProjectsExactlyOneLightComponent(_ index: Int) throws {
        let kind = Self.kinds[index]
        let light = Light(kind: kind, color: SIMD3(0.5, 0.5, 0.5), intensity: 1234)
        let (_, id, bridge) = try session(with: [.light(light)])
        let entity = try #require(bridge.entity(for: id))
        let lights = lightSnapshots(entity)
        try #require(lights.count == 1, "got \(lights)")
        let projected = lights[0]
        #expect(projected.kind == expectedKind(kind))
        #expect(projected.intensity == 1234)
        switch kind {
        case .directional:
            break
        case .point(let radius):
            #expect(projected.attenuationRadius == radius)
        case .spot(let inner, let outer, let radius):
            // RealityKit round-trips degrees through radians, so allow float slop.
            #expect(abs((projected.innerAngle ?? 0) - inner) < 0.001)
            #expect(abs((projected.outerAngle ?? 0) - outer) < 0.001)
            #expect(projected.attenuationRadius == radius)
        }
        // The authored color is linear: a linear 0.5 grey is sRGB-encoded,
        // and reads back as 0.5 in linear sRGB.
        let color: NSColor = switch kind {
        case .directional: try #require(entity.components[DirectionalLightComponent.self]).color
        case .point: try #require(entity.components[PointLightComponent.self]).color
        case .spot: try #require(entity.components[SpotLightComponent.self]).color
        }
        let linearSpace = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB).flatMap(NSColorSpace.init(cgColorSpace:)))
        let linear = try #require(color.usingColorSpace(linearSpace))
        #expect(abs(linear.redComponent - 0.5) < 0.01, "light color was \(linear.redComponent) in linear sRGB")
    }

    @Test func aKindChangeSwapsTheLightComponent() throws {
        var (session, id, bridge) = try session(with: [.light(.defaultPoint)])
        let entity = try #require(bridge.entity(for: id))
        #expect(lightSnapshots(entity).map(\.kind) == [.point])

        try session.execute(SetComponent(id, .light(Light(kind: Self.kinds[2], intensity: 10))))
        bridge.apply(session.drainChanges(), from: session.document)
        #expect(lightSnapshots(entity).map(\.kind) == [.spot])

        try session.execute(SetComponent(id, .light(.defaultDirectional)))
        bridge.apply(session.drainChanges(), from: session.document)
        #expect(lightSnapshots(entity).map(\.kind) == [.directional])
        #expect(bridge.entity(for: id) === entity)
    }

    @Test(arguments: 0..<kinds.count)
    func removingTheLightClearsTheComponentAndTheMarker(_ index: Int) throws {
        var (session, id, bridge) = try session(with: [.light(Light(kind: Self.kinds[index], intensity: 100))])
        let entity = try #require(bridge.entity(for: id))
        #expect(marker(of: entity, in: bridge) != nil)

        try session.execute(RemoveComponent(id, .light))
        bridge.apply(session.drainChanges(), from: session.document)
        #expect(lightSnapshots(entity).isEmpty)
        #expect(marker(of: entity, in: bridge) == nil)
        #expect(entity.children.isEmpty)
    }

    @Test func aCameraNeverGetsARealityKitCameraComponent() throws {
        var scene = try SampleScene()
        for id in scene.session.document.entities.keys.sorted() {
            try scene.session.execute(SetComponent(id, .camera(.default)))
        }
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        let incremental = RealityBridge()
        incremental.rebuild(from: SceneDocument())
        incremental.apply(scene.session.drainChanges(), from: scene.session.document)

        for projection in [bridge, incremental] {
            var pending = [projection.root]
            var visited = 0
            while let entity = pending.popLast() {
                visited += 1
                #expect(entity.components.has(PerspectiveCameraComponent.self) == false, "\(entity.name)")
                pending.append(contentsOf: entity.children)
            }
            // Six entities, six markers, and the root.
            #expect(visited == 13)
            #expect(projection.count == 6)
        }
    }

    @Test func aCameraGetsABoxMarkerAndWinsOverALight() throws {
        var (session, id, bridge) = try session(with: [.camera(.default)])
        let entity = try #require(bridge.entity(for: id))
        let cameraMarker = try #require(marker(of: entity, in: bridge))
        let extents = try #require(cameraMarker.components[ModelComponent.self]).mesh.bounds.extents
        #expect(abs(extents.x - 0.2) < 0.001 && abs(extents.y - 0.15) < 0.001 && abs(extents.z - 0.3) < 0.001)
        #expect(cameraMarker.components[ModelComponent.self]?.materials.first is UnlitMaterial)

        try session.execute(SetComponent(id, .light(.defaultPoint)))
        bridge.apply(session.drainChanges(), from: session.document)
        let both = entity.children.filter { $0.name == "GamaReality.marker" }
        #expect(both.count == 1)
        let bothExtents = try #require(both.first?.components[ModelComponent.self]).mesh.bounds.extents
        #expect(abs(bothExtents.z - 0.3) < 0.001, "the camera marker should win")

        try session.execute(RemoveComponent(id, .camera))
        bridge.apply(session.drainChanges(), from: session.document)
        let lightMarker = try #require(marker(of: entity, in: bridge))
        let sphere = try #require(lightMarker.components[ModelComponent.self]).mesh.bounds.extents
        #expect(abs(sphere.x - 0.2) < 0.001 && abs(sphere.z - 0.2) < 0.001)
        #expect(entity.children.count == 1)
    }

    @Test func aBlackLightMarkerStaysVisible() throws {
        let (_, id, bridge) = try session(with: [.light(Light(kind: .directional, color: SIMD3(0, 0, 0), intensity: 1))])
        let entity = try #require(bridge.entity(for: id))
        let lightMarker = try #require(marker(of: entity, in: bridge))
        let material = try #require(lightMarker.components[ModelComponent.self]?.materials.first as? UnlitMaterial)
        let tint = try #require(srgbComponents(material.color.tint))
        #expect(tint[0...2].max()! > 0.3, "marker tint \(tint) is too dark to see")
    }

    @Test func aMarkerIsPickedAsItsOwnerAndNeverMapped() throws {
        let (session, id, bridge) = try session(with: [.light(.defaultPoint)])
        let entity = try #require(bridge.entity(for: id))
        let lightMarker = try #require(marker(of: entity, in: bridge))
        #expect(lightMarker.components.has(CollisionComponent.self))
        #expect(bridge.id(for: lightMarker) == nil)
        #expect(pickedEntityID(for: lightMarker, in: bridge) == id)
        #expect(bridge.count == session.document.count)
    }

    @Test func aMarkerInheritsItsOwnersVisibility() throws {
        var (session, id, bridge) = try session(with: [.camera(.default)])
        let entity = try #require(bridge.entity(for: id))
        let cameraMarker = try #require(marker(of: entity, in: bridge))
        try session.execute(SetComponent(id, .visibility(Visibility(visible: false))))
        bridge.apply(session.drainChanges(), from: session.document)
        #expect(cameraMarker.isEnabledInHierarchy == false)
    }

    @Test func markersStayAfterMappedChildrenAcrossResequencing() throws {
        var scene = try SampleScene()
        let bridge = RealityBridge()
        bridge.rebuild(from: scene.session.document)
        _ = scene.session.drainChanges()

        try scene.session.execute(SetComponent(scene.character, .light(.defaultPoint)))
        try scene.session.execute(ReparentEntity(scene.hair, to: scene.character, at: 0))
        try scene.session.execute(ReparentEntity(scene.ground, to: scene.character, at: 1))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        let character = try #require(bridge.entity(for: scene.character))
        #expect(character.children.map { bridge.id(for: $0) } == [scene.hair, scene.ground, scene.body, nil])
        #expect(Array(character.children).last?.name == "GamaReality.marker")

        try scene.session.execute(DeleteEntity(scene.hair))
        bridge.apply(scene.session.drainChanges(), from: scene.session.document)
        #expect(character.children.map { bridge.id(for: $0) } == [scene.ground, scene.body, nil])

        let reference = RealityBridge()
        reference.rebuild(from: scene.session.document)
        #expect(snapshot(bridge) == snapshot(reference))
    }
}
