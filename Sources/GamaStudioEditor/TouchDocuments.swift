//  TouchDocuments.swift — GamaStudioEditor
//
//  File open and save on iOS and visionOS (ADR 0009, ADR 0011): the system
//  document picker opens a .usda file in place, Save As exports a copy
//  through the picker, and once the document has a file a StudioUIDocument
//  holds it for coordinated reads and writes and autosaves it in place.
//  Content and saved state live in StudioDocumentSession, which macOS shares.

#if canImport(UIKit) && canImport(RealityKit)

public import UIKit
public import GamaAuthoring
import UniformTypeIdentifiers

/// Presents the pickers and prompts for ``StudioDocumentSession`` from a
/// view controller, and keeps the current file open as a
/// ``StudioUIDocument``.
@MainActor
public final class TouchDocumentController: NSObject, UIDocumentPickerDelegate {
    public let documents: StudioDocumentSession
    private weak var presenter: UIViewController?

    /// The coordinated current file; `nil` while the document is Untitled.
    /// It autosaves; an Untitled document has nowhere to autosave to.
    public private(set) var coordinated: StudioUIDocument?
    private var observers: [any NSObjectProtocol] = []
    /// Whether a saving error is already on screen, so one failure that
    /// keeps the document in `.savingError` reports once.
    private var reportedSavingError = false

    /// Where this window keeps an Untitled document's unsaved changes
    /// (ADR 0012); `nil` turns recovery off. Set before any edit.
    public var untitledRecovery: UntitledRecovery?
    /// The recovery file, held open for autosave while the document is
    /// Untitled with unsaved changes. Its saves never mark the model saved:
    /// the document is still Untitled.
    private var recovery: StudioUIDocument?
    /// Whether a failure to write the recovery file is already on screen.
    private var reportedRecoveryError = false

    /// What the picker on screen is for.
    private enum Pending {
        case open
        /// A copy written for export, and the content it holds.
        case export(file: URL, document: SceneDocument)
    }
    private var pending: Pending?
    /// Runs after a Save As that the unsaved-changes prompt started lands,
    /// for an open that must not be dropped (a file handed over by the
    /// system). Cleared when that picker is cancelled.
    private var afterExport: (@MainActor () -> Void)?

    /// Whether the "changed by another app" question is waiting for an
    /// answer (``resolveExternalChange(_:)``).
    public private(set) var isAskingAboutExternalChange = false

    /// Called after a picker, prompt, or coordinated open finishes, for
    /// tests and the host.
    public var onFinish: (@MainActor () -> Void)?
    /// Called after the current file, its saved state, or the document
    /// changes; the host updates its title here.
    public var onStateChange: (@MainActor () -> Void)?

    public init(documents: StudioDocumentSession, presenter: UIViewController) {
        self.documents = documents
        self.presenter = presenter
        super.init()
        documents.onStateChange = { [weak self] in self?.sessionStateChanged() }
    }

    /// The toolbar buttons' actions.
    public var actions: DocumentActions {
        DocumentActions(
            open: { [weak self] in self?.open() },
            save: { [weak self] in self?.save() },
            saveAs: { [weak self] in self?.saveAs() }
        )
    }

    static var contentTypes: [UTType] {
        [UTType(filenameExtension: StudioDocumentIO.fileExtension) ?? .data]
    }

    /// Hands the model's content to the coordinated file and tells UIKit
    /// whether it differs from the file, which schedules or cancels
    /// autosave. Undoing back to the saved content clears it.
    private func sessionStateChanged() {
        if let coordinated {
            coordinated.publish(documents.model.session.document)
            coordinated.updateChangeCount(documents.hasUnsavedChanges ? .done : .cleared)
        } else {
            keepRecovery()
        }
        onStateChange?()
    }

    // MARK: Untitled recovery (ADR 0012)

