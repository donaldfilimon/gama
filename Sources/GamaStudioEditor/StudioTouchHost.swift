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
        do {
            try hostView.install(app: StudioApp(model: model, viewport: actions))
        } catch {
            assertionFailure("gama-studio: install failed: \(error)")
        }
        addChild(viewport.hostingController)
        hostView.attach(viewport.view, to: StudioApp.viewportRegion)
        viewport.hostingController.didMove(toParent: self)
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
        return failures
    }
}

/// Gama Studio as a SwiftUI view, for an app's `WindowGroup`.
public struct GamaStudioView: UIViewControllerRepresentable {
    /// Called once after the first layout with ``StudioHostViewController/smokeFailures()``
    /// when the app runs its launch smoke check.
    let onFirstLayout: (@MainActor ([String]) -> Void)?

    public init(onFirstLayout: (@MainActor ([String]) -> Void)? = nil) {
        self.onFirstLayout = onFirstLayout
    }

    public func makeUIViewController(context: Context) -> StudioHostViewController {
        let controller = StudioHostViewController()
        if let onFirstLayout {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { onFirstLayout(controller.smokeFailures()) }
            }
        }
        return controller
    }

    public func updateUIViewController(_ controller: StudioHostViewController, context: Context) {}
}

#endif
