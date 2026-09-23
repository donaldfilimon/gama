import AppKit
import GamaAuthoring
import GamaReality
import RealityKit

/// A comparable description of a projected tree: structure, identity, and
/// every projected property. Two bridges showing the same document must
/// produce equal snapshots.
struct NodeSnapshot: Equatable, CustomStringConvertible {
    var id: EntityID?
    var name: String
    var matrix: [Float]
    var enabled: Bool
    var meshExtents: [Float]?
    var metallic: Float?
    var roughness: Float?
    var tint: [Float]?
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
        children: entity.children.map { snapshot($0, in: bridge) }
    )
    if let model = entity.components[ModelComponent.self] {
        let extents = model.mesh.bounds.extents
        node.meshExtents = [extents.x, extents.y, extents.z]
        if let material = model.materials.first as? PhysicallyBasedMaterial {
            node.metallic = material.metallic.scale
            node.roughness = material.roughness.scale
            if let tint = material.baseColor.tint.usingColorSpace(.sRGB) {
                node.tint = [tint.redComponent, tint.greenComponent, tint.blueComponent, tint.alphaComponent].map { Float($0) }
            }
        }
    }
    return node
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
    switch rng.below(9) {
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
    default:
        let parent = rng.below(3) == 0 ? nil : rng.pick(ids)
        let count = document.children(of: parent).count
        return ReparentEntity(target, to: parent, at: rng.below(2) == 0 ? nil : rng.below(count + 1))
    }
}

extension Rotation {
    var normalized: Rotation {
        let length = (x * x + y * y + z * z + w * w).squareRoot()
        return Rotation(x: x / length, y: y / length, z: z / length, w: w / length)
    }
}
