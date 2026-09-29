//  ExportedFileTests.swift — GamaStudioEditorTests
//
//  Resolving what an export picker handed back to the exported file
//  (ADR 0019). On iOS, "Keep Both" in the Replace Existing Item dialog
//  returns the destination folder instead of the copy; only a regular file,
//  or the one fresh copy inside that folder, may become the current file.

import Foundation
import GamaStudioEditor
import Testing

@Suite("Exported file resolution")
struct ExportedFileTests {
    /// A destination folder and a temporary export copy beside it, written
    /// after `began`.
    struct Fixture {
        let began: Date
        let destination: URL
        let export: URL
        let bytes = Data("#usda 1.0\n( doc = \"exported\" )\n".utf8)

        init() throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("gama-studio-exported-\(UUID().uuidString)")
            began = Date()
            destination = root.appendingPathComponent("File Provider Storage", isDirectory: false)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let temporary = root.appendingPathComponent("export")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            export = temporary.appendingPathComponent("Untitled.usda")
            try bytes.write(to: export)
        }

        /// Copies the export into the destination as `name`, as the picker does.
        @discardableResult
        func copy(as name: String) throws -> URL {
            let url = destination.appendingPathComponent(name)
            try bytes.write(to: url)
            return url
        }

        func age(_ url: URL, by seconds: TimeInterval) throws {
            try FileManager.default.setAttributes(
                [.modificationDate: began.addingTimeInterval(-seconds)], ofItemAtPath: url.path
            )
        }

        func resolve(_ picked: URL) -> Result<URL, ExportedFile.Failure> {
            ExportedFile.resolve(picked: picked, export: export, notBefore: began)
        }
    }

    @Test func aFolderURLWithoutATrailingSlashIsStillAFolder() throws {
        let fixture = try Fixture()
        #expect(!fixture.destination.hasDirectoryPath)
        #expect(ExportedFile.isDirectory(fixture.destination))
        #expect(!ExportedFile.isDirectory(fixture.export))
    }

    @Test func aPickedFileIsTheAnswer() throws {
        let fixture = try Fixture()
        let copy = try fixture.copy(as: "Untitled.usda")
        #expect(fixture.resolve(copy) == .success(copy))
    }

    @Test func nothingAtThePickedURLFails() throws {
        let fixture = try Fixture()
        let missing = fixture.destination.appendingPathComponent("Untitled.usda")
        #expect(fixture.resolve(missing) == .failure(.missing(missing)))
    }

    @Test func aFolderResolvesToTheFreshCopyNamedLikeTheExport() throws {
        let fixture = try Fixture()
        let copy = try fixture.copy(as: "Untitled.usda")
        try fixture.copy(as: "Untitled 2.usda")
        #expect(fixture.resolve(fixture.destination) == .success(copy), "the export's own name wins")
    }

    @Test func aFolderResolvesToTheOnlyRenamedCopy() throws {
        let fixture = try Fixture()
        let copy = try fixture.copy(as: "Untitled 2.usda")
        #expect(fixture.resolve(fixture.destination) == .success(copy))
    }

    @Test func aFolderWithoutTheCopyFails() throws {
        let fixture = try Fixture()
        #expect(fixture.resolve(fixture.destination) == .failure(.folderWithoutTheCopy(fixture.destination)))
    }

    @Test func aStaleFileWithTheSameBytesIsNotTheCopy() throws {
        let fixture = try Fixture()
        let stale = try fixture.copy(as: "Untitled.usda")
        try fixture.age(stale, by: 60)
        #expect(fixture.resolve(fixture.destination) == .failure(.folderWithoutTheCopy(fixture.destination)))
    }

    @Test func aCopyWithinTheTimestampSlackStillCounts() throws {
        let fixture = try Fixture()
        let copy = try fixture.copy(as: "Untitled.usda")
        try fixture.age(copy, by: ExportedFile.timestampSlack / 2)
        #expect(fixture.resolve(fixture.destination) == .success(copy))
    }

    @Test func aFreshFileWithOtherBytesIsNotTheCopy() throws {
        let fixture = try Fixture()
        let other = fixture.destination.appendingPathComponent("Untitled.usda")
        try Data("#usda 1.0\n".utf8).write(to: other)
        #expect(fixture.resolve(fixture.destination) == .failure(.folderWithoutTheCopy(fixture.destination)))
    }

    @Test func twoRenamedCopiesAreAmbiguous() throws {
        let fixture = try Fixture()
        try fixture.copy(as: "Untitled 3.usda")
        try fixture.copy(as: "Untitled 2.usda")
        #expect(
            fixture.resolve(fixture.destination)
                == .failure(.ambiguous(fixture.destination, candidates: ["Untitled 2.usda", "Untitled 3.usda"]))
        )
    }

    @Test func aFileWithAnotherExtensionIsNotTheCopy() throws {
        let fixture = try Fixture()
        try fixture.copy(as: "Untitled.txt")
        #expect(fixture.resolve(fixture.destination) == .failure(.folderWithoutTheCopy(fixture.destination)))
    }

    @Test func failuresSayWhatCameBack() throws {
        let fixture = try Fixture()
        let text = ExportedFile.Failure.folderWithoutTheCopy(fixture.destination).description
        #expect(text.contains("File Provider Storage"))
        #expect(text.contains("folder"))
    }
}
