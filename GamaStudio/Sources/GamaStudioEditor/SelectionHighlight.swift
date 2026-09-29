//  SelectionHighlight.swift — GamaStudioEditor
//
//  The viewport's selection highlight: a wireframe box around each selected
//  entity's world-space bounds. Editor state, like the orbit camera and the
//  fallback light (ADR 0003): it is never in the document, never in the
//  bridge's entity maps, and carries no collision, so picking passes through
//  it.

#if canImport(RealityKit) && (canImport(AppKit) || canImport(UIKit))

#if canImport(AppKit)
public import AppKit
/// The platform color type the highlight's material takes.
public typealias HighlightColor = NSColor
#else
public import UIKit
/// The platform color type the highlight's material takes.
public typealias HighlightColor = UIColor
#endif
public import GamaAuthoring
public import GamaReality
public import RealityKit

/// Draws a wireframe box around every selected entity.
@MainActor
public final class SelectionHighlight {
    /// Parent of every highlight edge. The viewport adds it beside
    /// `bridge.root`, never under it, so the highlight cannot change the
    /// projection, its bounds, or picking.
    public let root: Entity

    /// The world-space box drawn for each highlighted entity, after padding.
    public private(set) var boxes: [EntityID: BoundingBox] = [:]

    /// Edge color: a saturated orange that reads against the dark background
    /// and against the sample's grey, red, green, and blue materials.
    #if canImport(AppKit)
    public static let color = HighlightColor(srgbRed: 1, green: 0.62, blue: 0.1, alpha: 1)
    #else
    // UIColor's red/green/blue initializer is sRGB.
    public static let color = HighlightColor(red: 1, green: 0.62, blue: 0.1, alpha: 1)
    #endif

    /// Smallest half-size of a highlighted box, in meters, so an entity with
    /// no geometry (an empty group) still shows where it is.
    public static let minimumHalfExtent: Float = 0.05

    private let mesh = MeshResource.generateBox(size: 1)
    private let material = UnlitMaterial(color: SelectionHighlight.color)

    public init() {
        root = Entity()
        root.name = "GamaStudio.selectionHighlight"
    }

    /// Replaces the highlight with one box per entity in `selection` that
    /// `bridge` projects. Hidden entities are highlighted too, so a selection
    /// made in the hierarchy can still be found in the viewport.
    /// `space` is the entity the highlight root sits under (`nil` for world
    /// space); bounds are measured in it, so a scaled or turned stage, as on
    /// visionOS, still gets boxes that line up with what they surround.
    public func update(selection: [EntityID], bridge: RealityBridge, relativeTo space: Entity? = nil) {
        for child in Array(root.children) {
            child.removeFromParent()
        }
        boxes = [:]
        for id in selection {
            guard let entity = bridge.entity(for: id) else { continue }
            let box = Self.highlightBounds(of: entity, relativeTo: space)
            boxes[id] = box
            let thickness = Self.edgeThickness(for: box)
            for edge in Self.edges(of: box, thickness: thickness) {
                let model = ModelEntity(mesh: mesh, materials: [material])
                model.position = edge.center
                model.scale = edge.size
                root.addChild(model)
            }
        }
    }

    /// `entity`'s world-space visual bounds, including its descendants and
    /// inactive (hidden) parts, padded so the edges sit just outside the
    /// surface instead of z-fighting with it. An entity without geometry gets
    /// a small box at its world position.
    public static func highlightBounds(of entity: Entity, relativeTo space: Entity? = nil) -> BoundingBox {
        var bounds = entity.visualBounds(recursive: true, relativeTo: space, excludeInactive: false)
        if bounds.isEmpty || !bounds.min.x.isFinite {
            let position = entity.position(relativeTo: space)
            bounds = BoundingBox(min: position, max: position)
        }
        let center = (bounds.min + bounds.max) / 2
        var half = (bounds.max - bounds.min) / 2
        let padding = max(0.03, 0.04 * max(half.x, max(half.y, half.z)))
        half = SIMD3(
            max(half.x + padding, minimumHalfExtent),
            max(half.y + padding, minimumHalfExtent),
            max(half.z + padding, minimumHalfExtent)
        )
        return BoundingBox(min: center - half, max: center + half)
    }

    /// Edge width in meters: proportional to the box so large and small
    /// selections read alike, with a floor so small ones stay visible.
    public static func edgeThickness(for box: BoundingBox) -> Float {
        let size = box.max - box.min
        let diagonal = (size * size).sum().squareRoot()
        return max(0.01, diagonal * 0.012)
    }

    /// One edge of a box, as the center and size of a thin box mesh.
    public struct Edge: Equatable, Sendable {
        public var center: SIMD3<Float>
        public var size: SIMD3<Float>
    }

    /// The twelve edges of `box`: for each axis, four edges running along it,
    /// one at each min/max corner of the other two axes. Each runs the full
    /// length plus `thickness` so the corners close.
    public static func edges(of box: BoundingBox, thickness: Float) -> [Edge] {
        var result: [Edge] = []
        let extent = box.max - box.min
        let middle = (box.min + box.max) / 2
        for axis in 0..<3 {
            let b = (axis + 1) % 3
            let c = (axis + 2) % 3
            for bEnd in [box.min[b], box.max[b]] {
                for cEnd in [box.min[c], box.max[c]] {
                    var center = middle
                    center[b] = bEnd
                    center[c] = cEnd
                    var size = SIMD3<Float>(repeating: thickness)
                    size[axis] = extent[axis] + thickness
                    result.append(Edge(center: center, size: size))
                }
            }
        }
        return result
    }
}
#endif
