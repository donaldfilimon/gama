//  ConsoleTests.swift — GamaStudioEditorTests
//
//  The command console end to end (ADR 0006): lines run through the same
//  StudioModel funnel as the toolbar, and the panel's field submits on Enter.

#if canImport(AppKit)

import Foundation
import GamaAuthoring
import GamaCore
import GamaDraw
import GamaReality
import GamaStudioEditor
import Testing

private let frameSize = Size(width: 120, height: 44)

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

@MainActor
@Suite("Command console")
struct ConsoleTests {
    @Test func consoleAddMatchesTheToolbarButton() throws {
        let viaConsole = StudioModel(document: StudioModel.sampleScene())
        let viaToolbar = StudioModel(document: StudioModel.sampleScene())
        let entry = try #require(viaConsole.runConsole("add sphere"))
        viaToolbar.addPrimitive(.sphere)
        #expect(viaConsole.session.document == viaToolbar.session.document)
        #expect(viaConsole.session.selection == viaToolbar.session.selection)
        #expect(viaConsole.session.undoLabel == viaToolbar.session.undoLabel)
        #expect(entry == .init(input: "add sphere", output: "Created Sphere 2", isError: false))
        assertConverged(viaConsole)
    }

    @Test func editsGoThroughTheFunnelAndUndoLikeAnyOther() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var changes = 0
        model.onDocumentChange = { changes += 1 }
        let box = try id("Box", model)
        model.runConsole("select box")
        #expect(model.session.selection.primary == box)
        let entry = try #require(model.runConsole("move 1 0 0"))
        #expect(!entry.isError)
        #expect(entry.output == "Set Transform")
        #expect(model.session.document.component(.transform, of: box) == .transform(Transform(position: SIMD3(-1, 0.5, 0))))
        #expect(changes == 1)
        assertConverged(model)

        model.runConsole("undo")
        #expect(model.session.document.component(.transform, of: box) == .transform(Transform(position: SIMD3(-2, 0.5, 0))))
        #expect(model.consoleLog.last?.output == "Undid Set Transform")
        assertConverged(model)
    }

    @Test func multiTargetEditsAreOneUndoStep() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.runConsole("select all")
        let revision = model.session.revision
        model.runConsole("hide")
        #expect(model.session.revision == revision + 1)
        #expect(model.session.undoLabel == "Hide 6 Entities")
        model.undo()
        #expect(model.session.document.hasSameContent(as: StudioModel.sampleScene()))
    }

    @Test func parseErrorsAndRefusalsAreLoggedAndChangeNothing() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let before = model.session.document
        let unknown = try #require(model.runConsole("fly away"))
        #expect(unknown.isError)
        #expect(unknown.output == "unknown command 'fly'; type 'help' for the list")
        let refused = try #require(model.runConsole("metallic sphere 5"))
        #expect(refused.isError)
        #expect(refused.output.hasPrefix("refused: "))
        #expect(model.session.document == before)
        #expect(model.session.revision == 0)
        // A later good line is not tainted by the earlier refusal.
        let help = try #require(model.runConsole("help"))
        #expect(!help.isError)
        let ok = try #require(model.runConsole("roughness sphere 0.2"))
        #expect(!ok.isError)
        #expect(model.lastError == nil)
    }

    @Test func blankLinesAreIgnoredAndTheLogIsBounded() {
        let model = StudioModel()
        #expect(model.runConsole("   ") == nil)
        #expect(model.consoleLog.isEmpty)
        for _ in 0..<(StudioModel.consoleLogLimit + 5) { model.runConsole("help") }
        #expect(model.consoleLog.count == StudioModel.consoleLogLimit)
    }

    /// Typing into the panel's field and pressing Enter runs the line; a
    /// click into the field does not.
    @Test func panelFieldSubmitsOnEnter() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        var host = try FrameHost(app: StudioApp(model: model))
        var text = painted(host.pump(size: frameSize))
        #expect(text.contains("Console"))

        // The field is the last focusable node: Shift-Tab from the first wraps to it.
        host.handle(.key(.backTab))
        _ = host.pump(size: frameSize)
        for character in "add cone" { host.handle(.key(.character(character))) }
        #expect(model.consoleInput == "add cone")
        #expect(model.session.revision == 0, "typing alone edits nothing")

        // Clicking into the field focuses it without submitting.
        text = painted(host.pump(size: frameSize))
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let row = try #require(rows.firstIndex { $0.contains(" add cone ") })
        let column = try #require(rows[row].range(of: " add cone ")).lowerBound
        host.handle(.pointer(Point(x: rows[row].distance(from: rows[row].startIndex, to: column) + 2, y: row), pressed: true))
        _ = host.pump(size: frameSize)
        #expect(model.consoleInput == "add cone", "a click must not submit")
        #expect(model.session.revision == 0)

        host.handle(.key(.enter))
        text = painted(host.pump(size: frameSize))
        #expect(model.consoleInput.isEmpty)
        #expect(model.session.document.entities.values.contains { $0.name == "Cone 2" })
        #expect(text.contains("> add cone  →  Created Cone 2"))
        #expect(text.contains("Cone 2"), "the hierarchy shows the new entity")
    }
}

#endif
