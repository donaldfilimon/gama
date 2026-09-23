//  Support.swift — GamaStudioEditorTests
//
//  Test targets can't share files, so this is a trimmed copy of the tree
//  snapshot helper from Tests/GamaRealityTests/Support.swift: just enough to
//  compare a StudioModel's bridge against a fresh rebuild.

import AppKit
import GamaAuthoring
import GamaReality
import RealityKit

/// A comparable description of a projected tree: structure, identity, and
/// every projected property. Two bridges showing the same document must
/// produce equal snapshots.
struct NodeSnapshot: Equatable {
    var id: EntityID?
    var name: String
    var matrix: [Float]
    var enabled: Bool
    var hasCollision: Bool
    var meshExtents: [Float]?
    var metallic: Float?
    var roughness: Float?
    var tint: [Float]?
    var children: [NodeSnapshot]
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

import GamaUSD

/// The USD codec, through the editor test target (ADR 0005, ADR 0007).
func usdaStringForTest(_ document: SceneDocument) -> String { usdaString(from: document) }
func sceneDocumentForTest(_ text: String) throws -> SceneDocument { try sceneDocument(fromUSDA: text) }
