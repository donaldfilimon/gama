//  StudioTouchHost.swift — GamaStudioEditor
//
//  Hosts Gama Studio on iOS and visionOS (ADR 0008): gama's UIKit
//  GamaHostView draws the panels, and the touch viewport fills its native
//  viewport region. The app target (Apps/GamaStudioApp) only wraps
//  ``GamaStudioView`` in a SwiftUI WindowGroup, so everything testable lives
//  here.

#if canImport(UIKit) && canImport(RealityKit) && canImport(SwiftUI)

public import UIKit
public import SwiftUI
public import GamaAuthoring
public import GamaAppleUI
public import GamaCore
import GamaDraw
import GamaReality

/// A view controller whose view is the gama host, with the RealityKit
/// viewport attached to ``StudioApp/viewportRegion``.
@MainActor
public final class StudioHostViewController: UIViewController {
    public let model: StudioModel
    public let hostView = GamaHostView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
    public private(set) var viewport: TouchViewportController!
    /// File open and save through the document picker (ADR 0009).
    public private(set) var files: TouchDocumentController!
    /// A file handed over before the view was on screen, opened once it is
    /// (the prompt and pickers need a window to present from).
    private var pendingExternalURL: URL?

    public init(model: StudioModel = StudioModel(document: StudioModel.sampleScene())) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("StudioHostViewController is created in code")
    }

    public override func loadView() {
        view = hostView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let host = hostView
        let viewport = TouchViewportController(model: model, onSelectionChange: { host.invalidate() })
        self.viewport = viewport
        // A change that did not come through a gama action (a viewport tap,
        // a document replaced) must still repaint the panels.
        let previousDocumentListener = model.onDocumentChange
        model.onDocumentChange = {
            previousDocumentListener?()
            // Deferred: a change made by a gama button runs inside the host's
            // event dispatch, and invalidating from there re-enters its frame
            // pump (see StudioAppDelegate.attach).
            Task { @MainActor in host.invalidate() }
        }
        let actions = ViewportActions(
            frameSelection: { viewport.frameSelection() },
            lookThrough: { viewport.lookThrough($0) }
        )
        let documents = StudioDocumentSession(model: model)
        let files = TouchDocumentController(documents: documents, presenter: self)
        self.files = files
        files.onStateChange = { [weak self] in self?.updateTitle() }
        do {
            try hostView.install(app: StudioApp(model: model, viewport: actions, documents: files.actions))
        } catch {
            assertionFailure("gama-studio: install failed: \(error)")
        }
        addChild(viewport.hostingController)
        hostView.attach(viewport.view, to: StudioApp.viewportRegion)
        viewport.hostingController.didMove(toParent: self)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTitle()
        if let url = pendingExternalURL {
            pendingExternalURL = nil
            files.openExternally(url)
        }
    }

    /// Opens a `.usda` file the system handed to the app (ADR 0010): from
    /// Files, the share sheet, or another app. Waits for the view to be on
    /// screen when it arrives at launch.
    public func openExternalDocument(_ url: URL) {
        guard let files, viewIfLoaded?.window != nil else {
            pendingExternalURL = url
            return
        }
        files.openExternally(url)
    }

    /// The window scene's title: the file name, with a bullet while edited.
    private func updateTitle() {
        guard let documents = files?.documents else { return }
        let name = documents.displayName
        view.window?.windowScene?.title = documents.hasUnsavedChanges ? "\(name) \u{2022}" : name
    }

    // MARK: Keyboard

    /// ⌘O, ⌘S, and ⇧⌘S on a hardware keyboard, as on macOS. Found through
    /// the responder chain from the gama host, which is first responder.
    public override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "Open…", action: #selector(openDocument), input: "o", modifierFlags: .command),
            UIKeyCommand(title: "Save", action: #selector(saveDocument), input: "s", modifierFlags: .command),
            UIKeyCommand(title: "Save As…", action: #selector(saveDocumentAs), input: "s", modifierFlags: [.command, .shift]),
        ]
    }

    @objc func openDocument() { files.open() }
    @objc func saveDocument() { files.save() }
    @objc func saveDocumentAs() { files.saveAs() }

    /// What the gate's launch smoke check verifies after `--open <path>`
    /// (ADR 0010, ADR 0011), in order:
    /// 1. the file opened as a coordinated `UIDocument` in the `.normal`
    ///    state, and the model holds its content (``openedFileFailures(expected:)``);
    /// 2. an edit autosaves to the file and the document reads as saved;
    /// 3. another writer's coordinated write reloads the file when nothing
    ///    is unsaved;
    /// 4. the same write with unsaved changes asks instead, and Keep Mine
    ///    leaves the document to overwrite the file.
    /// The file is the gate's scratch copy. Empty means healthy.
    public func fileSmokeFailures(expected url: URL) async -> [String] {
        guard await waitUntil({ self.files?.coordinated?.documentState == .normal }) else {
            return ["\(url.lastPathComponent) did not open as a coordinated document"]
                + openedFileFailures(expected: url)
        }
        var failures = openedFileFailures(expected: url)
        guard let files, let document = files.coordinated else { return failures + ["no coordinated document"] }
        let original = model.session.document

        model.addPrimitive(.box)
        let edited = model.session.document
        if !document.hasUnsavedChanges { failures.append("an edit did not mark the document for autosave") }
        let autosaved = await withCheckedContinuation { continuation in
            document.autosave { continuation.resume(returning: $0) }
        }
        if !autosaved { failures.append("autosave failed") }
        if !(await waitUntil({ !files.documents.hasUnsavedChanges })) {
            failures.append("the document still reads as unsaved after autosave")
        }
        if (try? StudioDocumentIO.read(from: url)) != edited { failures.append("autosave did not write the edit") }

        if let error = await Self.writeAsAnotherApp(original, to: url) { return failures + ["external write failed: \(error)"] }
        if !(await waitUntil({ self.model.session.document.hasSameContent(as: original) })) {
            failures.append("another writer's change was not reloaded")
        }

        model.addPrimitive(.sphere)
        if let error = await Self.writeAsAnotherApp(edited, to: url) { return failures + ["external write failed: \(error)"] }
        if await waitUntil({ files.isAskingAboutExternalChange }) {
            presentedViewController?.dismiss(animated: false)
            files.resolveExternalChange(.keepMine)
            if !document.hasUnsavedChanges { failures.append("Keep Mine did not mark the document to overwrite the file") }
        } else {
            failures.append("a change under unsaved edits did not ask")
        }
        return failures
    }

    /// Polls `condition` on the main actor for up to `seconds`.
    private func waitUntil(_ condition: @MainActor () -> Bool, seconds: Double = 10) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Writes `document` to `url` the way another app would: a coordinated
    /// write with no presenter of its own, so the open document is told. Off
    /// the main actor, because the document relinquishes the file through
    /// the main queue and a coordinated write on main would wait for itself.
    private static func writeAsAnotherApp(_ document: SceneDocument, to url: URL) async -> String? {
        await Task.detached { coordinatedWrite(document, to: url) }.value
    }

    nonisolated private static func coordinatedWrite(_ document: SceneDocument, to url: URL) -> String? {
        var coordinationError: NSError?
        var writeError: (any Error)?
        // unsafe: the NSError out-parameter is an AutoreleasingUnsafeMutablePointer.
        unsafe NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try StudioDocumentIO.write(document, to: target) } catch { writeError = error }
        }
        if let coordinationError { return coordinationError.localizedDescription }
        return writeError.map(StudioDocumentIO.describe)
    }

    /// What the gate's launch smoke check verifies after `--open <path>`: the
    /// file became the current file, and the document is its unedited
    /// content. Empty means healthy.
    public func openedFileFailures(expected url: URL) -> [String] {
        guard let documents = files?.documents else { return ["document controller not created"] }
        guard let current = documents.currentURL else { return ["\(url.lastPathComponent) was not opened"] }
        var failures: [String] = []
        if current.standardizedFileURL.path != url.standardizedFileURL.path {
            failures.append("opened \(current.path), expected \(url.path)")
        }
        if documents.hasUnsavedChanges { failures.append("the opened document has unsaved changes") }
        do {
            if try StudioDocumentIO.read(from: url) != model.session.document {
                failures.append("the document differs from \(url.lastPathComponent)")
            }
        } catch {
            failures.append("rereading \(url.lastPathComponent) failed: \(StudioDocumentIO.describe(error))")
        }
        return failures
    }

    /// What the gate's launch smoke check verifies after the first layout:
    /// the host drew, the viewport is attached, visible, and non-empty, and
    /// the projection matches the document. Empty means healthy.
    public func smokeFailures() -> [String] {
        hostView.invalidate()
        var failures: [String] = []
        if hostView.currentDrawList.commands.isEmpty { failures.append("0 draw commands") }
        guard let viewport else { return failures + ["viewport not created"] }
        if viewport.view.superview !== hostView { failures.append("viewport is not a subview of the host") }
        if viewport.view.isHidden { failures.append("viewport is hidden") }
        let frame = viewport.view.frame
        if !(frame.width > 0 && frame.height > 0) { failures.append("viewport frame is empty: \(frame)") }
        if model.bridge.count != model.session.document.count {
            failures.append("bridge holds \(model.bridge.count) entities, document \(model.session.document.count)")
        }
        // The app's own sandbox can write a .usda copy and read it back.
        if let files {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GamaStudioSmoke-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                let (file, document) = try files.documents.writeCopyForExport(in: directory)
                if try StudioDocumentIO.read(from: file) != document { failures.append("file round trip changed the document") }
            } catch {
                failures.append("file round trip failed: \(StudioDocumentIO.describe(error))")
            }
        } else {
            failures.append("document controller not created")
        }
        return failures
    }
}

