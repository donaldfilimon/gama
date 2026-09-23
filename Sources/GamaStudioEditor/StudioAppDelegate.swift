//  StudioAppDelegate.swift — GamaStudioEditor
//
//  The app-lifecycle half of hosting Gama Studio: without an
//  `NSApplicationDelegate`, AppKit's default is to keep the process alive
//  after its last window closes, leaving a windowless `gama-studio` running.
//  This lives in the library (not `Sources/gama-studio/main.swift`) so
//  `GamaStudioEditorTests` can exercise it directly — an executable target
//  can't be imported by a test target.

#if canImport(AppKit)

public import AppKit
public import Foundation
import GamaAuthoring
import UniformTypeIdentifiers

/// Terminates `gama-studio` when its one window closes, instead of AppKit's
/// default of leaving a windowless process running, and owns the File menu:
/// Open, Save, and Save As over `.usda` files (ADR 0005).
///
/// The executable holds one instance strongly for the process's lifetime
/// (`NSApplication.delegate` itself is a weak reference), and sets it with
/// `NSApplication.shared.delegate = appDelegate` before the window is shown.
@MainActor
public final class StudioAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public override init() {
        super.init()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Documents

    /// The file operations the menu drives (ADR 0009); `nil` until attached.
    public private(set) var documents: StudioDocumentSession?
    /// The model whose document the File menu opens and saves.
    public var model: StudioModel? { documents?.model }
    /// The window whose title, proxy icon, and edited dot follow the document.
    public private(set) weak var window: NSWindow?
    /// Where the document was last opened from or saved to; `nil` until then.
    public var currentURL: URL? { documents?.currentURL }
    /// Asks the Gama host to repaint. A File-menu action arrives from AppKit,
    /// outside the host's own action path, so without this the panels would
    /// keep showing the previous document until the next input event.
    private var redraw: @MainActor () -> Void = {}
    /// Set once the user has already answered the save prompt for closing the
    /// window, so the quit that follows does not ask again.
    private var closeConfirmed = false

    /// Connects the File menu to `model` and `window` and becomes the
    /// window's delegate, so closing it asks about unsaved changes. `url` is
    /// where the model's document came from, if a file; `redraw` repaints the
    /// Gama host. Chains ``StudioModel/onDocumentChange`` rather than
    /// replacing it, so earlier listeners keep running first.
    public func attach(
        model: StudioModel,
        window: NSWindow,
        url: URL? = nil,
        redraw: @escaping @MainActor () -> Void = {}
    ) {
        let documents = StudioDocumentSession(model: model, url: url)
        self.documents = documents
        self.window = window
        self.redraw = redraw
        window.delegate = self
        documents.onStateChange = { [weak self] in
            self?.updateWindow()
            // Deferred to the next main-actor turn: a document change made by
            // a gama button runs inside the host's own event dispatch, and
            // invalidating the host from there re-enters its frame pump
            // (Swift traps on the overlapping access). The action already
            // repaints; this pass is for changes from outside gama (File >
            // Open), which reach here outside any dispatch.
            self?.scheduleRedraw()
        }
        // A File-menu note (ADR 0017) is added outside any gama action too.
        model.onConsoleChange = { [weak self] in self?.scheduleRedraw() }
        updateWindow()
    }

    /// Whether a deferred repaint is already queued for this turn.
    private var redrawScheduled = false

