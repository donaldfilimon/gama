import AppKit
import GamaAuthoring
import GamaReality
import RealityKit

/// A comparable description of a projected tree: structure, identity, and
/// every projected property. Markers appear as unmapped child nodes named
/// `GamaReality.marker`, carrying their mesh extents and unlit tint. Two bridges showing the same document must
/// produce equal snapshots.
struct NodeSnapshot: Equatable, CustomStringConvertible {
    var id: EntityID?
    var name: String
    var matrix: [Float]
    var enabled: Bool
    var hasCollision: Bool
    var meshExtents: [Float]?
    var metallic: Float?
    var roughness: Float?
    var tint: [Float]?
    /// The tint of an `UnlitMaterial` model (markers use one).
    var unlitTint: [Float]?
    /// One entry per RealityKit light component present, so a stale second
    /// light component cannot hide behind the first.
    var lights: [LightSnapshot]
    var hasCameraComponent: Bool
    var children: [NodeSnapshot]

    var description: String {
        let kids = children.map(\.description).joined(separator: ", ")
        return "\(id.map(\.description) ?? "root")\(name.isEmpty ? "" : ":\(name)")[\(kids)]"
    }
}

@MainActor
func snapshot(_ bridge: RealityBridge) -> NodeSnapshot {
    snapshot(bridge.root, in: bridge)
}

@MainActor
private func snapshot(_ entity: Entity, in bridge: RealityBridge) -> NodeSnapshot {
    let m = entity.transform.matrix
    var node = NodeSnapshot(
        id: bridge.id(for: entity),
        name: entity.name,
        matrix: [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] },
        enabled: entity.isEnabled,
        hasCollision: entity.components.has(CollisionComponent.self),
        lights: lightSnapshots(entity),
        hasCameraComponent: entity.components.has(PerspectiveCameraComponent.self),
        children: entity.children.map { snapshot($0, in: bridge) }
    )
    if let model = entity.components[ModelComponent.self] {
        let extents = model.mesh.bounds.extents
        node.meshExtents = [extents.x, extents.y, extents.z]
        if let material = model.materials.first as? PhysicallyBasedMaterial {
            node.metallic = material.metallic.scale
            node.roughness = material.roughness.scale
            if let tint = material.baseColor.tint.usingColorSpace(.sRGB) {
                node.tint = srgbComponents(tint)
            }
        }
        if let material = model.materials.first as? UnlitMaterial {
            node.unlitTint = srgbComponents(material.color.tint)
        }
    }
    return node
}

/// A projected RealityKit light component, read back for comparison.
struct LightSnapshot: Equatable {
    enum Kind: Equatable { case directional, point, spot }
    var kind: Kind
    /// sRGB-encoded components as RealityKit holds them.
    var color: [Float]?
    var intensity: Float
    var innerAngle: Float?
    var outerAngle: Float?
    var attenuationRadius: Float?
}

@MainActor
func lightSnapshots(_ entity: Entity) -> [LightSnapshot] {
    var lights: [LightSnapshot] = []
    if let light = entity.components[DirectionalLightComponent.self] {
        lights.append(LightSnapshot(kind: .directional, color: srgbComponents(light.color), intensity: light.intensity))
    }
    if let light = entity.components[PointLightComponent.self] {
        lights.append(LightSnapshot(kind: .point, color: srgbComponents(light.color), intensity: light.intensity,
                                    attenuationRadius: light.attenuationRadius))
    }
    if let light = entity.components[SpotLightComponent.self] {
        lights.append(LightSnapshot(kind: .spot, color: srgbComponents(light.color), intensity: light.intensity,
                                    innerAngle: light.innerAngleInDegrees, outerAngle: light.outerAngleInDegrees,
                                    attenuationRadius: light.attenuationRadius))
    }
    return lights
}

func srgbComponents(_ color: NSColor) -> [Float]? {
    guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
    return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent].map { Float($0) }
}

/// The marker child the bridge hangs under a camera or light entity.
@MainActor
func marker(of entity: Entity, in bridge: RealityBridge) -> Entity? {
    let markers = entity.children.filter { $0.name == "GamaReality.marker" && bridge.id(for: $0) == nil }
    return markers.first
}

/// The Studio viewport's picking rule (`ViewportController.pickedEntityID`),
/// copied so this target does not depend on the editor: walk up from the hit
/// entity to the first one the bridge maps.
@MainActor
func pickedEntityID(for entity: Entity?, in bridge: RealityBridge) -> EntityID? {
    var current = entity
    while let candidate = current {
        if let id = bridge.id(for: candidate) { return id }
        current = candidate.parent
    }
    return nil
}

