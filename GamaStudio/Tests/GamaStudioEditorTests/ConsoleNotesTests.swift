//  ConsoleNotesTests.swift — GamaStudioEditorTests
//
//  Editor events kept in the console log as notes (ADR 0017): the logging
//  call itself, refusals from buttons (never doubled with a typed command's
//  own), and the macOS File menu's opens and saves. The iOS/visionOS notes
//  are checked by the gate's simulator file smoke.

#if canImport(RealityKit)

import Foundation
import GamaAuthoring
import GamaCore
import GamaDraw
import GamaStudioEditor
import Testing

#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Suite("Console notes")
struct ConsoleNotesTests {
    func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gama-studio-notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func notes(_ model: StudioModel) -> [String] {
        model.consoleLog.filter(\.isNote).map(\.output)
    }

    @Test func coalescingKeepsARepeatedNoteToOneLine() {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.log(note: "autosaved a.usda", coalescing: true)
        model.log(note: "autosaved a.usda", coalescing: true)
        #expect(notes(model) == ["autosaved a.usda"])

        model.log(note: "autosaved b.usda", coalescing: true)
        model.log(note: "autosaved a.usda", coalescing: true)
        #expect(notes(model) == ["autosaved a.usda", "autosaved b.usda", "autosaved a.usda"], "only the last entry counts")

        model.log(note: "autosaved a.usda")
        #expect(notes(model).count == 4, "without coalescing, a repeat is logged")
        model.runConsole("help")
        model.log(note: "autosaved a.usda", coalescing: true)
        #expect(notes(model).count == 5, "an exchange in between breaks the run")
    }

    @Test func errorNotesAreMarkedAndStillNotes() {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.log(note: "couldn’t save x.usda: disk full", isError: true)
        let entry = model.consoleLog.last
        #expect(entry?.isNote == true && entry?.isError == true && entry?.input == "")
    }

    @Test func aRefusedButtonIsLoggedOnce() {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.undo()  // nothing to undo, as the toolbar's Undo would
        #expect(model.lastError != nil)
        let refused = model.consoleLog.filter { $0.isNote && $0.isError }
        #expect(refused.count == 1)
        #expect(refused.first?.output.hasPrefix("refused: ") == true)

        model.select([EntityID(rawValue: 9_999)])
        #expect(model.consoleLog.filter { $0.isNote && $0.isError }.count == 2, "a refused selection too")
    }

    @Test func aTypedRefusalIsNotLoggedTwice() {
        let model = StudioModel(document: StudioModel.sampleScene())
        let entry = model.runConsole("undo")
        #expect(entry?.isError == true)
        #expect(model.consoleLog.count == 1, "the exchange only, no extra note")
        #expect(model.consoleLog.first?.isNote == false)
    }

    @Test func notesPaintWithoutThePromptEvenWhenErrors() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        model.undo()
        let frame = Size(width: 200, height: 40)
        var host = try FrameHost(app: StudioApp(model: model))
        var buffer = CellBuffer(size: frame)
        buffer.clearBack()
        CellPainter.paint(host.pump(size: frame), into: &buffer)
        let painted = (0..<frame.height).map { buffer.rowText($0) }.joined(separator: "\n")
        #expect(painted.contains("· refused: "))
        #expect(!painted.contains("> refused"))
    }

    #if canImport(AppKit)
    @Test func theFileMenusOpensAndSavesAreLogged() throws {
        let directory = try scratch()
        let model = StudioModel(document: StudioModel.sampleScene())
        let window = StudioAppDelegate.makeMainWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        let delegate = StudioAppDelegate()
        delegate.attach(model: model, window: window)

        let saved = directory.appendingPathComponent("y.usda")
        try delegate.save(to: saved)
        try delegate.open(saved)
        #expect(notes(model).suffix(2) == ["saved y.usda", "opened y.usda"])

        let broken = directory.appendingPathComponent("broken.usda")
        try Data("#usda 1.0\ndef Bogus \"X\"\n{\n}\n".utf8).write(to: broken)
        #expect(throws: (any Error).self) { try delegate.open(broken) }
        let last = try #require(model.consoleLog.last)
        #expect(last.isNote && last.isError)
        #expect(last.output.hasPrefix("couldn’t open broken.usda: "))
    }

    /// A note logged outside any gama action must still reach the screen:
    /// the host repaints on the next main-actor turn (ADR 0017). Found by
    /// hand on iOS, where an error note sat unseen until the next frame.
    @Test func aNoteFromOutsideTheHostRepaintsIt() async {
        let model = StudioModel(document: StudioModel.sampleScene())
        let window = StudioAppDelegate.makeMainWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        let delegate = StudioAppDelegate()
        var redraws = 0
        delegate.attach(model: model, window: window, redraw: { redraws += 1 })
        model.log(note: "couldn’t save z.usda: disk full", isError: true)
        #expect(redraws == 0, "deferred, never from inside the call")
        for _ in 0..<10 { await Task.yield() }
        #expect(redraws == 1)
    }
    #endif
}
#endif
