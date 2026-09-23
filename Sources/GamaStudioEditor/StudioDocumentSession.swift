//  StudioDocumentSession.swift — GamaStudioEditor
//
//  The platform-neutral half of opening and saving (ADR 0005, ADR 0009):
//  which file the document belongs to, reading and writing it with
//  security-scoped access, and the saved state. The macOS File menu
//  (StudioAppDelegate) and the iOS/visionOS document pickers
//  (TouchDocumentController) both drive this, and only present UI themselves.

#if canImport(RealityKit)

public import Foundation
public import GamaAuthoring

/// Where the current document lives, and the operations on it.
@MainActor
public final class StudioDocumentSession {
    public let model: StudioModel
    /// Where the document was last opened from or saved to; `nil` until then.
    public private(set) var currentURL: URL?
    /// Called after the current file or its saved state changes, and after
    /// every document edit, so a host can update its title and edited mark.
    public var onStateChange: (@MainActor () -> Void)?

    /// Wraps `model`, whose document came from `url` when it was opened from
    /// a file. Chains ``StudioModel/onDocumentChange`` so an edit updates the
    /// edited mark.
    public init(model: StudioModel, url: URL? = nil) {
        self.model = model
        self.currentURL = url
        let previous = model.onDocumentChange
        model.onDocumentChange = { [weak self] in
            previous?()
            self?.onStateChange?()
        }
    }

    /// The current file's name, or "Untitled.usda" before the first save.
    public var displayName: String {
        currentURL?.lastPathComponent ?? "Untitled.\(StudioDocumentIO.fileExtension)"
    }

    /// Whether the document differs from what was last opened or saved.
    public var hasUnsavedChanges: Bool { model.hasUnsavedChanges }

    /// Reads `url` and replaces the model's document with it (not undoable).
    /// The previous document and file are untouched when reading fails.
    public func open(_ url: URL) throws {
        let document = try Self.withAccess(to: url) { () throws -> SceneDocument in
            try StudioDocumentIO.read(from: url)
        }
        // The file changes first, so the one notification replaceDocument
        // sends (through onDocumentChange) already names the new file.
        currentURL = url
        model.replaceDocument(document)
    }

    /// Writes the document to `url`, which becomes the current file.
    public func save(to url: URL) throws {
        let document = model.session.document
        try Self.withAccess(to: url) { () throws in
            try StudioDocumentIO.write(document, to: url)
        }
        adoptSavedCopy(at: url, of: document)
    }

    /// Writes the document to the current file. Returns `false`, writing
    /// nothing, when there is no current file yet: the caller asks where.
    @discardableResult
    public func saveToCurrentFile() throws -> Bool {
        guard let currentURL else { return false }
        try save(to: currentURL)
        return true
    }

    /// Writes the document to a new file named ``displayName`` in
    /// `directory` (normally a temporary one), for a picker that copies a
    /// file to where the user chooses. Returns the file and the document it
    /// holds, to pass to ``adoptSavedCopy(at:of:)`` once the copy lands.
    public func writeCopyForExport(in directory: URL) throws -> (url: URL, document: SceneDocument) {
        let document = model.session.document
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(displayName)
        try StudioDocumentIO.write(document, to: url)
        return (url, document)
    }

    /// Records that `document` now lives at `url`: it becomes the current
    /// file, and the model counts as saved when it still holds that content
    /// (an edit made while a picker was open stays unsaved).
    public func adoptSavedCopy(at url: URL, of document: SceneDocument) {
        currentURL = url
        if model.session.document.hasSameContent(as: document) {
            model.markSaved()
        }
        onStateChange?()
    }

    /// Runs `body` with security-scoped access to `url`, as a file chosen in a
    /// document picker requires on iOS and visionOS. Outside a sandbox the
    /// start call returns `false` and access simply proceeds.
    static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}

/// What the toolbar's file buttons do, injected by a host that has file UI
/// (the touch hosts). `nil` in ``StudioApp`` hides the buttons, as on macOS,
/// where the File menu does this job.
public struct DocumentActions: Sendable {
    public let open: @MainActor @Sendable () -> Void
    public let save: @MainActor @Sendable () -> Void
    public let saveAs: @MainActor @Sendable () -> Void

    public init(
        open: @escaping @MainActor @Sendable () -> Void,
        save: @escaping @MainActor @Sendable () -> Void,
        saveAs: @escaping @MainActor @Sendable () -> Void
    ) {
        self.open = open
        self.save = save
        self.saveAs = saveAs
    }
}

#endif
