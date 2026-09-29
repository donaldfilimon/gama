//  ExportedFile.swift — GamaStudioEditor
//
//  Where a Save As copy actually landed (ADR 0019). The export picker is
//  meant to hand back the copied file, but on iOS it has handed back the
//  folder it was copied into. Only a regular file may become the current
//  file; a folder resolves to the copy inside it only when that copy is
//  provably the one just exported. Platform-neutral, so macOS tests it.

public import Foundation

/// Resolves the URL an export picker returned to the exported file.
public enum ExportedFile {
    /// How far a copy's modification date may precede `notBefore` and still
    /// count, for file systems that store coarser timestamps than `Date`.
    public static let timestampSlack: TimeInterval = 1

    /// Why a picked URL could not be taken as the exported file.
    public enum Failure: Error, Equatable, Sendable {
        /// Nothing exists at the picked URL.
        case missing(URL)
        /// The picked URL is a folder, and no file in it is the copy just
        /// exported (same bytes, written since the export began).
        case folderWithoutTheCopy(URL)
        /// The picked URL is a folder holding more than one file that
        /// matches the export, so which one is the copy is unknowable.
        case ambiguous(URL, candidates: [String])
    }

    /// Whether `url` names a directory. The resource value wins; a URL whose
    /// resource values cannot be read falls back to its trailing slash.
    public static func isDirectory(_ url: URL) -> Bool {
        if let value = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory {
            return value
        }
        return url.hasDirectoryPath
    }

    /// The exported file behind `picked`.
    ///
    /// - A regular file is the answer as it is.
    /// - A folder resolves to the one file in it that holds exactly the
    ///   bytes of `export` (the temporary copy handed to the picker) and was
    ///   modified at or after `notBefore` (when the export began, less
    ///   ``timestampSlack``). The file
    ///   named like the export is preferred; a renamed copy ("Keep Both") is
    ///   accepted only when it is the only match.
    /// - Anything else fails; the caller keeps its current file.
    ///
    /// Call it with security-scoped access to `picked` already started.
    public static func resolve(
        picked: URL,
        export: URL,
        notBefore: Date,
        fileManager: FileManager = .default
    ) -> Result<URL, Failure> {
        guard fileManager.fileExists(atPath: picked.path) else { return .failure(.missing(picked)) }
        guard isDirectory(picked) else { return .success(picked) }
        guard let expected = try? Data(contentsOf: export) else {
            return .failure(.folderWithoutTheCopy(picked))
        }
        func isTheCopy(_ candidate: URL) -> Bool {
            guard let values = try? candidate.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            ), values.isRegularFile == true,
                let modified = values.contentModificationDate,
                modified >= notBefore.addingTimeInterval(-timestampSlack)
            else { return false }
            return (try? Data(contentsOf: candidate)) == expected
        }
        let named = picked.appendingPathComponent(export.lastPathComponent, isDirectory: false)
        if isTheCopy(named) { return .success(named) }
        // Names only, rebuilt under `picked`: the listing spells paths its
        // own way, and the answer must stay inside the picked, security-
        // scoped URL.
        let names = (try? fileManager.contentsOfDirectory(atPath: picked.path)) ?? []
        let matches = names.sorted()
            .map { picked.appendingPathComponent($0, isDirectory: false) }
            .filter { $0.pathExtension == export.pathExtension && isTheCopy($0) }
        switch matches.count {
        case 1: return .success(matches[0])
        case 0: return .failure(.folderWithoutTheCopy(picked))
        default: return .failure(.ambiguous(picked, candidates: matches.map(\.lastPathComponent)))
        }
    }
}

extension ExportedFile.Failure: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missing(let url):
            "Nothing was saved at \u{201C}\(url.lastPathComponent)\u{201D}."
        case .folderWithoutTheCopy(let url):
            "The save location came back as the folder \u{201C}\(url.lastPathComponent)\u{201D}, and no file in it is the copy just saved."
        case .ambiguous(let url, let candidates):
            "The save location came back as the folder \u{201C}\(url.lastPathComponent)\u{201D}, and more than one file in it matches the copy just saved (\(candidates.joined(separator: ", ")))."
        }
    }
}
