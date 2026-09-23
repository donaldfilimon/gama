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
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard !key.isEmpty, key.count <= 64, key.allSatisfy(allowed.contains) else { return nil }
        url = directory.appendingPathComponent("\(key).\(StudioDocumentIO.fileExtension)")
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
    }
}

#endif
