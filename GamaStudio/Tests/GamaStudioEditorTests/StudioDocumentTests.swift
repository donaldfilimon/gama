//  StudioDocumentTests.swift — GamaStudioEditorTests
//
//  File I/O and the File menu's non-modal paths (ADR 0005). The panel and
//  alert paths need a person; everything they call is exercised here.

#if canImport(AppKit)

import AppKit
import Foundation
import GamaAuthoring
import GamaReality
import GamaStudioEditor
import GamaUSD
import Testing

@MainActor
@Suite("Studio documents")
struct StudioDocumentTests {
    func scratchURL(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gama-studio-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    @Test func fileRoundTripKeepsTheSampleSceneExactly() throws {
        let url = try scratchURL("sample.usda")
        let sample = StudioModel.sampleScene()
        try StudioDocumentIO.write(sample, to: url)
        #expect(try StudioDocumentIO.read(from: url) == sample)
    }

    @Test func saveAndOpenDriveTheModelAndWindow() throws {
        let url = try scratchURL("scene.usda")
        let model = StudioModel(document: StudioModel.sampleScene())
        let window = StudioAppDelegate.makeMainWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        let delegate = StudioAppDelegate()
        delegate.attach(model: model, window: window)
        #expect(window.title == "Gama Studio")
        #expect(!window.isDocumentEdited)

        model.addPrimitive(.box)
        #expect(window.isDocumentEdited, "an edit marks the window edited")
        let edited = model.session.document

        try delegate.save(to: url)
        #expect(delegate.currentURL == url)
        #expect(window.title == "scene.usda")
        #expect(window.representedURL == url)
        #expect(!window.isDocumentEdited)
        #expect(!model.hasUnsavedChanges)

        model.addPrimitive(.sphere)
        #expect(window.isDocumentEdited)
        try delegate.open(url)
        #expect(model.session.document == edited)
        #expect(!model.session.canUndo, "opening a file is not undoable")
        #expect(!window.isDocumentEdited)
        #expect(model.bridge.count == edited.count)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test func failedOpenLeavesTheDocumentAlone() throws {
        let url = try scratchURL("broken.usda")
        try Data("#usda 1.0\ndef Mesh \"X\"\n{\n}\n".utf8).write(to: url)
        let model = StudioModel(document: StudioModel.sampleScene())
        let window = StudioAppDelegate.makeMainWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        let delegate = StudioAppDelegate()
        delegate.attach(model: model, window: window)
        let before = model.session.document

        #expect(throws: USDError.self) { try delegate.open(url) }
        #expect(model.session.document == before)
        #expect(delegate.currentURL == nil)

        let missing = url.deletingLastPathComponent().appendingPathComponent("absent.usda")
        #expect(throws: (any Error).self) { try delegate.open(missing) }
        #expect(model.session.document == before)
    }

    @Test func openRedrawsTheHostAndCloseAsksOnlyWhenEdited() async throws {
        let url = try scratchURL("redraw.usda")
        try StudioDocumentIO.write(StudioModel.sampleScene(), to: url)
        let model = StudioModel()
        let window = StudioAppDelegate.makeMainWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        let delegate = StudioAppDelegate()
        var redraws = 0
        delegate.attach(model: model, window: window, redraw: { redraws += 1 })
        #expect(window.delegate === delegate)
        try delegate.open(url)
        // The repaint is deferred to the next main-actor turn (HostRedrawTests).
        for _ in 0..<10 { await Task.yield() }
        #expect(redraws == 1, "a File-menu open must repaint the Gama panels")
        #expect(delegate.windowShouldClose(window), "nothing unsaved: closes without asking")
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test func fileOperationsBeforeAttachThrow() throws {
        let delegate = StudioAppDelegate()
        let url = try scratchURL("never.usda")
        #expect(throws: StudioDocumentError.notAttached) { try delegate.save(to: url) }
        #expect(throws: StudioDocumentError.notAttached) { try delegate.open(url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func errorsDescribeTheirLine() {
        #expect(StudioDocumentIO.describe(USDError.syntax(line: 4, "expected a number")) == "Line 4: expected a number.")
        #expect(StudioDocumentIO.describe(USDError.unsupported(line: 2, "variant sets")) == "Line 2: unsupported: variant sets.")
    }

    @Test func fileMenuTargetsTheDelegate() {
        let delegate = StudioAppDelegate()
        let item = delegate.makeFileMenuItem()
        let entries = item.submenu?.items.map { ($0.title, $0.keyEquivalent, $0.keyEquivalentModifierMask) } ?? []
        #expect(entries.map(\.0) == ["Open…", "Save", "Save As…"])
        #expect(entries.map(\.1) == ["o", "s", "s"])
        #expect(entries[2].2 == [.command, .shift])
        #expect(item.submenu?.items.allSatisfy { $0.target === delegate } == true)
    }
}
#endif