    /// Repaints on the next main-actor turn, once however many changes (an
    /// open and its console note) asked for it this turn.
    private func scheduleRedraw() {
        guard !redrawScheduled else { return }
        redrawScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.redrawScheduled = false
            self.redraw()
        }
    }

    /// A File menu whose items target this delegate.
    public func makeFileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Open…", #selector(openDocument(_:)), "o", [.command]),
            ("Save", #selector(saveDocument(_:)), "s", [.command]),
            ("Save As…", #selector(saveDocumentAs(_:)), "s", [.command, .shift]),
        ]
        for (title, action, key, modifiers) in items {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
        }
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// Reads `url` and replaces the model's document with it. The previous
    /// document is gone and the load is not undoable.
    /// Logs the outcome as a console note (ADR 0017).
    public func open(_ url: URL) throws {
        guard let documents else { throw StudioDocumentError.notAttached }
        do {
            try documents.open(url)
            documents.model.log(note: "opened \(url.lastPathComponent)")
        } catch {
            documents.model.log(note: "couldn\u{2019}t open \(url.lastPathComponent): \(StudioDocumentIO.describe(error))", isError: true)
            throw error
        }
    }

    /// Writes the model's document to `url`, which becomes the current file.
    /// Logs the outcome as a console note (ADR 0017).
    public func save(to url: URL) throws {
        guard let documents else { throw StudioDocumentError.notAttached }
        do {
            try documents.save(to: url)
            documents.model.log(note: "saved \(url.lastPathComponent)")
        } catch {
            documents.model.log(note: "couldn\u{2019}t save \(url.lastPathComponent): \(StudioDocumentIO.describe(error))", isError: true)
            throw error
        }
    }

    /// Title, proxy icon, and edited dot from the current document.
    func updateWindow() {
        guard let window else { return }
        window.representedURL = currentURL
        window.title = currentURL?.lastPathComponent ?? "Gama Studio"
        window.isDocumentEdited = model?.hasUnsavedChanges ?? false
    }

    @objc public func openDocument(_ sender: Any?) {
        guard confirmDiscardingChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.contentTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try open(url)
        } catch {
            report(error, doing: "open “\(url.lastPathComponent)”")
        }
    }

    @objc public func saveDocument(_ sender: Any?) {
        _ = saveCurrent()
    }

    @objc public func saveDocumentAs(_ sender: Any?) {
        _ = saveWithPanel()
    }

    /// Asks before quitting over unsaved changes, unless closing the window
    /// already asked.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if closeConfirmed { return .terminateNow }
        return confirmDiscardingChanges() ? .terminateNow : .terminateCancel
    }

    /// Asks before closing the window over unsaved changes. Closing the last
    /// window quits, so a Cancel here keeps both the window and the document.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        let proceed = confirmDiscardingChanges()
        closeConfirmed = proceed
        return proceed
    }

    // MARK: Prompts

    private static var contentTypes: [UTType] {
        [UTType(filenameExtension: StudioDocumentIO.fileExtension) ?? .data]
    }

    /// Saves to the current file, or asks where when there is none. Returns
    /// whether the document was written.
    private func saveCurrent() -> Bool {
        guard let currentURL else { return saveWithPanel() }
        do {
            try save(to: currentURL)
            return true
        } catch {
            report(error, doing: "save “\(currentURL.lastPathComponent)”")
            return false
        }
    }

    private func saveWithPanel() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.contentTypes
        panel.nameFieldStringValue = currentURL?.lastPathComponent ?? "Untitled.\(StudioDocumentIO.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try save(to: url)
            return true
        } catch {
            report(error, doing: "save “\(url.lastPathComponent)”")
            return false
        }
    }

    /// `true` when there is nothing unsaved, or the user saved or chose to
    /// discard it; `false` when they cancelled or the save failed.
    private func confirmDiscardingChanges() -> Bool {
        guard let model, model.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(currentURL?.lastPathComponent ?? "Untitled")”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCurrent()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func report(_ error: any Error, doing action: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t \(action)."
        alert.informativeText = StudioDocumentIO.describe(error)
        alert.runModal()
    }

    /// Creates the studio's main window with the style mask `gama-studio`
    /// uses and `isReleasedWhenClosed = false`.
    ///
    /// A top-level `let window` in `main.swift` holds this strongly for the
    /// whole process, so AppKit's default `isReleasedWhenClosed = true`
    /// would release it a second time when the window closes — this factory
    /// is the one place that decision is made, so it can't drift from the
    /// executable that relies on it.
    public static func makeMainWindow(contentRect: NSRect, title: String = "Gama Studio") -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }
}
/// A File-menu operation was attempted before ``StudioAppDelegate/attach(model:window:url:redraw:)``.
public enum StudioDocumentError: Error, Hashable, Sendable {
    case notAttached
}
#endif
