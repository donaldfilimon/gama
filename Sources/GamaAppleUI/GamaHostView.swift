//  GamaHostView.swift — GamaAppleUI
//  Native Apple GUI backend: an NSView/UIView that hosts a Gama app,
//  drawing the shared DrawList through CoreGraphics with a monospaced
//  system font. Keyboard, mouse, trackpad and pen on macOS; touch, pencil,
//  pointer hover and scroll on iOS/visionOS; taps on tvOS. Pointer input is
//  translated into raw `PointerEvent` samples; FrameHost recognizes the
//  gestures (ADR 0018).
//  Entire target is @MainActor — UIKit/AppKit isolation is enforced by
//  the compiler, not convention.
//
//  macOS:  window.contentView = try GamaHostView(app: MyApp())
//  iOS:    view.addSubview(try GamaHostView(app: MyApp()))

#if canImport(AppKit) || canImport(UIKit)

#if canImport(AppKit)
    public import AppKit
    /// The platform view class `GamaHostView` extends — `NSView` on macOS.
    public typealias GamaPlatformView = NSView
    /// The platform font class the host paints with — `NSFont` on macOS.
    /// Package-visible so the styled-font cache test can name the type.
    package typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
#else
    public import UIKit
    /// The platform view class `GamaHostView` extends — `UIView` on
    /// iOS/tvOS/visionOS.
    public typealias GamaPlatformView = UIView
    /// The platform font class the host paints with — `UIFont` on
    /// iOS/tvOS/visionOS. Package-visible so the styled-font cache test
    /// can name the type.
    package typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
#endif

public import GamaCore
public import GamaDraw

/// A native AppKit/UIKit view hosting one Gama surface: it pumps the surface's
/// `FrameHost`, paints the shared `DrawList` through CoreGraphics as a
/// monospaced character grid, and translates platform keyboard, mouse, and
/// touch input into `InputEvent`s. Like every backend it only carries
/// events in and frames out — interaction semantics stay in GamaCore.
/// `@MainActor` end to end, so AppKit/UIKit isolation is enforced by the
/// compiler rather than convention.
@MainActor
public final class GamaHostView: GamaPlatformView {
    // Closure types carry explicit @MainActor so the isolation contract
    // survives any refactor that moves them off this class.
    private var driver: (@MainActor () -> Void)?  // erased frame pump
    private var invalidateHost: (@MainActor () -> Void)?
    private var handleEvent: (@MainActor (InputEvent) -> Void)?
    /// Shell hook run after one native event has been handled and any required
    /// frame has been pumped. Package-only so embedded host views keep their
    /// standalone ownership model.
    package var afterEventDispatch: (@MainActor () -> Void)?
    /// Cancels the current session's model subscriptions; called before a
    /// second `install` replaces the session wholesale.
    private var tearDownSession: (@MainActor () -> Void)?
    /// Most recently rendered shared draw list, exposed read-only for host
    /// accessibility adapters, diagnostics, and runtime smoke validation.
    public private(set) var currentDrawList = DrawList(size: Size(width: 0, height: 0)) {
        didSet {
            accessibilityCacheIsStale = true
            refreshAccessibilityIfObserved()
        }
    }

    // MARK: Accessibility cache
    //
    // The VoiceOver adapter derives everything from `currentDrawList`
    // (GamaHostAccessibility.swift). Deriving it eagerly every frame would
    // charge every host for something only an assistive-technology client
    // reads, so the snapshot is computed lazily, cached until the next
    // frame, and the change notification is armed only after a client has
    // actually queried the view.
    /// This host derives a `DrawList` from the borrowed painted grid and
    /// never swaps the buffer's planes, exactly as `GamaEmbed` does, so it
    /// holds a `CellSerializer`. It was excluded from the earlier
    /// `CellPresenter` spike for reasons — an `inout` access and a swap
    /// contract — that a `borrowing`, non-mutating protocol does not have.
    let drawListSerializer = DrawListSerializer()

    var accessibilityCacheIsStale = true
    var cachedAccessibilitySnapshot: AccessibilitySnapshot?
    var cachedAccessibilityElements: [GamaAccessibilityLineElement]?
    var lastAnnouncedAccessibilitySnapshot: AccessibilitySnapshot?
    var accessibilityHasBeenQueried = false

    /// Whether an assistive-technology client has queried this host yet, and
    /// so whether the frame path is doing any accessibility work at all.
    /// Package-only: it exists so a test can prove the "no cost until
    /// queried" contract, which is otherwise invisible from outside.
    package var accessibilityIsObserved: Bool { accessibilityHasBeenQueried }

    /// The snapshot most recently announced to an assistive-technology
    /// client, or `nil` if none has been. Package-only, for the same reason
    /// as ``accessibilityIsObserved``.
    package var accessibilityAnnouncedSnapshot: AccessibilitySnapshot? {
        lastAnnouncedAccessibilitySnapshot
    }

    // Font construction is not reliably inert under CoreText pressure: the
    // same failure described below for per-command styled fonts was observed
    // while several hosts each measured a freshly constructed base font.
    // Platform fonts are immutable, so construct the measurement font once
    // and share that value; mutable render and accessibility caches remain
    // confined to each host.
    private static let baseFont =
        PlatformFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var font: PlatformFont { Self.baseFont }

    /// Identity of the immutable measurement font. Package-only so the
    /// regression test can pin one construction across multiple hosts.
    package var baseFontIdentifier: ObjectIdentifier { ObjectIdentifier(font) }

