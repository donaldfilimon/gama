//  UntitledRecoveryTests.swift — GamaStudioEditorTests
//
//  The recovery file an Untitled document autosaves to on iOS and visionOS
//  (ADR 0012): finding it, restoring it as unsaved changes, setting an
//  unreadable one aside, and removing it.

#if canImport(RealityKit)

import Foundation
import GamaAuthoring
import GamaCore
import GamaDraw
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

    // MARK: Orphans (ADR 0013)

    /// Writes `name` in `directory`, last modified `age` seconds before `now`.
    func plant(_ name: String, in directory: URL, age: TimeInterval, now: Date) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("#usda 1.0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    @Test func sweepingDeletesOnlyOrphansPastTheGracePeriod() throws {
        let directory = try scratch()
        let now = Date()
        let grace = UntitledRecovery.orphanGracePeriod
        let oldOrphan = try plant("A1.usda", in: directory, age: grace + 60, now: now)
        let youngOrphan = try plant("A2.usda", in: directory, age: grace - 60, now: now)
        let oldLive = try plant("LIVE.usda", in: directory, age: grace * 4, now: now)
        let oldAside = try plant("A3.unreadable-1790000000.usda", in: directory, age: grace + 60, now: now)
        let youngAside = try plant("A4.unreadable-1790000000.usda", in: directory, age: 60, now: now)
        let foreign = try [
            plant("notes.txt", in: directory, age: grace * 4, now: now),
            plant("a.b.c.usda", in: directory, age: grace * 4, now: now),
            plant("A5.copy.usda", in: directory, age: grace * 4, now: now),
            plant("bad key.usda", in: directory, age: grace * 4, now: now),
        ]

        let deleted = UntitledRecovery.sweepOrphans(in: directory, keeping: ["LIVE"], now: now)

        #expect(Set(deleted.map(\.lastPathComponent)) == [oldOrphan.lastPathComponent, oldAside.lastPathComponent])
        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
        #expect(!exists(oldOrphan) && !exists(oldAside))
        #expect(exists(youngOrphan), "inside the grace period")
        #expect(exists(oldLive), "a live window's file is never an orphan, however old")
        #expect(exists(youngAside))
        for url in foreign { #expect(exists(url), "\(url.lastPathComponent) is not a recovery file") }
    }

    @Test func sweepingAMissingDirectoryDoesNothing() throws {
        let missing = try scratch().appendingPathComponent("absent", isDirectory: true)
        #expect(UntitledRecovery.sweepOrphans(in: missing, keeping: []).isEmpty)
    }

    /// Setting a file aside restarts its clock, so a sweep does not delete
    /// it for being as old as the recovery it came from.
    @Test func aFileSetAsideSurvivesTheNextSweep() throws {
        let directory = try scratch()
        let recovery = try #require(UntitledRecovery(key: "stale", in: directory))
        try Data("#usda 1.0\ndef Bogus \"X\"\n{\n}\n".utf8).write(to: recovery.url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-UntitledRecovery.orphanGracePeriod * 2)],
            ofItemAtPath: recovery.url.path
        )
        let session = StudioDocumentSession(model: StudioModel(document: StudioModel.sampleScene()))
        #expect(throws: (any Error).self) { try recovery.restore(into: session) }

        #expect(UntitledRecovery.sweepOrphans(in: directory, keeping: []).isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("stale.unreadable-") })
    }

    // MARK: Discarded sessions and adoption (ADR 0014)

    @Test func liveKeysDropDiscardedSessionsAndKeepThisProcessesWindows() {
        let live = UntitledRecovery.liveKeys(open: ["A", "B", "C"], discarded: ["B", "X"], active: ["K"])
        #expect(live == ["A", "C", "K"])
        #expect(UntitledRecovery.liveKeys(open: [], discarded: ["K"], active: ["K"]) == ["K"], "a window of this process stays live")
    }

    @Test func theNewestYoungOrphanIsAdoptable() throws {
        let directory = try scratch()
        let now = Date()
        let grace = UntitledRecovery.orphanGracePeriod
        _ = try plant("OLDER.usda", in: directory, age: 3600, now: now)
        let newest = try plant("NEWEST.usda", in: directory, age: 60, now: now)
        _ = try plant("LIVE.usda", in: directory, age: 1, now: now)
        _ = try plant("ASIDE.unreadable-1790000000.usda", in: directory, age: 1, now: now)
        _ = try plant("EXPIRED.usda", in: directory, age: grace + 60, now: now)
        _ = try plant("notes.usda.txt", in: directory, age: 1, now: now)

        let found = UntitledRecovery.newestAdoptable(in: directory, keeping: ["LIVE"], now: now)
        #expect(found?.lastPathComponent == newest.lastPathComponent)
        #expect(UntitledRecovery.newestAdoptable(in: directory, keeping: ["LIVE", "NEWEST", "OLDER"], now: now) == nil,
                "set-aside, expired, and foreign files are never adoptable")
    }

    @Test func adoptingMovesTheOrphanToTheWindowsOwnFileOnce() throws {
        let directory = try scratch()
        var edited = EditorSession()
        try edited.execute(CreateEntity(name: "Orphaned", components: [.transform(.identity)]))
        let orphan = directory.appendingPathComponent("GONE.usda")
        try StudioDocumentIO.write(edited.document, to: orphan)
        let bytes = try Data(contentsOf: orphan)
        let mine = try #require(UntitledRecovery(key: "MINE", in: directory))

        #expect(mine.adopt(orphan))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(try Data(contentsOf: mine.url) == bytes)
        #expect(!mine.adopt(orphan), "the orphan is gone")

        let other = directory.appendingPathComponent("ANOTHER.usda")
        try StudioDocumentIO.write(edited.document, to: other)
        #expect(!mine.adopt(other), "a window that has a recovery file adopts nothing")
        #expect(FileManager.default.fileExists(atPath: other.path))

        let session = StudioDocumentSession(model: StudioModel(document: StudioModel.sampleScene()))
        #expect(try mine.restore(into: session))
        #expect(session.model.session.document == edited.document)
        #expect(session.hasUnsavedChanges)
    }

    // MARK: The recovered notice (ADR 0015)

    func statusText(_ model: StudioModel) throws -> String {
        let frame = Size(width: 200, height: 40)
        var host = try FrameHost(app: StudioApp(model: model))
        var buffer = CellBuffer(size: frame)
        buffer.clearBack()
        CellPainter.paint(host.pump(size: frame), into: &buffer)
        return (0..<frame.height).map { buffer.rowText($0) }.joined(separator: "\n")
    }

    @Test func restoringLeavesANoticeSayingWhereTheChangesCameFrom() throws {
        let directory = try scratch()
        let before = StudioModel(document: StudioModel.sampleScene())
        before.addPrimitive(.box)
        for (key, adopted, notice) in [
            ("own", false, UntitledRecovery.restoredNotice),
            ("adopted", true, UntitledRecovery.adoptedNotice),
        ] {
            let recovery = try #require(UntitledRecovery(key: key, in: directory))
            try StudioDocumentIO.write(before.session.document, to: recovery.url)
            let model = StudioModel(document: StudioModel.sampleScene())
            #expect(try recovery.restore(into: StudioDocumentSession(model: model), adopted: adopted))
            #expect(model.notice == notice)
            #expect(try statusText(model).contains(notice))
        }
    }

    @Test func theNoticeClearsOnTheNextDocumentChange() throws {
        let directory = try scratch()
        let before = StudioModel(document: StudioModel.sampleScene())
        before.addPrimitive(.box)
        let recovery = try #require(UntitledRecovery(key: "clears", in: directory))
        try StudioDocumentIO.write(before.session.document, to: recovery.url)
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)
        #expect(try recovery.restore(into: session))

        model.select([])  // not a document change
        #expect(model.notice == UntitledRecovery.restoredNotice)
        model.addPrimitive(.sphere)
        #expect(model.notice == nil)
        #expect(try !statusText(model).contains(UntitledRecovery.restoredNotice))

        model.notice = "anything"
        model.undo()
        #expect(model.notice == nil, "undo is a document change")
        model.notice = "anything"
        model.replaceDocument(StudioModel.sampleScene())
        #expect(model.notice == nil, "so is opening")
    }

    @Test func aDocumentWithAFileGetsNoNotice() throws {
        let directory = try scratch()
        let recovery = try #require(UntitledRecovery(key: "hasfile", in: directory))
        try StudioDocumentIO.write(StudioModel.sampleScene(), to: recovery.url)
        let model = StudioModel(document: StudioModel.sampleScene())
        let session = StudioDocumentSession(model: model)
        try session.save(to: directory.appendingPathComponent("real.usda"))
        #expect(try recovery.restore(into: session) == false)
        #expect(model.notice == nil)
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