/// Gama Studio as a SwiftUI view, for an app's `WindowGroup`.
public struct GamaStudioView: UIViewControllerRepresentable {
    /// Called once after the first layout with ``StudioHostViewController/smokeFailures()``
    /// when the app runs its launch smoke check.
    let onFirstLayout: (@MainActor ([String]) -> Void)?
    /// The latest file the system handed to the app, if any (ADR 0010).
    let incoming: IncomingDocument?

    public init(incoming: IncomingDocument? = nil, onFirstLayout: (@MainActor ([String]) -> Void)? = nil) {
        self.incoming = incoming
        self.onFirstLayout = onFirstLayout
    }

    public final class Coordinator {
        /// The last request passed on, so each one opens exactly once.
        var handled: IncomingDocument.ID?
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIViewController(context: Context) -> StudioHostViewController {
        let controller = StudioHostViewController()
        if let onFirstLayout {
            let expected = incoming?.url
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    let failures = controller.smokeFailures()
                    guard let expected else { return onFirstLayout(failures) }
                    Task { @MainActor in
                        onFirstLayout(failures + (await controller.fileSmokeFailures(expected: expected)))
                    }
                }
            }
        }
        return controller
    }

    public func updateUIViewController(_ controller: StudioHostViewController, context: Context) {
        guard let incoming, context.coordinator.handled != incoming.id else { return }
        context.coordinator.handled = incoming.id
        controller.openExternalDocument(incoming.url)
    }
}

/// One request to open a file handed over by the system. Each request has
/// its own identity, so handing over the same file twice opens it twice.
public struct IncomingDocument: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

#endif