    // MARK: Styled-font cache
    //
    // `styledFont(for:)` used to build a fresh `monospacedSystemFont` for
    // every text command of every frame. Driven hard that intermittently
    // yields a font CoreText cannot resolve: `TAttributes::ApplyFont`
    // inserts nil into the attribute dictionary and the process aborts
    // inside `CTLineCreateWithAttributedString`, with `draw(_:)` on the
    // stack. Measured on branch `perf/apple-host-baseline`, whose
    // `gama-apple-demo --scenario` harness is NOT on this branch: 15
    // attempts at 500-2500 frames, exactly one completed, and a diagnostic
    // build whose only change was a four-entry cache ran 5x2000 frames
    // clean. Those runs were made there, not here -- reproducing them
    // requires that harness, and this branch's gates prove correctness and
    // compilation only, not the crash rate.
    //
    // Only two of the six `TextAttributes` bits reach font selection —
    // `.bold` picks the weight and `.italic` adds a symbolic trait — and
    // the point size is fixed, so masking the style down to those two bits
    // bounds the cache at four entries for the life of the view. The miss
    // path is the original construction verbatim, so a cached font is the
    // same font the uncached code would have built.
    //
    // The class is `@MainActor`, so this is plain unsynchronized state:
    // every reader reaches it from `draw(_:)`, which the compiler already
    // isolates to the main actor.

    /// The attribute bits that actually select a different font.
    private static let fontDefiningAttributes: TextAttributes = [.bold, .italic]
    /// Fonts built so far, keyed by ``fontDefiningAttributes``; at most four.
    private var fontCache: [TextAttributes: PlatformFont] = [:]
    /// How many fonts this view has constructed. Uncached, this grew with
    /// every text command drawn; cached, it stops at four. Package-only so
    /// a test can pin the contract, for the same reason as
    /// ``accessibilityIsObserved``.
    package private(set) var styledFontConstructionCount = 0
    /// How many distinct fonts the cache currently retains — the bound the
    /// same test asserts. Package-only.
    package var styledFontCacheCount: Int { fontCache.count }

    /// Measured monospaced cell size. `package` (not `public`) so tests can
    /// read it without duplicating its measurement math.
    package private(set) var cellSize: CGSize = .zero
    /// Measured monospaced cell size, for the accessibility adapter's
    /// grid-to-view rectangle conversion.
    var accessibilityCellSize: CGSize { cellSize }
    private let defaultForeground: PlatformColor = .white
    private let defaultBackground: PlatformColor = .black

    // MARK: Native regions (ADR 0016)
    /// Application-owned views attached to native regions, by identity.
    var attachedNativeViews: [NativeRegionID: GamaPlatformView] = [:]
    /// Regions of the most recent frame, kept so attach/detach can place a
    /// view without waiting for the next frame.
    private var lastNativeRegions: [NativeRegionFrame] = []
    /// The most recently published native regions. Package-only so tests can
    /// derive an expected view frame without duplicating the placement math.
    package var nativeRegions: [NativeRegionFrame] { lastNativeRegions }
    /// Cell frames of regions currently showing an attached view; drawing
    /// skips commands wholly inside them.
    private var shownNativeRegionCells: [Rect] = []
    /// Regions whose attached view was given first responder last frame.
    private var focusedNativeRegions: Set<NativeRegionID> = []

    // MARK: Pointer (ADR 0018)
    /// Reads the installed host's pending long-press deadline.
    private var pointerDeadline: (@MainActor () -> UInt64?)?
    /// The one-shot timer delivering the stationary sample at the deadline.
    private var pointerDeadlineTimer: Timer?
    /// The deadline the timer is armed for. Package-only so a test can check
    /// the timer follows the host without spinning the run loop.
    package private(set) var armedPointerDeadlineMillis: UInt64?
    /// The pressed pointer and where it was last seen, so the deadline sample
    /// is for that same pointer at that same cell.
    private var pressedPointer: (location: Point, kind: PointerEvent.Kind, pointerID: Int, button: Int)?
    /// Sub-cell scroll travel carried to the next scroll event.
    private var scrollRemainder = CGSize.zero
    #if canImport(UIKit)
        /// The one touch being translated, tracked by identity.
        private var trackedTouch: UITouch?
        /// Pointer identity handed to FrameHost; a new one per tracked touch.
        private var nextTouchID = 0
    #endif

    // MARK: Init

    /// Creates a zero-frame view with `app` installed — one-step shorthand
    /// for `init(frame:)` followed by `install(app:)`. Ownership of `app` is
    /// transferred into the MainActor-hosted session.
    public convenience init<A: App>(app: sending A) throws(SceneConfigurationError) {
        self.init(frame: .zero)
        try install(app: app)
    }

