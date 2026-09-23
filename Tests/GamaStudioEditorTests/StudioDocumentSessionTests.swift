//  StudioDocumentSessionTests.swift — GamaStudioEditorTests
//
//  The platform-neutral file core both the macOS File menu and the
//  iOS/visionOS document pickers drive (ADR 0009), and the toolbar's file
//  buttons.

#if canImport(RealityKit)

import Foundation
import GamaAuthoring
import GamaCore
import GamaDraw
import GamaStudioEditor
import GamaUSD
import Testing

@MainActor
@Suite("Studio document session")
struct StudioDocumentSessionTests {
    func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gama-studio-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func saveWithoutAFileAsksForOneAndWritesNothing() throws {
        let session = StudioDocumentSession(model: StudioModel(document: StudioModel.sampleScene()))
        #expect(session.displayName == "Untitled.usda")
        #expect(try session.saveToCurrentFile() == false)
        #expect(session.currentURL == nil)
    }

    @Test func saveThenSaveInPlaceThenOpen() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)
        var changes = 0
        session.onStateChange = { changes += 1 }
        let url = try scratch().appendingPathComponent("scene.usda")

        try session.save(to: url)
        #expect(session.currentURL == url)
        #expect(session.displayName == "scene.usda")
        #expect(!session.hasUnsavedChanges)
        model.addPrimitive(.box)
        #expect(session.hasUnsavedChanges)
        let edited = model.session.document
        #expect(try session.saveToCurrentFile())
        #expect(try StudioDocumentIO.read(from: url) == edited)
        #expect(!session.hasUnsavedChanges)

        model.addPrimitive(.sphere)
        let before = changes
        try session.open(url)
        #expect(model.session.document == edited)
        #expect(!model.session.canUndo)
        #expect(changes == before + 1, "one notification per open, naming the new file")
    }

    @Test func exportCopyAdoptsTheChosenLocation() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)
        let temp = try scratch()
        let (file, document) = try session.writeCopyForExport(in: temp)
        #expect(file.lastPathComponent == "Untitled.usda")
        #expect(try StudioDocumentIO.read(from: file) == document)
        #expect(session.currentURL == nil, "writing the copy alone changes nothing")

        // The picker copies the file somewhere else; that becomes the file.
        let chosen = try scratch().appendingPathComponent("Chosen.usda")
        try FileManager.default.copyItem(at: file, to: chosen)
        model.addPrimitive(.cone)  // edited while the picker was open
        session.adoptSavedCopy(at: chosen, of: document)
        #expect(session.currentURL == chosen)
        #expect(session.hasUnsavedChanges, "the edit made during the picker is not in the copy")

        model.undo()
        session.adoptSavedCopy(at: chosen, of: document)
        #expect(!session.hasUnsavedChanges)
    }

    @Test func failedOpenLeavesFileAndDocumentAlone() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)
        let good = try scratch().appendingPathComponent("good.usda")
        try session.save(to: good)
        let bad = try scratch().appendingPathComponent("bad.usda")
        try Data("#usda 1.0\ndef Mesh \"X\"\n{\n}\n".utf8).write(to: bad)
        let before = model.session.document
        #expect(throws: USDError.self) { try session.open(bad) }
        #expect(session.currentURL == good)
        #expect(model.session.document == before)
    }

    @Test func fileButtonsAppearOnlyWhenAHostSuppliesThem() throws {
        let frame = Size(width: 160, height: 40)
        func paint(_ laidOut: LaidOutNode) -> String {
            var buffer = CellBuffer(size: frame)
            buffer.clearBack()
            CellPainter.paint(laidOut, into: &buffer)
            return (0..<frame.height).map { buffer.rowText($0) }.joined(separator: "\n")
        }
        let model = StudioModel(document: StudioModel.sampleScene())
        var plain = try FrameHost(app: StudioApp(model: model))
        #expect(!paint(plain.pump(size: frame)).contains("Save As"))

        var calls: [String] = []
        let actions = DocumentActions(
            open: { calls.append("open") }, save: { calls.append("save") }, saveAs: { calls.append("saveAs") }
        )
        var host = try FrameHost(app: StudioApp(model: model, documents: actions))
        #expect(paint(host.pump(size: frame)).contains("Save As"))
        for id in StudioApp.fileActionIDs { host.perform(id) }
        #expect(calls == ["open", "save", "saveAs"])
        #expect(model.session.revision == 0, "the buttons only ask the host")
    }
}
#endif
