//  StudioUIDocument.swift — GamaStudioEditor
//
//  The coordinated file behind a document on iOS and visionOS (ADR 0011).
//  UIDocument reads and writes the .usda through NSFileCoordinator, autosaves
//  in place, and hears when another process changes the file. It never
//  touches StudioModel: UIKit calls these overrides on its own queues, so
//  content crosses in both directions as SceneDocument values behind a
//  Mutex, and every event is delivered on the main actor.

#if canImport(UIKit) && canImport(RealityKit)

public import UIKit
public import GamaAuthoring
import GamaUSD
import Synchronization

/// A `.usda` file held open for coordinated reading, writing, and autosave.
/// `TouchDocumentController` owns it; the model stays the authority on
/// content, and this only carries values to and from the file.
///
/// Every mutable property lives in `shared`, behind a `Mutex`, and events
/// name the document by `ObjectIdentifier`, so nothing needs the document
/// itself to be `Sendable`.
public final class StudioUIDocument: UIDocument {
    /// What UIKit's queues and the main actor share.
    private struct State {
        /// The model's latest content, published from the main actor; what
        /// the next save writes.
        var current: SceneDocument
        /// Parsed by the last open or revert.
        var loaded: SceneDocument?
        /// The content of the save in flight.
        var written: SceneDocument?
        /// What the file held when this document last read or wrote it.
        var synced: SceneDocument?
        /// The last read, write, or save error UIKit reported, described
        /// for an alert.
        var lastError: String?
    }

    /// The lock, in a class so UIKit's completion handlers can hold it
    /// without holding the document.
    private final class Shared: Sendable {
        let state: Mutex<State>
        init(_ state: State) { self.state = Mutex(state) }
    }

    /// Delivered on the main actor, naming the document by identity: the
    /// overrides run on UIKit's queues, and an identifier crosses to the
    /// main actor without sending the document itself.
    struct Events: Sendable {
        /// A save (explicit or autosave) wrote this content.
        var saved: @MainActor @Sendable (ObjectIdentifier, SceneDocument) -> Void
        /// Another process changed the file (a coordinated write).
        var changedExternally: @MainActor @Sendable (ObjectIdentifier) -> Void
    }

    private let shared: Shared
    private let events: Events
    /// The URL whose security scope this document started, if it did.
    private let scopedURL: URL?

    /// Starts security-scoped access to `url` for the document's lifetime,
    /// as a file chosen in a picker or handed over by the system requires.
    /// `current` is what a save writes until ``publish(_:)`` replaces it.
    init(fileURL url: URL, current: SceneDocument, events: Events) {
        shared = Shared(State(current: current))
        self.events = events
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        super.init(fileURL: url)
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: Main-actor side

    /// Records the model's current content as what the next save writes.
    func publish(_ document: SceneDocument) {
        shared.state.withLock { $0.current = document }
    }

    /// The document parsed by the last successful open or revert.
    var loadedDocument: SceneDocument? {
        shared.state.withLock { $0.loaded }
    }

    /// The last error UIKit reported, described for an alert.
    var lastError: String? {
        shared.state.withLock { $0.lastError }
    }

    // MARK: UIKit overrides (any queue)

    public override func contents(forType typeName: String) throws -> Any {
        let document = shared.state.withLock { state in
            state.written = state.current
            return state.current
        }
        return Data(usdaString(from: document).utf8)
    }

    public override func load(fromContents contents: Any, ofType typeName: String?) throws {
        do {
            guard let data = contents as? Data else { throw CocoaError(.fileReadCorruptFile) }
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let document = try sceneDocument(fromUSDA: text)
            shared.state.withLock { state in
                state.loaded = document
                state.synced = document
            }
        } catch {
            shared.state.withLock { $0.lastError = StudioDocumentIO.describe(error) }
            throw error
        }
    }

    public override func save(
        to url: URL,
        for saveOperation: UIDocument.SaveOperation,
        completionHandler: (@Sendable (Bool) -> Void)? = nil
    ) {
        let id = ObjectIdentifier(self)
        let saved = events.saved
        super.save(to: url, for: saveOperation) { [shared] success in
            let written = shared.state.withLock { state in
                defer { state.written = nil }
                if success, let written = state.written { state.synced = written }
                return state.written
            }
            if success, let written {
                Task { @MainActor in saved(id, written) }
            }
            completionHandler?(success)
        }
    }

    public override func handleError(_ error: any Error, userInteractionPermitted: Bool) {
        shared.state.withLock { $0.lastError = StudioDocumentIO.describe(error) }
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }

    /// Reports a change only when the file's content differs from what this
    /// document last read or wrote: UIKit also calls this for the document's
    /// own saves (measured: an autosave arrived here 12 ms later).
    ///
    /// Deliberately does not call super: the controller decides whether to
    /// revert (no unsaved changes) or to ask (unsaved changes), instead of
    /// UIKit reverting on its own.
    public override func presentedItemDidChange() {
        // A coordinated read waits for a write in progress to finish. With
        // this document as the presenter, it is not asked to relinquish.
        var coordinationError: NSError?
        var onDisk: SceneDocument?
        // unsafe: the NSError out-parameter is an AutoreleasingUnsafeMutablePointer.
        unsafe NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            onDisk = try? sceneDocument(fromUSDA: text)
        }
        if let onDisk {
            let ours = shared.state.withLock { [$0.written, $0.synced].compactMap(\.self) }
            if ours.contains(where: { $0.hasSameContent(as: onDisk) }) { return }
        }
        let id = ObjectIdentifier(self)
        let changed = events.changedExternally
        Task { @MainActor in changed(id) }
    }
}

#endif
