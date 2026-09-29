//  GamaNativeHostView.swift — GamaAppleUI
//  Native presentation host (ADR 0017): presents a Gama surface with real
//  AppKit controls instead of a painted cell grid. Layout stays Gama's, in
//  points measured by `AppKitLayoutMetrics`; this view only turns each
//  frame's presentation diff into subview changes and routes platform
//  events back to `FrameHost`. Separate from `GamaHostView`, which keeps the
//  cell path unchanged.
//
//  macOS:  window.contentView = try GamaNativeHostView(app: MyApp())

#if canImport(AppKit)

    public import AppKit
    public import GamaCore

    /// An AppKit view presenting one Gama surface with native controls.
    ///
    /// Text is an `NSTextField` label, buttons and toggles are `NSButton`s,
    /// text fields are editable `NSTextField`s, progress is an
    /// `NSProgressIndicator`, dividers are `NSBox` separators, and
    /// backgrounds and borders are plain layer-backed views, all at frames
    /// `LayoutEngine` computed in points with ``AppKitLayoutMetrics``.
    /// Buttons and checkboxes call `FrameHost.activate(_:)`, text edits write
    /// the field's binding, and first-responder changes report back through
    /// `FrameHost.focus(_:)`; `FrameHost` stays the source of focus order,
    /// which the host mirrors into `nextKeyView`. Native regions (ADR 0016)
    /// work as they do in ``GamaHostView``, with frames in points.
    ///
    /// Unlike ``GamaHostView`` it paints no cells and publishes no
    /// `DrawList`: accessibility comes from the native controls themselves.
    @MainActor
    public final class GamaNativeHostView: NSView, NSTextFieldDelegate {
        /// The measurements this host lays out with.
        public let layoutMetrics: AppKitLayoutMetrics

        private var session: NativeHostSession?
        /// Shell hook run after one native event has been handled and any
        /// required frame has been presented. Package-only, like
        /// ``GamaHostView``'s.
        package var afterEventDispatch: (@MainActor () -> Void)?
        /// Set while this host changes first responder itself, so the
        /// resulting focus notification is not echoed back to `FrameHost`.
        private var isApplyingFocus = false
        /// The Gama focus most recently mirrored into first responder.
        private var syncedFocus: NodeID?
        private var isPumping = false

        // MARK: Native regions (ADR 0016)
        /// Application-owned views attached to native regions, by identity.
        private var attachedNativeViews: [NativeRegionID: NSView] = [:]
        private var lastNativeRegions: [NativeRegionFrame] = []
        private var focusedNativeRegions: Set<NativeRegionID> = []

        // MARK: Init

        /// Creates a zero-frame host with `app` installed.
        public convenience init<A: App>(app: sending A) throws(SceneConfigurationError) {
            self.init(frame: .zero)
            try install(app: app)
        }

        /// Creates an empty host; call ``install(app:)`` to attach an app.
        public override init(frame: NSRect) {
            layoutMetrics = AppKitLayoutMetrics()
            super.init(frame: frame)
        }

        /// Restores an empty host from an archive; call ``install(app:)``
        /// to attach an app.
        public required init?(coder: NSCoder) {
            layoutMetrics = AppKitLayoutMetrics()
            super.init(coder: coder)
        }

        /// Attaches `app`'s primary scene, replacing any installed surface,
        /// and presents its first frame.
        public func install<A: App>(app: sending A) throws(SceneConfigurationError) {
            let graph = try compileSceneGraph(app)
            let surface = try graph.makePrimarySurface()
            install(surface: surface)
        }

        /// Installs one already-validated scene surface for a package-owned
        /// shell.
        package func install(surface: SceneSurface) {
            tearDown()
            session = NativeHostSession(
                surface: surface, metrics: layoutMetrics.metrics, size: pumpSize())
            syncedFocus = nil
            drive()
        }

        /// Routes an event into the installed surface and presents any frame
        /// it requires.
        package func send(_ event: InputEvent) {
            guard let session else { return }
            session.pump.handle(event)
            if session.pump.needsFrame { drive() }
            afterEventDispatch?()
        }

        /// Cancels the installed surface's subscriptions and removes its
        /// views.
        package func tearDown() {
            guard let session else { return }
            session.pump.cancelSubscriptions()
            session.removeAllViews()
            self.session = nil
        }

        /// Requests a frame after application state changes outside a Gama
        /// event.
        public func invalidate() {
            session?.pump.invalidate()
            drive()
        }

        // MARK: Test and shell access

        /// The presentation tree currently shown. Package-only, for tests.
        package var presentedTree: [PresentedNode] { session?.tree ?? [] }

        /// The view presenting `id`. Package-only, for tests.
        package func presentedView(for id: PresentationID) -> NSView? { session?.view(for: id) }

        /// The Gama node that holds focus. Package-only, for tests.
        package var focusedID: NodeID? { session?.pump.focusedID }

        /// The most recently published native regions, in points.
        /// Package-only, for tests.
        package var nativeRegions: [NativeRegionFrame] { lastNativeRegions }

        // MARK: Frame pump

        private func pumpSize() -> Size {
            Size(width: max(1, Int(bounds.width)), height: max(1, Int(bounds.height)))
        }

        private func drive() {
            guard let session, !isPumping else { return }
            isPumping = true
            defer { isPumping = false }
            // Applying a frame can dirty the host again (focus
            // reconciliation, or a control reporting focus while its view is
            // placed), so keep presenting until it is clean. The bound only
            // guards against an application that dirties itself every frame.
            for _ in 0..<8 {
                let size = pumpSize()
                if size != session.pump.size { session.pump.handle(.resize(size)) }
                guard session.advance(into: self, metrics: layoutMetrics).produced else { break }
                placeNativeRegions(session.pump.nativeRegions)
                syncFirstResponder()
                if !session.pump.needsFrame { break }
            }
        }

        // MARK: Events from native controls

        /// Target of every presented button and checkbox.
        @objc func nativeControlFired(_ sender: Any?) {
            guard let presented = sender as? any NativePresentedView, let id = presented.nodeID else { return }
            controlDidActivate(id)
        }

        /// A control fired: run the node's action and present the result.
        func controlDidActivate(_ id: NodeID) {
            guard let session else { return }
            session.pump.activate(id)
            // Activation moved Gama focus to the control AppKit already
            // focused; record it so the frame does not re-assign it.
            syncedFocus = session.pump.focusedID
            if session.pump.needsFrame { drive() }
            afterEventDispatch?()
        }

        /// A presented control became first responder.
        func controlDidTakeFocus(_ id: NodeID) {
            guard !isApplyingFocus, let session else { return }
            session.pump.focus(id)
            syncedFocus = session.pump.focusedID
            if session.pump.needsFrame { drive() }
        }

        /// Writes a text field's edit through its binding.
        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NativeTextField, let id = field.nodeID,
                let session, case .textField(_, _, _, let setText)? = session.controls[id]
            else { return }
            setText(field.stringValue)
            session.pump.invalidate()
            drive()
            afterEventDispatch?()
        }

        /// Makes the view presenting Gama's focused node first responder
        /// when Gama moved focus.
        private func syncFirstResponder() {
            guard let session else { return }
            let focused = session.pump.focusedID
            guard focused != syncedFocus else { return }
            guard let window = unsafe window else { return }
            syncedFocus = focused
            guard let focused, let view = session.view(for: .node(focused)) else { return }
            // A focused native region hands first responder to its attached
            // view in `placeNativeRegions`.
            if view is NativeRegionContainer { return }
            isApplyingFocus = true
            defer { isApplyingFocus = false }
            _ = window.makeFirstResponder(view)
        }

        // MARK: Native regions (ADR 0016)

        /// Attaches an application-owned view to the native region `id`, with
        /// the same contract as ``GamaHostView/attach(_:to:)``: the host adds
        /// it as a subview on the region's point frame, hides the region's
        /// fallback while it shows, hides it while the region is absent, and
        /// hands it first responder when Gama focus lands on the region.
        public func attach(_ view: NSView, to id: NativeRegionID) {
            if let previous = attachedNativeViews[id], previous !== view {
                previous.removeFromSuperview()
            }
            for (other, attached) in attachedNativeViews where other != id && attached === view {
                attachedNativeViews[other] = nil
                focusedNativeRegions.remove(other)
            }
            attachedNativeViews[id] = view
            if unsafe view.superview !== self { addSubview(view) }
            view.isHidden = true
            placeNativeRegions(lastNativeRegions)
        }

        /// Removes the view attached to `id` and shows the region's fallback
        /// again. First responder returns to the host only if it was inside
        /// the detached view while Gama focus was on the region.
        public func detach(_ id: NativeRegionID) {
            guard let view = attachedNativeViews.removeValue(forKey: id) else { return }
            let wasFocused = focusedNativeRegions.remove(id) != nil
            let shouldReclaim = wasFocused && firstResponderIsInside(view)
            view.removeFromSuperview()
            if shouldReclaim { _ = unsafe window?.makeFirstResponder(self) }
            placeNativeRegions(lastNativeRegions)
        }

        /// Whether `view` is an application view attached to a region.
        func isAttachedNativeView(_ view: NSView) -> Bool {
            attachedNativeViews.values.contains { $0 === view }
        }

        private func placeNativeRegions(_ regions: [NativeRegionFrame]) {
            lastNativeRegions = regions
            var byID: [NativeRegionID: NativeRegionFrame] = [:]
            for region in regions { byID[region.id] = region }
            var focused: Set<NativeRegionID> = []
            var newlyFocusedView: NSView?
            var showing: Set<NodeID> = []
            for (id, view) in attachedNativeViews {
                guard let region = byID[id], region.frame.size.width > 0, region.frame.size.height > 0 else {
                    view.isHidden = true
                    continue
                }
                view.frame = NativeHostSession.rect(region.frame)
                view.isHidden = false
                showing.insert(region.node)
                if region.isFocused {
                    focused.insert(id)
                    if !focusedNativeRegions.contains(id) { newlyFocusedView = view }
                }
            }
            // The fallback of a region showing an attached view is hidden.
            for region in regions {
                session?.view(for: .node(region.node))?.isHidden = showing.contains(region.node)
            }
            let lost = focusedNativeRegions.subtracting(focused)
            focusedNativeRegions = focused
            if let newlyFocusedView {
                isApplyingFocus = true
                _ = unsafe window?.makeFirstResponder(newlyFocusedView)
                isApplyingFocus = false
            } else if !lost.isEmpty,
                lost.contains(where: { attachedNativeViews[$0].map(firstResponderIsInside) ?? false })
            {
                isApplyingFocus = true
                _ = unsafe window?.makeFirstResponder(self)
                isApplyingFocus = false
            }
        }

        private func firstResponderIsInside(_ view: NSView) -> Bool {
            guard let responder = unsafe window?.firstResponder as? NSView else { return false }
            return responder.isDescendant(of: view)
        }

        // MARK: AppKit

        /// Uses a top-left origin so frames computed by `LayoutEngine` apply
        /// unchanged.
        public override var isFlipped: Bool { true }

        /// Accepts first responder so keys reach Gama when no control has
        /// focus.
        public override var acceptsFirstResponder: Bool { true }

        /// Re-lays out the surface at the new size in points.
        public override func layout() {
            super.layout()
            guard let session, pumpSize() != session.pump.size else { return }
            drive()
        }

        /// Mirrors Gama's focus into first responder once the host has a
        /// window, and retries a native region's deferred focus handoff.
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncedFocus = nil
            focusedNativeRegions.removeAll()
            placeNativeRegions(lastNativeRegions)
            syncFirstResponder()
        }

        /// Routes keys that reach the host itself (no control has focus) to
        /// `FrameHost`.
        public override func keyDown(with event: NSEvent) {
            guard let key = NativeKeyTranslation.key(from: event) else { return }
            send(.key(key))
        }

        /// Reports the host as a plain container; the controls inside it are
        /// the accessibility elements.
        public override func accessibilityRole() -> NSAccessibility.Role? { .group }
    }

#endif  // canImport(AppKit)
