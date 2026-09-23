//  SelectionHighlightTests.swift — GamaStudioEditorTests
//
//  The viewport's selection highlight: its geometry, that it follows every
//  way the selection or the selected entity can change, and that it stays
//  editor state (outside the bridge, unpickable).

#if canImport(AppKit) && canImport(RealityKit)

import AppKit
import GamaAuthoring
import GamaReality
import GamaStudioEditor
import RealityKit
import Testing

@MainActor
private func sampleID(named name: String, in model: StudioModel) throws -> EntityID {
    try #require(model.session.document.entities.values.first { $0.name == name }?.id)
}

private func approximately(_ a: SIMD3<Float>, _ b: SIMD3<Float>, within tolerance: Float = 1e-3) -> Bool {
    let d = a - b
    return abs(d.x) <= tolerance && abs(d.y) <= tolerance && abs(d.z) <= tolerance
}

@MainActor
@Suite("Selection highlight")
struct SelectionHighlightTests {
    @Test func edgesTraceAllTwelveEdgesOfTheBox() {
        let box = BoundingBox(min: SIMD3(-1, 0, -2), max: SIMD3(1, 4, 2))
        let edges = SelectionHighlight.edges(of: box, thickness: 0.1)
        #expect(edges.count == 12)
        // Four edges along each axis, each the box's length plus one thickness.
        for (axis, length) in [(0, Float(2)), (1, Float(4)), (2, Float(4))] {
            let along = edges.filter { $0.size[axis] > 0.1 + 1e-6 }
            #expect(along.count == 4)
            #expect(along.allSatisfy { abs($0.size[axis] - (length + 0.1)) < 1e-6 })
        }
        // Every edge center lies on the box's surface corners in two axes.
        let corners = Set(edges.map { "\($0.center)" })
        #expect(corners.count == 12)
        #expect(edges.contains { approximately($0.center, SIMD3(0, 0, -2)) })
        #expect(edges.contains { approximately($0.center, SIMD3(1, 4, 0)) })
    }

    @Test func boundsArePaddedAndEmptyEntitiesStillShow() {
        let empty = Entity()
        empty.position = SIMD3(3, 1, 2)
        let box = SelectionHighlight.highlightBounds(of: empty)
        #expect(approximately((box.min + box.max) / 2, SIMD3(3, 1, 2)))
        #expect(approximately(box.max - box.min, SIMD3(repeating: 2 * SelectionHighlight.minimumHalfExtent)))

        let cube = ModelEntity(mesh: .generateBox(size: 1))
        let padded = SelectionHighlight.highlightBounds(of: cube)
        #expect(padded.min.x < -0.5 && padded.max.x > 0.5, "edges sit outside the surface")
        #expect(padded.max.x < 0.6, "tight enough to read as this entity's box")
    }

    @Test func highlightFollowsSelectionFromAnySource() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        let highlight = viewport.selectionHighlight
        #expect(highlight.boxes.isEmpty)
        #expect(highlight.root.children.isEmpty)

        // A panel selection goes through the model, not a viewport click.
        let box = try sampleID(named: "Box", in: model)
        model.select(box)
        #expect(Array(highlight.boxes.keys) == [box])
        #expect(highlight.root.children.count == 12)
        let boxBounds = try #require(model.bridge.entity(for: box))
            .visualBounds(recursive: true, relativeTo: nil, excludeInactive: false)
        let drawn = try #require(highlight.boxes[box])
        #expect(approximately((drawn.min + drawn.max) / 2, (boxBounds.min + boxBounds.max) / 2))

        // An edit to the selected entity moves the box with it.
        model.nudgeSelection(by: SIMD3(1, 0, 0))
        let moved = try #require(highlight.boxes[box])
        #expect(approximately((moved.min + moved.max) / 2, (drawn.min + drawn.max) / 2 + SIMD3(1, 0, 0)))

        // Adding selects the new entity; delete clears; undo restores without
        // reselecting (the session does not restore selection on undo).
        model.addPrimitive(.sphere)
        let added = try #require(model.session.selection.primary)
        #expect(Array(highlight.boxes.keys) == [added])
        model.deleteSelection()
        #expect(highlight.boxes.isEmpty)
        #expect(highlight.root.children.isEmpty)

        model.select(box)
        model.select(nil)
        #expect(highlight.boxes.isEmpty)
    }

    @Test func hiddenSelectionsAreStillHighlighted() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        let cone = try sampleID(named: "Cone", in: model)
        model.select(cone)
        model.toggleVisibility()
        #expect(viewport.selectionHighlight.boxes[cone] != nil)
    }

    @Test func openingADocumentClearsTheHighlight() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        model.select(try sampleID(named: "Sphere", in: model))
        #expect(!viewport.selectionHighlight.boxes.isEmpty)
        model.replaceDocument(StudioModel.sampleScene())
        #expect(viewport.selectionHighlight.boxes.isEmpty)
    }

    @Test func highlightIsEditorStateOutsideTheBridgeAndUnpickable() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let viewport = ViewportController(model: model, onSelectionChange: {})
        model.select(try sampleID(named: "Sphere", in: model))
        let root = viewport.selectionHighlight.root
        #expect(root.parent === model.bridge.root.parent, "a sibling of bridge.root, not a child")
        #expect(!isDescendant(root, of: model.bridge.root))
        for edge in root.children {
            #expect(edge.components[CollisionComponent.self] == nil)
            #expect(ViewportController.pickedEntityID(for: edge, in: model.bridge) == nil)
            #expect(model.bridge.id(for: edge) == nil)
        }
        // The projection still converges with a fresh rebuild.
        let fresh = RealityBridge()
        fresh.rebuild(from: model.session.document)
        #expect(snapshot(model.bridge) == snapshot(fresh))
    }

    @Test func selectionFeedFiresOnlyOnChange() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var fired = 0
        model.onSelectionChange = { fired += 1 }
        let box = try sampleID(named: "Box", in: model)
        model.select(box)
        #expect(fired == 1)
        model.select(box)
        #expect(fired == 1, "same selection: no report")
        model.nudgeSelection(by: SIMD3(0, 1, 0))
        #expect(fired == 1, "an edit that keeps the selection: no report")
        model.select(EntityID(rawValue: 999))
        #expect(fired == 1, "a refused selection changes nothing")
        model.deleteSelection()
        #expect(fired == 2)
        model.undo()
        #expect(fired == 2)
        model.addPrimitive(.cone)
        #expect(fired == 3)
    }
}

private func isDescendant(_ entity: Entity, of ancestor: Entity) -> Bool {
    var cursor = entity.parent
    while let current = cursor {
        if current === ancestor { return true }
        cursor = current.parent
    }
    return false
}
#endif
