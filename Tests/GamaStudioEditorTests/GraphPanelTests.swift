//  GraphPanelTests.swift — GamaStudioEditorTests
//
//  The graph editor panel driven only through its buttons (ADR 0007), and the
//  StudioModel graph API it calls.

#if canImport(AppKit)

import GamaAuthoring
import GamaCore
import GamaDraw
import GamaGraph
import GamaReality
import GamaStudioEditor
import Testing

private let frameSize = Size(width: 120, height: 48)

private func painted(_ frame: LaidOutNode) -> String {
    var buffer = CellBuffer(size: frameSize)
    buffer.clearBack()
    CellPainter.paint(frame, into: &buffer)
    return (0..<frameSize.height).map { buffer.rowText($0) }.joined(separator: "\n")
}

@MainActor
private func id(_ name: String, _ model: StudioModel) throws -> EntityID {
    try #require(model.session.document.entities.values.first { $0.name == name }?.id)
}

@MainActor
private func assertConverged(_ model: StudioModel, sourceLocation: SourceLocation = #_sourceLocation) {
    let fresh = RealityBridge()
    fresh.rebuild(from: model.session.document)
    #expect(snapshot(model.bridge) == snapshot(fresh), sourceLocation: sourceLocation)
}

/// Cycles the Add picker until it shows `title`.
@MainActor
private func pick(_ title: String, _ host: inout FrameHost, _ model: StudioModel) throws {
    for _ in 0..<model.offeredNodes.count where model.pickedNode?.title != title {
        host.perform(ActionID("studio.graph.picker.next"))
        _ = host.pump(size: frameSize)
    }
    #expect(model.pickedNode?.title == title)
}

@MainActor
@Suite("Graph editor panel")
struct GraphPanelTests {
    @Test func buildAMaterialGraphWithButtonsOnly() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        var text = painted(host.pump(size: frameSize))
        #expect(text.contains("Inspector"))

        host.perform(ActionID("studio.graph.toggle"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("No graphs"))
        #expect(!text.contains("Nothing selected"), "the graph editor replaces the inspector")

        host.perform(ActionID("studio.graph.newMaterial"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("1/1 material"))
        #expect(text.contains("Material Graph"))

        try pick("Material Output", &host, model)
        host.perform(ActionID("studio.graph.add"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("▸ n1 Material Output"))
        #expect(text.contains("target = none"))

        // Point the output at the selected Box: its material follows.
        let box = try id("Box", model)
        model.select(box)
        host.perform(ActionID("studio.graph.target.target"))
        #expect(model.session.document.component(.material, of: box)
            == .material(Material(baseColor: SIMD4(0.8, 0.8, 0.8, 1), metallic: 0, roughness: 0.5)))
        host.perform(ActionID("studio.graph.inc.metallic"))
        guard case .material(let nudged)? = model.session.document.component(.material, of: box) else {
            Issue.record("material missing"); return
        }
        #expect(abs(nudged.metallic - 0.1) < 1e-6)
        assertConverged(model)

        // Add a Color constant and link it into base_color.
        try pick("Color", &host, model)
        host.perform(ActionID("studio.graph.add"))
        _ = host.pump(size: frameSize)
        host.perform(ActionID("studio.graph.link.value"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("Link n2.value →"))
        host.perform(ActionID("studio.graph.node.1"))
        _ = host.pump(size: frameSize)
        host.perform(ActionID("studio.graph.connect.base_color"))
        text = painted(host.pump(size: frameSize))
        #expect(text.contains("base_color ← n2.value"))
        #expect(model.pendingLink == nil)

        // One undo takes back the link and its effect together.
        let linked = model.session.document
        host.perform(ActionID("studio.undo"))
        #expect(model.currentGraph?.connections.isEmpty == true)
        host.perform(ActionID("studio.redo"))
        #expect(model.session.document == linked)
        assertConverged(model)
    }

    @Test func graphEditsThatWouldFailAreRefusedAndReported() throws {
        let model = StudioModel()
        model.createGraph(name: "Math", domain: .logic)
        model.addGraphNode("math.divide")
        let divide = try #require(model.selectedGraphNode)
        let revision = model.session.revision
        model.setGraphValue(.float(0), for: PortReference(divide, "b"))
        #expect(model.lastError == .invalidGraph("g1 evaluation failed: n1: division by zero"))
        #expect(model.session.revision == revision, "the refused edit changed nothing")
    }

    @Test func editorStateSurvivesUndoOfTheActiveGraph() throws {
        let model = StudioModel()
        model.createGraph(name: "One", domain: .material)
        model.createGraph(name: "Two", domain: .scene)
        #expect(model.currentGraph?.name == "Two")
        model.undo()
        #expect(model.currentGraph?.name == "One", "falls back to the first graph")
        model.cycleGraph(by: 1)
        #expect(model.currentGraph?.name == "One")
        model.deleteCurrentGraph()
        #expect(model.currentGraph == nil)
        var host = try FrameHost(app: StudioApp(model: model))
        model.toggleGraphEditor()
        #expect(painted(host.pump(size: frameSize)).contains("No graphs"))
    }

    @Test func domainsFilterThePicker() {
        let model = StudioModel()
        model.createGraph(name: "M", domain: .material)
        #expect(model.offeredNodes.contains { $0.id == "output.material" })
        #expect(!model.offeredNodes.contains { $0.id == "output.transform" })
        model.createGraph(name: "S", domain: .scene)
        #expect(model.offeredNodes.contains { $0.id == "output.transform" })
        model.cycleNodePicker(by: -1)
        #expect(model.pickedNode?.id == model.offeredNodes.last?.id)
    }

    @Test func savingAndOpeningKeepsGraphs() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.runConsole("graph new Lift scene")
        model.runConsole("graph add Lift output.transform")
        model.runConsole("graph set Lift n1.position 0 3 0")
        model.runConsole("graph set Lift n1.target sphere")
        let sphere = try id("Sphere", model)
        guard case .transform(let lifted)? = model.session.document.component(.transform, of: sphere) else {
            Issue.record("transform missing"); return
        }
        #expect(lifted.position == SIMD3(0, 3, 0))
        let text = usdaStringForTest(model.session.document)
        let reopened = StudioModel()
        reopened.replaceDocument(try sceneDocumentForTest(text))
        #expect(reopened.session.document == model.session.document)
        #expect(reopened.currentGraph?.name == "Lift")
    }
}
#endif