/// The sample scene from the authoring tests:
/// `World > [Ground, Character > [Body, Hair]]` plus a root `Camera`.
struct SampleScene {
    var session = EditorSession()
    var world = EntityID(rawValue: 1)
    var ground = EntityID(rawValue: 2)
    var character = EntityID(rawValue: 3)
    var body = EntityID(rawValue: 4)
    var hair = EntityID(rawValue: 5)
    var camera = EntityID(rawValue: 6)

    init() throws {
        try session.execute(CreateEntity(name: "World"))
        try session.execute(CreateEntity(name: "Ground", parent: world, components: [.transform(.identity), .mesh(.plane)]))
        try session.execute(CreateEntity(name: "Character", parent: world))
        try session.execute(CreateEntity(name: "Body", parent: character, components: [.transform(.identity), .mesh(.box), .material(Material(metallic: 0.3))]))
        try session.execute(CreateEntity(name: "Hair", parent: character, components: [.transform(.identity), .mesh(.sphere)]))
        try session.execute(CreateEntity(name: "Camera"))
    }
}

/// A small deterministic generator (SplitMix64), so every failure replays.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }

    mutating func unit() -> Float { Float(next() % 1001) / 1000 }

    mutating func pick<T>(_ items: [T]) -> T? {
        items.isEmpty ? nil : items[below(items.count)]
    }
}

/// Produces a random but valid-looking command against the current document.
/// Some commands are refused by the session (cycles, bad indices); callers
/// skip those, exactly as an editor would.
func randomCommand(_ rng: inout SeededGenerator, _ document: SceneDocument) -> any DocumentCommand {
    let ids = document.entities.keys.sorted()
    let target = rng.pick(ids) ?? EntityID(rawValue: 1)
    switch rng.below(11) {
    case 0:
        let parent = rng.below(3) == 0 ? nil : rng.pick(ids)
        let count = document.children(of: parent).count
        let index = rng.below(2) == 0 ? nil : rng.below(count + 1)
        let primitive = Primitive.allCases[rng.below(Primitive.allCases.count)]
        return CreateEntity(name: "E\(rng.below(100))", parent: parent, index: index,
                            components: [.transform(.identity), .mesh(primitive)])
    case 1:
        return DeleteEntity(target)
    case 2:
        // Duplicating a large subtree roughly doubles the tree; cap growth so
        // the test stays about the bridge, not about entity volume.
        guard document.count < 60 else { return DeleteEntity(target) }
        return DuplicateEntity(target)
    case 3:
        return RenameEntity(target, to: "R\(rng.below(100))")
    case 4:
        let angle = rng.unit() * 3
        let rotation = Rotation(x: 0, y: sin(angle / 2), z: 0, w: cos(angle / 2))
        return SetComponent(target, .transform(Transform(
            position: SIMD3(rng.unit() * 4 - 2, rng.unit(), rng.unit() * 4 - 2),
            rotation: rotation.normalized,
            scale: SIMD3(repeating: 0.5 + rng.unit())
        )))
    case 5:
        return SetComponent(target, .material(Material(
            baseColor: SIMD4(rng.unit(), rng.unit(), rng.unit(), 1),
            metallic: rng.unit(),
            roughness: rng.unit()
        )))
    case 6:
        return RemoveComponent(target, ComponentKind.allCases[rng.below(ComponentKind.allCases.count)])
    case 7:
        return SetComponent(target, .visibility(Visibility(visible: rng.below(3) != 0)))
    case 8:
        return SetComponent(target, .light(randomLight(&rng)))
    case 9:
        return SetComponent(target, .camera(CameraSettings(
            fieldOfViewDegrees: 20 + rng.unit() * 100,
            near: 0.01 + rng.unit(),
            far: 10 + rng.unit() * 1000
        )))
    default:
        let parent = rng.below(3) == 0 ? nil : rng.pick(ids)
        let count = document.children(of: parent).count
        return ReparentEntity(target, to: parent, at: rng.below(2) == 0 ? nil : rng.below(count + 1))
    }
}

/// A valid light of any of the three kinds, with a random color (including
/// black, which exercises the marker's visibility floor).
func randomLight(_ rng: inout SeededGenerator) -> Light {
    let kind: LightKind
    switch rng.below(3) {
    case 0:
        kind = .directional
    case 1:
        kind = .point(attenuationRadius: 0.5 + rng.unit() * 10)
    default:
        let inner = 1 + rng.unit() * 88
        kind = .spot(innerAngleDegrees: inner, outerAngleDegrees: inner + rng.unit() * 89,
                     attenuationRadius: 0.5 + rng.unit() * 10)
    }
    let color = rng.below(4) == 0 ? SIMD3<Float>(repeating: 0) : SIMD3(rng.unit(), rng.unit(), rng.unit())
    return Light(kind: kind, color: color, intensity: rng.unit() * 30000)
}

extension Rotation {
    var normalized: Rotation {
        let length = (x * x + y * y + z * z + w * w).squareRoot()
        return Rotation(x: x / length, y: y / length, z: z / length, w: w / length)
    }
}