    /// Keeps the invariant: a recovery file exists only while the document
    /// is Untitled with unsaved changes. The first such change creates the
    /// file; later ones hand UIKit the content and let it autosave.
    private func keepRecovery() {
        guard let untitledRecovery else { return }
        guard documents.currentURL == nil, documents.hasUnsavedChanges else { return discardRecovery() }
        let content = documents.model.session.document
        if let recovery {
            recovery.publish(content)
            recovery.updateChangeCount(.done)
            return
        }
        let document = StudioUIDocument(
            fileURL: untitledRecovery.url,
            current: content,
            events: .init(saved: { _, _ in }, changedExternally: { _ in })
        )
        recovery = document
        try? FileManager.default.createDirectory(
            at: untitledRecovery.url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let operation: UIDocument.SaveOperation = untitledRecovery.exists ? .forOverwriting : .forCreating
        document.save(to: untitledRecovery.url, for: operation) { [weak self] success in
            Task { @MainActor in self?.recoveryCreated(success) }
        }
    }

    private func recoveryCreated(_ success: Bool) {
        guard !success, !reportedRecoveryError else { return }
        reportedRecoveryError = true
        report(
            recovery?.lastError ?? "The recovery file could not be written.",
            doing: "keep unsaved changes to \u{201C}\(documents.displayName)\u{201D} for the next launch"
        )
    }

    /// Closes the recovery file without saving and removes it, unless a new
    /// one was started meanwhile (an edit right after an undo).
    private func discardRecovery() {
        guard let untitledRecovery else { return }
        guard let document = recovery else {
            // Restored at launch but never reopened, or already closed.
            return untitledRecovery.discard()
        }
        recovery = nil
        document.updateChangeCount(.cleared)
        document.close { [weak self] _ in
            Task { @MainActor in
                if self?.recovery == nil { untitledRecovery.discard() }
            }
        }
    }

    /// Reports a recovery file that could not be read at launch, which was
    /// set aside rather than deleted (ADR 0012).
    public func reportUnrecoverable(_ error: any Error) {
        report(error, doing: "recover unsaved changes to \u{201C}\(documents.displayName)\u{201D}")
    }

    // MARK: Actions

    /// Saves pending changes, or asks about them when Untitled, then shows
    /// the picker for a file to open in place.
    public func open() {
        confirmDiscardingChanges { [weak self] in
            guard let self else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.contentTypes, asCopy: false)
            self.present(picker, for: .open)
        }
    }

    /// Opens a file the system handed over (Files, the share sheet, another
    /// app) in place (ADR 0010). Unlike ``open()``, a Save As started by the
    /// Untitled prompt resumes the open once it lands, because the file
    /// cannot be picked again.
    public func openExternally(_ url: URL) {
        confirmDiscardingChanges(resumingAfterSaveAs: true) { [weak self] in
            self?.openCoordinated(url)
        }
    }

    /// Saves the current file now, or asks where when Untitled. With a file,
    /// autosave would write it soon anyway; this does not wait.
    public func save() {
        guard let coordinated else { return saveAs() }
        coordinated.save(to: coordinated.fileURL, for: .forOverwriting)
    }