    #if canImport(AppKit)
        /// Creates an empty host view measuring its monospaced cell size;
        /// call `install(app:)` to attach an app.
        public override init(frame: NSRect) {
            super.init(frame: frame)
            commonInit()
        }
    #else
        /// Creates an empty host view measuring its monospaced cell size;
        /// call `install(app:)` to attach an app.
        public override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }
    #endif

    /// Restores an empty host view from an archive; call `install(app:)`
    /// to attach an app.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        let probe = NSAttributedString(string: "M", attributes: [.font: font])
        let s = probe.size()
        cellSize = CGSize(width: ceil(s.width), height: ceil(s.height))
        #if canImport(AppKit)
            // `.inVisibleRect` keeps the area matched to the visible bounds,
            // so `updateTrackingAreas` has nothing to recompute.
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self, userInfo: nil))
        #else
            #if !os(tvOS)
                isMultipleTouchEnabled = false
                let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
                addGestureRecognizer(hover)
                let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
                // Indirect scrolling only (trackpad, mouse wheel): touches
                // stay with `touchesBegan` and friends.
                scroll.allowedScrollTypesMask = .all
                scroll.allowedTouchTypes = []
                addGestureRecognizer(scroll)
            #endif
            backgroundColor = defaultBackground
        #endif
    }

    /// The interaction idiom this host's `FrameHost` recognizes gestures
    /// with: desktop on macOS, vision on visionOS, and on UIKit the
    /// `userInterfaceIdiom`: phone for `.phone`, desktop for `.mac` (a Mac
    /// Catalyst app optimized for Mac), and pad for everything else,
    /// including tvOS, an iPad-idiom Catalyst app, and an iPhone or iPad
    /// app running on a Mac, which reports its original idiom.
    package var interactionIdiom: InteractionIdiom {
        #if canImport(AppKit)
            return .desktop
        #elseif os(visionOS)
            return .vision
        #else
            switch traitCollection.userInterfaceIdiom {
            case .phone: return .phone
            case .mac: return .desktop
            default: return .pad
            }
        #endif
    }

    /// Attaches `app`: creates its `FrameHost` and back buffer sized to
    /// the current cell grid, wires the frame pump and event routing, and
    /// pumps the first frame. Installing again replaces the previous app.
    /// Ownership of the app region transfers into this MainActor host.
    public func install<A: App>(app: sending A) throws(SceneConfigurationError) {
        let graph = try compileSceneGraph(app)
        let surface = try graph.makePrimarySurface()
        install(surface: surface)
    }

    /// Installs one already-validated scene surface for a package-owned shell.
    package func install(surface: SceneSurface) {
        // `driver` and `handleEvent` are separately-stored, type-erased
        // closures (the view can't be generic over A without breaking the
        // two-phase init this class exposes), yet both must read and
        // mutate the same FrameHost/CellBuffer pair every frame. Boxing
        // that pair in one owner — rather than letting two closures each
        // implicitly share Swift's promoted capture storage for two loose
        // `var`s — makes the shared ownership visible at the call site
        // and keeps it intact if either closure is ever hoisted out.
        // A second install replaces the previous session wholesale; cancel
        // its model subscriptions instead of silently orphaning them.
        tearDownSession?()

        let session = Session(surface: surface, size: gridSize(), idiom: interactionIdiom)
        tearDownSession = {
            session.pump.cancelSubscriptions()
        }
        cancelPointerDeadline()
        pressedPointer = nil
        pointerDeadline = {
            session.pump.pointerDeadlineMillis
        }

        driver = { [weak self] in
            guard let self else { return }
            // The grid is re-synced through the pump's eager resize path,
            // so a layout pass that changed the extent is visible to this
            // frame rather than to the next one.
            let grid = self.gridSize()
            if grid != session.pump.size { session.pump.handle(.resize(grid)) }
            let outcome = session.pump.advance(into: &session.buffer) { painted in
                self.currentDrawList = self.drawListSerializer.serialize(painted)
            }
            guard outcome.produced else { return }
            self.placeNativeRegions(session.pump.nativeRegions)
            self.setNeedsDisplayCompat()
            if outcome.followUp { self.driver?() }
        }
        invalidateHost = {
            session.pump.invalidate()
        }
        handleEvent = { [weak self] event in
            session.pump.handle(event)
            self?.pumpIfNeeded(session.pump.needsFrame)
            // Any event can move the long-press deadline: a pointer sample,
            // Escape, a lifecycle cancel, or a pump that dropped the pressed
            // node.
            self?.armPointerDeadline()
            self?.afterEventDispatch?()
        }
        driver?()
    }

    /// Routes an event into the installed surface. Shells use this for native
    /// lifecycle transitions in addition to the view's own key/pointer events.
    package func send(_ event: InputEvent) {
        handleEvent?(event)
    }

    /// Cancels the installed host's subscriptions and detaches its closures.
    package func tearDown() {
        tearDownSession?()
        tearDownSession = nil
        driver = nil
        invalidateHost = nil
        handleEvent = nil
        afterEventDispatch = nil
        pointerDeadline = nil
        cancelPointerDeadline()
        pressedPointer = nil
    }

    /// Requests a frame after application state changes outside a Gama event.
    public func invalidate() {
        invalidateHost?()
        driver?()
    }

    // MARK: Native regions (ADR 0016)

    /// Attaches an application-owned view to the native region `id`. The
    /// application keeps ownership; the host adds it as a subview, places it
    /// on the region's frame each frame, hides it while the region is absent,
    /// and hands it first responder when Gama focus lands on the region.
    /// Attaching a different view to the same identity detaches the first.
    public func attach(_ view: GamaPlatformView, to id: NativeRegionID) {
        if let previous = attachedNativeViews[id], previous !== view {
            previous.removeFromSuperview()
        }
        // One view shows in one region: drop any other identity holding it,
        // so placement and a later detach of that identity cannot fight
        // over the same view.
        for (other, attached) in attachedNativeViews where other != id && attached === view {
            attachedNativeViews[other] = nil
            focusedNativeRegions.remove(other)
        }
        attachedNativeViews[id] = view
        #if canImport(AppKit)
            let alreadyAttached = unsafe view.superview === self
        #else
            let alreadyAttached = view.superview === self
        #endif
        if !alreadyAttached { addSubview(view) }
        view.isHidden = true
        placeNativeRegions(lastNativeRegions)
    }

    /// Removes the view attached to `id`, if any, from this host. If `id`
    /// currently holds Gama focus AND the window's first responder is still
    /// inside the detached view, first responder returns to the host;
    /// otherwise the detach leaves first responder untouched.
    public func detach(_ id: NativeRegionID) {
        guard let view = attachedNativeViews.removeValue(forKey: id) else { return }
        // Reclaim only if first responder is actually inside the detached
        // view right now — not merely because Gama last recorded it as
        // focused, which could be stale relative to a first responder the
        // user (or another control) has since moved elsewhere. Test against
        // the local `view` captured above, not a dictionary lookup — `view`
        // has already been removed from `attachedNativeViews`, so a lookup
        // by `id` would always come back nil here.
        let wasFocused = focusedNativeRegions.remove(id) != nil
        let shouldReclaim = wasFocused && firstResponderIsInside(view)
        view.removeFromSuperview()
        if shouldReclaim { giveFirstResponder(to: self) }
        placeNativeRegions(lastNativeRegions)
    }

    /// Whether `cells` lies wholly inside a region currently showing an
    /// attached view. Package-only so the no-overdraw rule is testable.
    package func isCoveredByNativeRegion(_ cells: Rect) -> Bool {
        shownNativeRegionCells.contains { region in
            cells.minX >= region.minX && cells.minY >= region.minY
                && cells.maxX <= region.maxX && cells.maxY <= region.maxY
        }
    }

    private func placeNativeRegions(_ regions: [NativeRegionFrame]) {
        lastNativeRegions = regions
        var byID: [NativeRegionID: NativeRegionFrame] = [:]
        for region in regions { byID[region.id] = region }
        var shown: [Rect] = []
        var focused: Set<NativeRegionID> = []
        // At most one region gains focus in a given frame (Gama focus is
        // single), but this stays a "last one wins" assignment rather than
        // an assumption, so a future multi-focus model degrades instead of
        // silently misbehaving.
        var newlyFocusedView: GamaPlatformView?
        for (id, view) in attachedNativeViews {
            guard let region = byID[id], region.frame.size.width > 0, region.frame.size.height > 0
            else {
                view.isHidden = true
                continue
            }
            view.frame = pixelRect(region.frame)
            view.isHidden = false
            shown.append(region.frame)
            if region.isFocused {
                focused.insert(id)
                if !focusedNativeRegions.contains(id) { newlyFocusedView = view }
            }
        }
        let lost = focusedNativeRegions.subtracting(focused)
        // Record the new focus set before attempting any handoff:
        // hardens against a re-entrant call (e.g. a responder-chain
        // callback triggered by `giveFirstResponder`) reading a stale
        // `focusedNativeRegions` while this call is still in progress.
        // Note this still records `id` as focused even when `window` is nil
        // and the handoff below is a no-op; the window-attach lifecycle
        // (`viewDidMoveToWindow`/`didMoveToWindow`) clears this set and
        // re-places regions once a window exists, so that deferred handoff
        // is retried rather than silently skipped.
        focusedNativeRegions = focused
        // Focus handed straight from one region to another must reach the
        // new view without an intervening bounce to the host:
        // a region gaining focus this frame always wins the handoff, and the
        // host only reclaims when nothing took focus this frame.
        if let newlyFocusedView {
            giveFirstResponder(to: newlyFocusedView)
        } else {
            // Reclaiming unconditionally would steal first responder from an
            // unrelated control the user (or another part of the app) just
            // focused: only reclaim when the window's current
            // first responder is still inside a view that just lost focus.
            if !lost.isEmpty, firstResponderIsInside(lost) {
                giveFirstResponder(to: self)
            }
        }
        if shown != shownNativeRegionCells {
            shownNativeRegionCells = shown
            setNeedsDisplayCompat()
        }
    }

    /// Whether the window's current first responder is one of `ids`'
    /// attached views, or a descendant of one — the precondition for the
    /// host reclaiming first responder after a region loses focus.
    private func firstResponderIsInside(_ ids: Set<NativeRegionID>) -> Bool {
        for id in ids {
            if let view = attachedNativeViews[id], firstResponderIsInside(view) {
                return true
            }
        }
        return false
    }

    /// Whether the window's current first responder is `view` itself, or a
    /// descendant of it. Takes the view directly (rather than a region id)
    /// so callers can test a view that has already been removed from
    /// `attachedNativeViews`.
    private func firstResponderIsInside(_ view: GamaPlatformView) -> Bool {
        #if canImport(AppKit)
            guard let responder = unsafe window?.firstResponder as? NSView else { return false }
            return responder.isDescendant(of: view)
        #else
            return isFirstResponderOrDescendant(view)
        #endif
    }

    #if canImport(UIKit)
        private func isFirstResponderOrDescendant(_ view: GamaPlatformView) -> Bool {
            if view.isFirstResponder { return true }
            for sub in view.subviews {
                if isFirstResponderOrDescendant(sub) { return true }
            }
            return false
        }
    #endif

    private func giveFirstResponder(to view: GamaPlatformView) {
        #if canImport(AppKit)
            _ = unsafe window?.makeFirstResponder(view)
        #else
            _ = view.becomeFirstResponder()
        #endif
    }

    /// Owns one primary-scene FrameHost + back buffer. Non-Sendable
    /// by design — it's only ever touched from `driver`/`handleEvent`,
    /// which are themselves MainActor-isolated because they're stored on
    /// this @MainActor class.
    private final class Session {
        var pump: HostPump
        var buffer: CellBuffer
        init(surface: SceneSurface, size: Size, idiom: InteractionIdiom) {
            pump = HostPump(host: FrameHost(surface: surface, idiom: idiom), size: size)
            buffer = CellBuffer(size: size)
        }
    }

    // MARK: Pointer samples (ADR 0018)

    /// Routes one raw pointer sample to the host and remembers the pressed
    /// pointer; the event route re-arms the long-press timer afterwards.
    private func sendPointer(_ sample: PointerEvent) {
        switch sample.phase {
        case .down:
            // Mirrors FrameHost: while a press is held, only the same
            // pointer and button pressing again (a lost release) replaces it.
            if pressedPointer == nil
                || (pressedPointer?.pointerID == sample.pointerID && pressedPointer?.button == sample.button)
            {
                pressedPointer = (sample.location, sample.kind, sample.pointerID, sample.button)
            }
        case .move:
            if pressedPointer?.pointerID == sample.pointerID {
                pressedPointer?.location = sample.location
            }
        case .up:
            if pressedPointer?.pointerID == sample.pointerID, pressedPointer?.button == sample.button {
                pressedPointer = nil
            }
        case .cancel:
            if pressedPointer?.pointerID == sample.pointerID { pressedPointer = nil }
        case .hover, .scroll, .stationary:
            break
        }
        handleEvent?(.pointerEvent(sample))
    }

    /// Arms the one-shot timer for the host's pending deadline, or cancels
    /// it when there is none. The timer runs on the main run loop in the
    /// common modes, so it still fires during event tracking (a menu, a
    /// live resize, a scroll view tracking a touch), and its callback is
    /// already on the main actor.
    private func armPointerDeadline() {
        let deadline = pointerDeadline?()
        guard deadline != armedPointerDeadlineMillis else { return }
        cancelPointerDeadline()
        guard let deadline else { return }
        armedPointerDeadlineMillis = deadline
        let now = Self.uptimeMillis()
        let delay = deadline > now ? Double(deadline - now) / 1000 : 0
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliverPointerDeadline() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerDeadlineTimer = timer
    }

    private func cancelPointerDeadline() {
        pointerDeadlineTimer?.invalidate()
        pointerDeadlineTimer = nil
        armedPointerDeadlineMillis = nil
    }

    /// Delivers the stationary sample the armed deadline is waiting for, for
    /// the pressed pointer at its last cell. The timer calls this; it is
    /// package-visible so a test can fire it without waiting.
    package func deliverPointerDeadline() {
        guard let deadline = armedPointerDeadlineMillis else { return }
        cancelPointerDeadline()
        guard let pressed = pressedPointer else { return }
        sendPointer(
            PointerEvent(
                phase: .stationary, location: pressed.location, kind: pressed.kind,
                pointerID: pressed.pointerID, timestampMillis: max(Self.uptimeMillis(), deadline)))
    }

    /// Milliseconds since boot: the clock `NSEvent.timestamp` and
    /// `UITouch.timestamp` count in, so timer samples and platform samples
    /// compare.
    private static func uptimeMillis() -> UInt64 {
        millis(ProcessInfo.processInfo.systemUptime)
    }

    private static func millis(_ seconds: TimeInterval) -> UInt64 {
        seconds > 0 ? UInt64(seconds * 1000) : 0
    }

    /// Converts a scroll delta into whole cells, carrying the fraction in
    /// `remainder`. `precise` deltas are points (trackpad, Magic Mouse) and
    /// are divided by the cell size; line deltas are one cell per line. The
    /// platform's positive delta reveals content above or to the left, so it
    /// is negated into Gama's sign (positive reveals the lines below).
    package static func scrollCells(
        deltaX: CGFloat, deltaY: CGFloat, precise: Bool, cellSize: CGSize,
        remainder: inout CGSize
    ) -> Point {
        let width = precise ? max(cellSize.width, 1) : 1
        let height = precise ? max(cellSize.height, 1) : 1
        remainder.width -= deltaX / width
        remainder.height -= deltaY / height
        let columns = remainder.width.rounded(.towardZero)
        let rows = remainder.height.rounded(.towardZero)
        remainder.width -= columns
        remainder.height -= rows
        return Point(x: Int(columns), y: Int(rows))
    }

    /// Grid cell under a view-local point; floors, so a drag past the top or
    /// left edge reports a negative cell rather than cell zero.
    private func cell(atLocal local: CGPoint) -> Point {
        guard cellSize.width > 0, cellSize.height > 0 else { return Point(x: 0, y: 0) }
        return Point(
            x: Int((local.x / cellSize.width).rounded(.down)),
            y: Int((local.y / cellSize.height).rounded(.down)))
    }

    private func pumpIfNeeded(_ needed: Bool) {
        if needed { driver?() }
    }

    private func gridSize() -> Size {
        guard cellSize.width > 0, cellSize.height > 0 else {
            return Size(width: 80, height: 24)
        }
        return Size(
            width: max(1, Int(bounds.width / cellSize.width)),
            height: max(1, Int(bounds.height / cellSize.height)))
    }

    private func setNeedsDisplayCompat() {
        #if canImport(AppKit)
            needsDisplay = true
        #else
            setNeedsDisplay()
        #endif
    }

    // MARK: Layout / resize

    #if canImport(AppKit)
        /// Forwards each AppKit layout pass to the host as a `.resize`
        /// event and pumps a frame at the new grid size.
        public override func layout() {
            super.layout()
            handleEvent?(.resize(gridSize()))
            driver?()
        }
        /// Accepts first-responder status so keyboard events reach the
        /// view directly.
        public override var acceptsFirstResponder: Bool { true }
        /// Uses a top-left origin so view coordinates match the cell grid.
        public override var isFlipped: Bool { true }  // y-down, like the grid
        /// Claims first-responder status as soon as the view lands in a
        /// window, so keys flow without an extra click. Also clears and
        /// re-places native-region focus: a region already focused
        /// before this host had a window recorded that focus in
        /// `focusedNativeRegions` even though the handoff to its attached
        /// view was a no-op (no `window` to call `makeFirstResponder` on).
        /// Clearing the set here makes the region look "newly focused"
        /// again to the placement that follows, so the deferred handoff to
        /// its attached view is retried now that a window exists.
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            _ = unsafe window?.makeFirstResponder(self)
            focusedNativeRegions.removeAll()
            placeNativeRegions(lastNativeRegions)
        }
    #else
        /// Forwards each UIKit layout pass to the host as a `.resize`
        /// event and pumps a frame at the new grid size.
        public override func layoutSubviews() {
            super.layoutSubviews()
            handleEvent?(.resize(gridSize()))
            driver?()
        }
        /// Accepts first-responder status so hardware key presses reach
        /// the view.
        public override var canBecomeFirstResponder: Bool { true }
        /// Becomes first responder as soon as the view lands in a window,
        /// so hardware keys flow immediately. Also clears and re-places
        /// native-region focus — see the AppKit `viewDidMoveToWindow`
        /// doc comment for the deferred-handoff rationale.
        public override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                becomeFirstResponder()
                focusedNativeRegions.removeAll()
                placeNativeRegions(lastNativeRegions)
            }
        }
    #endif

    // MARK: Drawing

    /// Replays the current `DrawList` through CoreGraphics: fills the
    /// background, then draws each command — rectangle fills and styled
    /// text runs — at cell-grid positions scaled by the measured cell
    /// size. Bold and italic map to font traits, underline and
    /// strikethrough to string attributes, dim to reduced alpha, and
    /// inverse swaps foreground and background.
    public override func draw(_ dirtyRect: CGRect) {
        #if canImport(AppKit)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        #else
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
        #endif

        ctx.setFillColor(defaultBackground.cgColor)
        ctx.fill(bounds)

        for command in currentDrawList.commands {
            switch command {
            case .fillRect(let r, let color):
                if isCoveredByNativeRegion(r) { continue }
                ctx.setFillColor(platformColor(color, fallback: defaultBackground).cgColor)
                ctx.fill(pixelRect(r))

            case .text(let s, let p, let style):
                if isCoveredByNativeRegion(
                    Rect(origin: p, size: Size(width: TextLayout.displayWidth(of: s), height: 1))
                ) { continue }
                var fg = style.foreground
                var bg = style.background
                if style.attributes.contains(.inverse) { swap(&fg, &bg) }
                var color = platformColor(fg, fallback: defaultForeground)
                if style.attributes.contains(.dim) {
                    color = color.withAlphaComponent(0.6)
                }
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: styledFont(for: style),
                    .foregroundColor: color,
                ]
                if style.attributes.contains(.underline) {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if style.attributes.contains(.strikethrough) {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                let origin = CGPoint(
                    x: CGFloat(p.x) * cellSize.width,
                    y: CGFloat(p.y) * cellSize.height)
                NSAttributedString(string: s, attributes: attrs).draw(at: origin)
            }
        }
    }

    private func pixelRect(_ r: Rect) -> CGRect {
        CGRect(
            x: CGFloat(r.minX) * cellSize.width,
            y: CGFloat(r.minY) * cellSize.height,
            width: CGFloat(r.size.width) * cellSize.width,
            height: CGFloat(r.size.height) * cellSize.height)
    }

    /// The font for `style`, built once per distinct bold/italic
    /// combination and reused thereafter. See the styled-font cache note
    /// above ``fontCache`` for why per-command construction had to stop.
    /// Package-only so the regression test can exercise it directly.
    package func styledFont(for style: TextStyle) -> PlatformFont {
        let key = style.attributes.intersection(Self.fontDefiningAttributes)
        if let cached = fontCache[key] { return cached }
        let built = makeStyledFont(for: key)
        fontCache[key] = built
        return built
    }

    private func makeStyledFont(for attributes: TextAttributes) -> PlatformFont {
        styledFontConstructionCount += 1
        var weight: PlatformFont.Weight = .regular
        if attributes.contains(.bold) { weight = .bold }
        var f = PlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: weight)
        if attributes.contains(.italic) {
            #if canImport(AppKit)
                // NSFontDescriptor, not the legacy NSFontManager singleton.
                let d = f.fontDescriptor.withSymbolicTraits(.italic)
                f = NSFont(descriptor: d, size: f.pointSize) ?? f
            #else
                if let d = f.fontDescriptor.withSymbolicTraits(.traitItalic) {
                    f = UIFont(descriptor: d, size: f.pointSize)
                }
            #endif
        }
        return f
    }

    private func platformColor(_ c: Color, fallback: PlatformColor) -> PlatformColor {
        c.isDefault
            ? fallback
            : PlatformColor(
                red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                blue: CGFloat(c.b) / 255, alpha: 1)
    }

    // MARK: Accessibility
    //
    // The host is a container, not a single element: each non-blank grid row
    // is published as its own static-text child so VoiceOver can walk the
    // surface line by line instead of reading it as one opaque blob. Every
    // accessor also arms change notifications, because a query is the only
    // reliable signal that an assistive-technology client is attached — the
    // frame path stays free of accessibility work until then.

    #if canImport(AppKit)
        /// Reports the host as a container rather than a single element; the
        /// readable content is its per-row children.
        public override func isAccessibilityElement() -> Bool {
            accessibilityHasBeenQueried = true
            return false
        }

        /// Exposes the host as a group so assistive technologies descend
        /// into its per-row children.
        public override func accessibilityRole() -> NSAccessibility.Role? {
            accessibilityHasBeenQueried = true
            return .group
        }

        /// Names the container itself; the rendered text lives on the
        /// children, not here.
        public override func accessibilityLabel() -> String? {
            accessibilityHasBeenQueried = true
            return "Gama surface"
        }

        /// One static-text child per non-blank row of the current frame,
        /// plus any shown attached native region views, all in top-to-bottom
        /// reading order.
        public override func accessibilityChildren() -> [Any]? {
            accessibilityHasBeenQueried = true
            return accessibilityChildrenInReadingOrder()
        }
    #else
        /// Reports the host as a container rather than a single element; the
        /// readable content is its per-row elements.
        public override var isAccessibilityElement: Bool {
            get {
                accessibilityHasBeenQueried = true
                return false
            }
            set { _ = newValue }
        }

        /// One static-text element per non-blank row of the current frame,
        /// plus any shown attached native region views, all in top-to-bottom
        /// reading order.
        public override var accessibilityElements: [Any]? {
            get {
                accessibilityHasBeenQueried = true
                return accessibilityChildrenInReadingOrder()
            }
            set { _ = newValue }
        }
    #endif

    // MARK: Events — macOS

    #if canImport(AppKit)
        /// Translates an AppKit key event into a Gama `Key` and routes it
        /// to the host; keys with no mapping are ignored.
        public override func keyDown(with event: NSEvent) {
            guard let key = AppKitKeyTranslation.key(from: event) else { return }
            handleEvent?(.key(key))
        }

        /// Routes a primary-button press to the host as a down sample.
        public override func mouseDown(with event: NSEvent) { sendMouse(.down, event) }
        /// Routes a primary-button drag to the host as a move sample.
        public override func mouseDragged(with event: NSEvent) { sendMouse(.move, event) }
        /// Routes a primary-button release to the host as an up sample.
        public override func mouseUp(with event: NSEvent) { sendMouse(.up, event) }
        /// Routes a secondary-button press to the host as a down sample,
        /// instead of AppKit's default context menu.
        public override func rightMouseDown(with event: NSEvent) { sendMouse(.down, event) }
        /// Routes a secondary-button drag to the host as a move sample.
        public override func rightMouseDragged(with event: NSEvent) { sendMouse(.move, event) }
        /// Routes a secondary-button release to the host as an up sample.
        public override func rightMouseUp(with event: NSEvent) { sendMouse(.up, event) }
        /// Routes a middle or other button press to the host as a down sample.
        public override func otherMouseDown(with event: NSEvent) { sendMouse(.down, event) }
        /// Routes a middle or other button drag to the host as a move sample.
        public override func otherMouseDragged(with event: NSEvent) { sendMouse(.move, event) }
        /// Routes a middle or other button release to the host as an up sample.
        public override func otherMouseUp(with event: NSEvent) { sendMouse(.up, event) }
        /// Routes pointer motion with no button held (from the tracking
        /// area) to the host as a hover sample.
        public override func mouseMoved(with event: NSEvent) { sendMouse(.hover, event) }

        /// Reports the pointer leaving the view as a hover outside the grid,
        /// which clears hover. It is not a cancel: a drag captured outside
        /// the view keeps arriving through `mouseDragged`.
        public override func mouseExited(with event: NSEvent) {
            sendPointer(
                PointerEvent(
                    phase: .hover, location: Point(x: -1, y: -1),
                    modifiers: Self.modifiers(event.modifierFlags),
                    timestampMillis: Self.millis(event.timestamp)))
        }

        /// Accumulates wheel and trackpad scrolling into whole cells and
        /// routes each whole-cell step to the host as a scroll sample.
        public override func scrollWheel(with event: NSEvent) {
            let cells = Self.scrollCells(
                deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                precise: event.hasPreciseScrollingDeltas, cellSize: cellSize,
                remainder: &scrollRemainder)
            guard cells != Point(x: 0, y: 0) else { return }
            sendPointer(
                PointerEvent(
                    phase: .scroll, location: gridPoint(event.locationInWindow),
                    modifiers: Self.modifiers(event.modifierFlags), scroll: cells,
                    timestampMillis: Self.millis(event.timestamp)))
        }

        private func sendMouse(_ phase: PointerEvent.Phase, _ event: NSEvent) {
            sendPointer(
                PointerEvent(
                    phase: phase, location: gridPoint(event.locationInWindow),
                    kind: event.subtype == .tabletPoint ? .pen : .mouse,
                    button: phase == .hover ? 0 : Self.button(event),
                    modifiers: Self.modifiers(event.modifierFlags),
                    timestampMillis: Self.millis(event.timestamp)))
        }

        private func gridPoint(_ windowPoint: NSPoint) -> Point {
            cell(atLocal: convert(windowPoint, from: nil))
        }

        /// The button from the event type, which is authoritative for the
        /// left and right families; `buttonNumber` only distinguishes the
        /// other buttons (2 is middle).
        private static func button(_ event: NSEvent) -> Int {
            switch event.type {
            case .leftMouseDown, .leftMouseDragged, .leftMouseUp: return 0
            case .rightMouseDown, .rightMouseDragged, .rightMouseUp: return 1
            default: return max(2, event.buttonNumber)
            }
        }

        private static func modifiers(_ flags: NSEvent.ModifierFlags) -> PointerEvent.Modifiers {
            var modifiers: PointerEvent.Modifiers = []
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.command) { modifiers.insert(.command) }
            return modifiers
        }

    #else

        // MARK: Events — iOS/tvOS/visionOS

        /// Starts tracking the first touch that lands, by identity, and
        /// routes it to the host as a down sample. Later touches are ignored
        /// until it lifts: one pointer is captured at a time.
        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard trackedTouch == nil, let t = touches.first else { return }
            trackedTouch = t
            nextTouchID &+= 1
            sendTouch(.down, t, event)
        }

        /// Routes the tracked touch's movement to the host as a move sample.
        public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = trackedTouch, touches.contains(t) else { return }
            sendTouch(.move, t, event)
        }

        /// Routes the tracked touch's lift to the host as an up sample.
        public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = trackedTouch, touches.contains(t) else { return }
            sendTouch(.up, t, event)
            trackedTouch = nil
        }

        /// Routes a cancelled tracked touch to the host as a cancel sample,
        /// so a captured gesture ends with `cancelled` and never sticks.
        public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = trackedTouch, touches.contains(t) else { return }
            sendTouch(.cancel, t, event)
            trackedTouch = nil
        }

        private func sendTouch(_ phase: PointerEvent.Phase, _ touch: UITouch, _ event: UIEvent?) {
            sendPointer(
                PointerEvent(
                    phase: phase, location: gridPoint(touch.location(in: self)),
                    kind: Self.kind(touch.type),
                    modifiers: Self.modifiers(event?.modifierFlags ?? []),
                    pointerID: nextTouchID, timestampMillis: Self.millis(touch.timestamp)))
        }

        /// `.direct` is a finger, `.pencil` a stylus, and an indirect pointer
        /// (trackpad or mouse on iPad) a cursor.
        private static func kind(_ type: UITouch.TouchType) -> PointerEvent.Kind {
            switch type {
            case .pencil: return .pen
            case .indirectPointer: return .mouse
            default: return .touch
            }
        }

        private static func modifiers(_ flags: UIKeyModifierFlags) -> PointerEvent.Modifiers {
            var modifiers: PointerEvent.Modifiers = []
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.alternate) { modifiers.insert(.option) }
            if flags.contains(.command) { modifiers.insert(.command) }
            return modifiers
        }

        #if !os(tvOS)
            /// Pointer hover (iPad trackpad or mouse, visionOS gaze) as hover
            /// samples; the end of a hover is a hover outside the grid.
            @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
                let location: Point
                switch recognizer.state {
                case .began, .changed: location = gridPoint(recognizer.location(in: self))
                default: location = Point(x: -1, y: -1)
                }
                sendPointer(
                    PointerEvent(
                        phase: .hover, location: location,
                        modifiers: Self.modifiers(recognizer.modifierFlags),
                        timestampMillis: Self.uptimeMillis()))
            }

            /// Indirect scrolling (trackpad, wheel) as scroll samples; the
            /// pan translation is consumed each callback and accumulated
            /// into whole cells.
            @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
                guard recognizer.state == .began || recognizer.state == .changed else {
                    scrollRemainder = .zero
                    return
                }
                let translation = recognizer.translation(in: self)
                recognizer.setTranslation(.zero, in: self)
                let cells = Self.scrollCells(
                    deltaX: translation.x, deltaY: translation.y, precise: true,
                    cellSize: cellSize, remainder: &scrollRemainder)
                guard cells != Point(x: 0, y: 0) else { return }
                sendPointer(
                    PointerEvent(
                        phase: .scroll, location: gridPoint(recognizer.location(in: self)),
                        modifiers: Self.modifiers(recognizer.modifierFlags), scroll: cells,
                        timestampMillis: Self.uptimeMillis()))
            }
        #endif

        /// Translates hardware key presses (`UIPress.key`) into Gama keys
        /// and routes them to the host, forwarding any press it cannot
        /// translate to the superclass.
        public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key, let translated = Self.key(from: key) else { continue }
                handleEvent?(.key(translated))
                handled = true
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }

        private func gridPoint(_ local: CGPoint) -> Point {
            cell(atLocal: local)
        }

        // Hardware keyboard (iPad etc.)
        /// Key commands capturing arrow, Enter, Tab, Shift-Tab, and Escape
        /// presses from a hardware keyboard, each routed to the host as
        /// the matching `Key`.
        public override var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(kUp)),
                UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(kDown)),
                UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(kLeft)),
                UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(kRight)),
                UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(kEnter)),
                UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(kTab)),
                UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(kBackTab)),
                UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(kEscape)),
            ]
        }
        @objc private func kUp() { handleEvent?(.key(.up)) }
        @objc private func kDown() { handleEvent?(.key(.down)) }
        @objc private func kLeft() { handleEvent?(.key(.left)) }
        @objc private func kRight() { handleEvent?(.key(.right)) }
        @objc private func kEnter() { handleEvent?(.key(.enter)) }
        @objc private func kTab() { handleEvent?(.key(.tab)) }
        @objc private func kBackTab() { handleEvent?(.key(.backTab)) }
        @objc private func kEscape() { handleEvent?(.key(.escape)) }

        private static func key(from key: UIKey) -> Key? {
            switch key.keyCode {
            case .keyboardUpArrow: return .up
            case .keyboardDownArrow: return .down
            case .keyboardLeftArrow: return .left
            case .keyboardRightArrow: return .right
            case .keyboardReturnOrEnter, .keypadEnter: return .enter
            case .keyboardEscape: return .escape
            case .keyboardTab:
                return key.modifierFlags.contains(.shift) ? .backTab : .tab
            case .keyboardDeleteOrBackspace: return .backspace
            case .keyboardDeleteForward: return .delete
            case .keyboardHome: return .home
            case .keyboardEnd: return .end
            case .keyboardPageUp: return .pageUp
            case .keyboardPageDown: return .pageDown
            default: break
            }
            guard let character = key.charactersIgnoringModifiers.first else { return nil }
            if key.modifierFlags.contains(.control), character.isLetter {
                return .ctrl(Character(character.lowercased()))
            }
            return .character(character)
        }
    #endif
}

#endif  // canImport(AppKit) || canImport(UIKit)
