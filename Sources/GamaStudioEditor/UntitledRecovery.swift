//  UntitledRecovery.swift — GamaStudioEditor
//
//  Where an Untitled document's unsaved changes are kept between launches
//  (ADR 0012): one private .usda per window, named by a key the host keeps
//  for that window. This file finds, restores, and removes it; on iOS and
//  visionOS, TouchDocumentController writes it through a StudioUIDocument so
//  UIKit autosaves it. Platform-neutral so macOS tests cover it.

#if canImport(RealityKit)

public import Foundation
import GamaAuthoring

/// The recovery file of one window's Untitled document.
public struct UntitledRecovery: Sendable, Hashable {
    /// Where the file is, whether or not it exists yet.
    public let url: URL

    /// The file for `key` in `directory`, or `nil` when `key` could name
    /// anything but a plain file there: only ASCII letters, digits, and `-`
    /// are allowed, as in a UUID string.
    public init?(key: String, in directory: URL) {
        guard Self.isValidKey(key) else { return nil }
        url = directory.appendingPathComponent("\(key).\(StudioDocumentIO.fileExtension)")
    }

    private static func isValidKey(_ key: some StringProtocol) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return !key.isEmpty && key.count <= 64 && key.allSatisfy(allowed.contains)
    }

    /// How long a recovery file whose window is gone is kept before
    /// ``sweepOrphans(in:keeping:now:gracePeriod:)`` deletes it (ADR 0013).
    public static let orphanGracePeriod: TimeInterval = 7 * 24 * 60 * 60

    /// Deletes recovery files no window will restore any more (ADR 0013):
    /// a `<key>.usda` whose key is not in `liveKeys`, or a
    /// `<key>.unreadable-<time>.usda` set aside after a failed restore, once
    /// it has gone unmodified for `gracePeriod`. The grace period covers a
    /// window the system brings back. Files with any other name are never
    /// touched. Returns what was deleted.
    @discardableResult
    public static func sweepOrphans(
        in directory: URL,
        keeping liveKeys: Set<String>,
        now: Date = Date(),
        gracePeriod: TimeInterval = orphanGracePeriod
    ) -> [URL] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return [] }
        let suffix = ".\(StudioDocumentIO.fileExtension)"
        var deleted: [URL] = []
        for name in names where name.hasSuffix(suffix) {
            let stem = name.dropLast(suffix.count)
            let parts = stem.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first, isValidKey(key) else { continue }
            if parts.count == 2 {
                // Only a set-aside file may carry a second part.
                guard parts[1].hasPrefix("unreadable-") else { continue }
            } else if liveKeys.contains(String(key)) {
                continue
            }
            let url = directory.appendingPathComponent(name)
            guard let modified = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) >= gracePeriod
            else { continue }
            if (try? manager.removeItem(at: url)) != nil { deleted.append(url) }
        }
        return deleted
    }

    /// `Application Support/GamaStudio Recovery`: private to the app, never
    /// shown in Files.
    public static func defaultDirectory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("GamaStudio Recovery", isDirectory: true)
    }

    /// Whether there are changes to recover.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Restores the recovered changes into `session`, which must still be
    /// Untitled. Returns `false`, changing nothing, when there is no file.
    ///
    /// A file that cannot be read is moved aside, to
    /// `<key>.unreadable-<time>.usda` beside it, so it is neither lost nor
    /// overwritten by the next autosave, and the error is rethrown with the
    /// document untouched.
    @MainActor
    public func restore(into session: StudioDocumentSession) throws -> Bool {
        guard exists else { return false }
        let document: SceneDocument
        do {
            document = try StudioDocumentIO.read(from: url)
        } catch {
            moveAside()
            throw error
        }
        session.restoreUntitled(document)
        return true
    }

    /// Removes the file. Harmless when it is already gone.
    public func discard() {
        try? FileManager.default.removeItem(at: url)
    }

    private func moveAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        let base = url.deletingPathExtension().lastPathComponent
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).unreadable-\(stamp).\(StudioDocumentIO.fileExtension)")
        try? FileManager.default.moveItem(at: url, to: aside)
        // A rename keeps the old modification date; the grace period before
        // an orphan sweep deletes it starts now (ADR 0013).
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: aside.path)
    }
}

#endif
