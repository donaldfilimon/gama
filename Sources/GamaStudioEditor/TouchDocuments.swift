//  TouchDocuments.swift — GamaStudioEditor
//
//  File open and save on iOS and visionOS (ADR 0009): the system document
//  picker opens a .usda file in place, and Save As exports a copy through
//  the picker. Everything that is not presentation lives in
//  StudioDocumentSession, which macOS shares.

#if canImport(UIKit) && canImport(RealityKit)

public import UIKit
public import GamaAuthoring
import UniformTypeIdentifiers

/// Presents the pickers and prompts for ``StudioDocumentSession`` from a
/// view controller.
@MainActor
public final class TouchDocumentController: NSObject, UIDocumentPickerDelegate {
    public let documents: StudioDocumentSession
    private weak var presenter: UIViewController?

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

    /// Called after a picker or prompt finishes, for tests and the host.
    public var onFinish: (@MainActor () -> Void)?

    public init(documents: StudioDocumentSession, presenter: UIViewController) {
        self.documents = documents
        self.presenter = presenter
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

    // MARK: Actions

    /// Asks about unsaved changes, then shows the picker for a file to open
    /// in place.
    public func open() {
        confirmDiscardingChanges { [weak self] in
            guard let self else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.contentTypes, asCopy: false)
            self.present(picker, for: .open)
        }
    }

    /// Opens a file the system handed over (Files, the share sheet, another
    /// app) in place, after the unsaved-changes prompt (ADR 0010). Unlike
    /// ``open()``, a Save As started by that prompt resumes the open once it
    /// lands, because the file cannot be picked again.
    public func openExternally(_ url: URL) {
        confirmDiscardingChanges(resumingAfterSaveAs: true) { [weak self] in
            guard let self else { return }
            do {
                try self.documents.open(url)
            } catch {
                self.report(error, doing: "open \u{201C}\(url.lastPathComponent)\u{201D}")
            }
            self.onFinish?()
        }
    }

    /// Writes to the current file, or asks where when there is none yet.
    public func save() {
        do {
            if try !documents.saveToCurrentFile() { saveAs() }
        } catch {
            report(error, doing: "save \u{201C}\(documents.displayName)\u{201D}")
        }
    }

    /// Exports a copy through the picker; the chosen location becomes the
    /// current file.
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
            do {
                try documents.open(url)
            } catch {
                report(error, doing: "open \u{201C}\(url.lastPathComponent)\u{201D}")
            }
        case .export(_, let document)?:
            documents.adoptSavedCopy(at: url, of: document)
            let resume = afterExport
            afterExport = nil
            resume?()
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

    /// Runs `proceed` when nothing is unsaved, or after the user saves or
    /// chooses to discard. With no current file, Save starts Save As instead;
    /// the pending action then waits for the user to try again, or, with
    /// `resumingAfterSaveAs`, runs once that Save As lands.
    func confirmDiscardingChanges(
        resumingAfterSaveAs: Bool = false,
        then proceed: @escaping @MainActor () -> Void
    ) {
        guard documents.hasUnsavedChanges else { return proceed() }
        let alert = UIAlertController(
            title: "Save changes to \u{201C}\(documents.displayName)\u{201D}?",
            message: "Your changes will be lost if you don\u{2019}t save them.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            do {
                if try self.documents.saveToCurrentFile() {
                    proceed()
                } else {
                    if resumingAfterSaveAs { self.afterExport = proceed }
                    self.saveAs()
                }
            } catch {
                self.report(error, doing: "save \u{201C}\(self.documents.displayName)\u{201D}")
            }
        })
        alert.addAction(UIAlertAction(title: "Don\u{2019}t Save", style: .destructive) { _ in proceed() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presenter?.present(alert, animated: true)
    }

    private func report(_ error: any Error, doing action: String) {
        let alert = UIAlertController(
            title: "Couldn\u{2019}t \(action).",
            message: StudioDocumentIO.describe(error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter?.present(alert, animated: true)
    }
}

#endif