    /// Exports a copy through the picker; the chosen location becomes the
    /// current file, and autosave moves there with it.
    public func saveAs() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GamaStudioExport-\(UUID().uuidString)")
        do {
            let (file, document) = try documents.writeCopyForExport(in: directory)
            let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
            present(picker, for: .export(file: file, document: document))
        } catch {
            afterExport = nil
            report(error, doing: "save \u{201C}\(documents.displayName)\u{201D}")
        }
    }

    // MARK: Coordinated file

    private func makeDocument(_ url: URL) -> StudioUIDocument {
        StudioUIDocument(
            fileURL: url,
            current: documents.model.session.document,
            events: .init(
                saved: { [weak self] id, written in self?.coordinatedFileSaved(id, written) },
                changedExternally: { [weak self] id in self?.coordinatedFileChanged(id) }
            )
        )
    }

    /// What a document being opened is for.
    private enum Opening {
        /// Read it into the model; it becomes the current file.
        case open
        /// A Save As copy: hold it without reading it into the model, then
        /// run the resumed action, if any.
        case attach(resume: (@MainActor () -> Void)?)
    }
    /// Documents whose open is in flight, by identity. Completion handlers
    /// carry the identifier to the main actor instead of the document.
    private var opening: [ObjectIdentifier: (document: StudioUIDocument, purpose: Opening)] = [:]

    /// Opens `url` with a coordinated read and makes it the current file.
    /// On failure the previous file stays open and current.
    func openCoordinated(_ url: URL) {
        beginOpening(url, for: .open)
    }

    /// Holds a freshly exported copy at `url` as the current file without
    /// reading it into the model, so an edit made while the picker was open
    /// survives and autosaves there.
    private func attach(_ url: URL, then resume: (@MainActor () -> Void)?) {
        beginOpening(url, for: .attach(resume: resume))
    }

    private func beginOpening(_ url: URL, for purpose: Opening) {
        let document = makeDocument(url)
        let id = ObjectIdentifier(document)
        opening[id] = (document, purpose)
        document.open { [weak self] success in
            Task { @MainActor in self?.finishOpening(id, success: success) }
        }
    }

    private func finishOpening(_ id: ObjectIdentifier, success: Bool) {
        guard let (document, purpose) = opening.removeValue(forKey: id) else { return }
        let failure = document.lastError ?? "The file could not be read."
        let action = "open \u{201C}\(document.fileURL.lastPathComponent)\u{201D}"
        switch purpose {
        case .open:
            defer { onFinish?() }
            guard success, let loaded = document.loadedDocument else { return report(failure, doing: action) }
            becomeCurrent(document, savingPrevious: true)
            documents.adoptOpened(loaded, from: document.fileURL)
        case .attach(let resume):
            guard success else {
                // The copy is the current file now, so the previous file
                // must not stay coordinated: it would autosave there.
                detach()
                return report(failure, doing: action)
            }
            // Save As leaves the previous file as it was last saved.
            becomeCurrent(document, savingPrevious: false)
            sessionStateChanged()
            resume?()
        }
    }

    /// Makes `document` the coordinated current file and closes the previous
    /// one: closing autosaves it unless `savingPrevious` is false.
    private func becomeCurrent(_ document: StudioUIDocument, savingPrevious: Bool) {
        // The document has a file now: Untitled changes are either in it
        // (Save As) or were given up (Don't Save).
        discardRecovery()
        let previous = coordinated
        coordinated = document
        reportedSavingError = false
        observers.forEach(NotificationCenter.default.removeObserver)
        let id = ObjectIdentifier(document)
        observers = [
            NotificationCenter.default.addObserver(
                forName: UIDocument.stateChangedNotification, object: document, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.coordinatedStateChanged(id) }
            },
        ]
        if #available(iOS 26.0, visionOS 26.0, *) {
            observers.append(NotificationCenter.default.addObserver(
                forName: UIDocument.didMoveToWritableLocationNotification, object: document, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.coordinatedFileMoved(id) }
            })
        }
        if let previous, previous !== document {
            if !savingPrevious { previous.updateChangeCount(.cleared) }
            previous.close()
        }
    }

    /// Closes the coordinated file without saving; the document keeps its
    /// content, and Save then asks where.
    private func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        coordinated?.updateChangeCount(.cleared)
        coordinated?.close()
        coordinated = nil
    }

    /// The coordinated file, if `id` names it; events from a document that
    /// was replaced since are ignored.
    private func current(_ id: ObjectIdentifier) -> StudioUIDocument? {
        guard let coordinated, ObjectIdentifier(coordinated) == id else { return nil }
        return coordinated
    }

    private func coordinatedFileSaved(_ id: ObjectIdentifier, _ written: SceneDocument) {
        guard let document = current(id) else { return }
        documents.adoptSavedCopy(at: document.fileURL, of: written)
    }

    private func coordinatedFileMoved(_ id: ObjectIdentifier) {
        guard let document = current(id) else { return }
        documents.fileMoved(to: document.fileURL)
    }

    private func coordinatedStateChanged(_ id: ObjectIdentifier) {
        guard let document = current(id) else { return }
        if document.documentState.contains(.savingError) {
            guard !reportedSavingError else { return }
            reportedSavingError = true
            report(document.lastError ?? "The file could not be written.", doing: "save \u{201C}\(documents.displayName)\u{201D}")
        } else {
            reportedSavingError = false
        }
    }

    // MARK: Changes from other apps

    /// What to do when another app changed the file while there were
    /// unsaved changes here.
    public enum ExternalChangeChoice: Sendable {
        /// Load the file, discarding the unsaved changes (not undoable).
        case revert
        /// Keep this version; the next save overwrites the file.
        case keepMine
    }

    /// Reloads the file when there is nothing unsaved, and asks otherwise.
    private func coordinatedFileChanged(_ id: ObjectIdentifier) {
        guard let document = current(id), !isAskingAboutExternalChange else { return }
        guard documents.hasUnsavedChanges else { return revertToFile(document) }
        isAskingAboutExternalChange = true
        let alert = UIAlertController(
            title: "\u{201C}\(documents.displayName)\u{201D} was changed by another app.",
            message: "Revert to that version, or keep yours? Keeping yours replaces the file when it next saves.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Revert", style: .destructive) { [weak self] _ in
            self?.resolveExternalChange(.revert)
        })
        alert.addAction(UIAlertAction(title: "Keep Mine", style: .default) { [weak self] _ in
            self?.resolveExternalChange(.keepMine)
        })
        presenter?.present(alert, animated: true)
    }

    /// Answers the "changed by another app" question. The alert's buttons
    /// call this; so does the launch smoke check.
    public func resolveExternalChange(_ choice: ExternalChangeChoice) {
        guard isAskingAboutExternalChange else { return }
        isAskingAboutExternalChange = false
        guard let coordinated else { return }
        switch choice {
        case .revert: revertToFile(coordinated)
        case .keepMine: coordinated.updateChangeCount(.done)
        }
    }

    private func revertToFile(_ document: StudioUIDocument) {
        let id = ObjectIdentifier(document)
        document.revert(toContentsOf: document.fileURL) { [weak self] success in
            Task { @MainActor in self?.finishReverting(id, success: success) }
        }
    }

    private func finishReverting(_ id: ObjectIdentifier, success: Bool) {
        guard let document = current(id) else { return }
        defer { onFinish?() }
        guard success, let loaded = document.loadedDocument else {
            return report(document.lastError ?? "The file could not be read.", doing: "reload \u{201C}\(documents.displayName)\u{201D}")
        }
        if documents.model.session.document.hasSameContent(as: loaded) {
            documents.adoptSavedCopy(at: document.fileURL, of: loaded)
        } else {
            documents.adoptOpened(loaded, from: document.fileURL)
        }
    }

    // MARK: Picker

    private func present(_ picker: UIDocumentPickerViewController, for purpose: Pending) {
        pending = purpose
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter?.present(picker, animated: true)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let purpose = pending
        pending = nil
        defer { finish(purpose) }
        guard let url = urls.first else { return }
        switch purpose {
        case .open?:
            openCoordinated(url)
        case .export(_, let document)?:
            documents.adoptSavedCopy(at: url, of: document)
            let resume = afterExport
            afterExport = nil
            attach(url, then: resume)
        case nil:
            break
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let purpose = pending
        pending = nil
        afterExport = nil
        finish(purpose)
    }

    /// Removes an export's temporary copy and reports completion.
    private func finish(_ purpose: Pending?) {
        if case .export(let file, _)? = purpose {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
        onFinish?()
    }

    // MARK: Prompts

    /// Runs `proceed` once nothing would be lost. With a file, pending
    /// changes are saved first, without asking, as autosave would. Untitled
    /// with changes asks Save / Don't Save / Cancel; Save starts Save As,
    /// and the pending action then waits for the user to try again, or, with
    /// `resumingAfterSaveAs`, runs once that Save As lands.
    func confirmDiscardingChanges(
        resumingAfterSaveAs: Bool = false,
        then proceed: @escaping @MainActor () -> Void
    ) {
        if let coordinated {
            guard coordinated.hasUnsavedChanges else { return proceed() }
            coordinated.save(to: coordinated.fileURL, for: .forOverwriting) { success in
                Task { @MainActor in
                    // A failure is reported through the savingError state.
                    if success { proceed() }
                }
            }
            return
        }
        guard documents.hasUnsavedChanges else { return proceed() }
        let alert = UIAlertController(
            title: "Save changes to \u{201C}\(documents.displayName)\u{201D}?",
            message: "Your changes will be lost if you don\u{2019}t save them.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            if resumingAfterSaveAs { self.afterExport = proceed }
            self.saveAs()
        })
        alert.addAction(UIAlertAction(title: "Don\u{2019}t Save", style: .destructive) { _ in proceed() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presenter?.present(alert, animated: true)
    }

    private func report(_ error: any Error, doing action: String) {
        report(StudioDocumentIO.describe(error), doing: action)
    }

    private func report(_ message: String, doing action: String) {
        let alert = UIAlertController(
            title: "Couldn\u{2019}t \(action).",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter?.present(alert, animated: true)
    }
}

#endif
