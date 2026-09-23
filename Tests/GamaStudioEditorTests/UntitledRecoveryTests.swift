//  UntitledRecoveryTests.swift — GamaStudioEditorTests
//
//  The recovery file an Untitled document autosaves to on iOS and visionOS
//  (ADR 0012): finding it, restoring it as unsaved changes, setting an
//  unreadable one aside, and removing it.

#if canImport(RealityKit)

import Foundation
import GamaAuthoring
import GamaStudioEditor
import Testing

@MainActor
@Suite("Untitled recovery")
struct UntitledRecoveryTests {
    func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gama-studio-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func keysThatCouldNameAnythingButAPlainFileAreRefused() throws {
        let directory = try scratch()
        for key in ["", "../x", "a/b", "a.b", "k~", String(repeating: "a", count: 65)] {
            #expect(UntitledRecovery(key: key, in: directory) == nil, "\(key)")
        }
        let recovery = try #require(UntitledRecovery(key: "6F1C0B2A-0D5E-4E0C-9A4B-1C2D3E4F5A6B", in: directory))
        #expect(recovery.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(recovery.url.pathExtension == "usda")
    }

    @Test func withNoFileNothingIsRestored() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)
        var changes = 0
        session.onStateChange = { changes += 1 }
        let recovery = try #require(UntitledRecovery(key: "none", in: try scratch()))

        #expect(try recovery.restore(into: session) == false)
        #expect(changes == 0)
        #expect(model.session.document == StudioModel.sampleScene())
    }

    @Test func restoringBringsBackUnsavedChangesToAnUntitledDocument() throws {
        let start = StudioModel.sampleScene()
        let before = StudioModel(document: start)
        before.addPrimitive(.box)
        let recovered = before.session.document
        let recovery = try #require(UntitledRecovery(key: "window-1", in: try scratch()))
        try StudioDocumentIO.write(recovered, to: recovery.url)

        let model = StudioModel(document: start)
        let session = StudioDocumentSession(model: model)
        var changes = 0
        session.onStateChange = { changes += 1 }
        #expect(try recovery.restore(into: session))

        #expect(model.session.document == recovered)
        #expect(changes == 1)
        #expect(session.currentURL == nil, "still Untitled")
        #expect(session.displayName == "Untitled.usda")
        #expect(session.hasUnsavedChanges, "unsaved against the content it started from")
        #expect(!model.session.canUndo)
        #expect(recovery.exists, "restoring keeps the file until the changes are saved or discarded")

        // Back to the starting content reads as clean.
        model.replaceDocument(start, asSaved: false)
        #expect(!session.hasUnsavedChanges)
    }

    @Test func aDocumentWithAFileIsNotOverwrittenByARecovery() throws {
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)
        let directory = try scratch()
        try session.save(to: directory.appendingPathComponent("real.usda"))
        let before = model.session.document
        var other = EditorSession()
        try other.execute(CreateEntity(name: "Other", components: [.transform(.identity)]))

        session.restoreUntitled(other.document)
        #expect(model.session.document == before)
        #expect(!session.hasUnsavedChanges)
    }

    @Test func anUnreadableFileIsSetAsideIntactAndTheDocumentUntouched() throws {
        let directory = try scratch()
        let recovery = try #require(UntitledRecovery(key: "broken", in: directory))
        let bytes = Data("#usda 1.0\ndef Bogus \"X\"\n{\n}\n".utf8)
        try bytes.write(to: recovery.url)
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)

        #expect(throws: (any Error).self) { try recovery.restore(into: session) }
        #expect(model.session.document == StudioModel.sampleScene())
        #expect(!recovery.exists, "moved out of the way of the next autosave")
        let aside = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("broken.unreadable-") && $0.hasSuffix(".usda") }
        #expect(aside.count == 1)
        if let name = aside.first {
            #expect(try Data(contentsOf: directory.appendingPathComponent(name)) == bytes)
        }
    }

    @Test func discardingRemovesTheFileAndIsHarmlessTwice() throws {
        let recovery = try #require(UntitledRecovery(key: "gone", in: try scratch()))
        try StudioDocumentIO.write(StudioModel.sampleScene(), to: recovery.url)
        recovery.discard()
        #expect(!recovery.exists)
        recovery.discard()
        #expect(!recovery.exists)
    }

    @Test func replacingWithoutMarkingSavedKeepsTheSavedBaseline() {
        let start = StudioModel.sampleScene()
        let model = StudioModel(document: start)
        var other = EditorSession()
        try? other.execute(CreateEntity(name: "Other", components: [.transform(.identity)]))

        model.replaceDocument(other.document, asSaved: false)
        #expect(model.hasUnsavedChanges)
        model.replaceDocument(other.document)
        #expect(!model.hasUnsavedChanges)
    }
}
#endif
