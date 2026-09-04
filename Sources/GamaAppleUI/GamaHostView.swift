//  GamaHostView.swift — GamaAppleUI
//  Native Apple GUI backend: an NSView/UIView that hosts a Gama app,
//  drawing the shared DrawList through CoreGraphics with a monospaced
//  system font. Keyboard + mouse on macOS; taps on iOS/tvOS/visionOS.
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

    private var cellSize: CGSize = .zero
    /// Measured monospaced cell size, for the accessibility adapter's
    /// grid-to-view rectangle conversion.
    var accessibilityCellSize: CGSize { cellSize }
    private let defaultForeground: PlatformColor = .white
    private let defaultBackground: PlatformColor = .black

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
        #if canImport(UIKit)
            #if !os(tvOS)
                isMultipleTouchEnabled = false
            #endif
            backgroundColor = defaultBackground
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

        let session = Session(surface: surface, size: gridSize())
        tearDownSession = {
            session.pump.cancelSubscriptions()
        }

        driver = { [weak self] in
            guard let self else { return }
            // The grid is re-synced through the pump's eager resize path,
            // so a layout pass that changed the extent is visible to this
            // frame rather than to the next one.
            let grid = self.gridSize()
            if grid != session.pump.size { session.pump.handle(.resize(grid)) }
            let outcome = session.pump.advance(into: &session.buffer) { painted in
                self.currentDrawList = DrawList.from(painted)
            }
            guard outcome.produced else { return }
            self.setNeedsDisplayCompat()
            if outcome.followUp { self.driver?() }
        }
        invalidateHost = {
            session.pump.invalidate()
        }
        handleEvent = { [weak self] event in
            session.pump.handle(event)
            self?.pumpIfNeeded(session.pump.needsFrame)
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
    }

    /// Requests a frame after application state changes outside a Gama event.
    public func invalidate() {
        invalidateHost?()
        driver?()
    }

    /// Owns one primary-scene FrameHost + back buffer. Non-Sendable
    /// by design — it's only ever touched from `driver`/`handleEvent`,
    /// which are themselves MainActor-isolated because they're stored on
    /// this @MainActor class.
    private final class Session {
        var pump: HostPump
        var buffer: CellBuffer
        init(surface: SceneSurface, size: Size) {
            pump = HostPump(host: FrameHost(surface: surface), size: size)
            buffer = CellBuffer(size: size)
        }
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
        /// window, so keys flow without an extra click.
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            _ = unsafe window?.makeFirstResponder(self)
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
        /// so hardware keys flow immediately.
        public override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
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
                ctx.setFillColor(platformColor(color, fallback: defaultBackground).cgColor)
                ctx.fill(pixelRect(r))

            case .text(let s, let p, let style):
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

        /// One static-text child per non-blank row of the current frame, in
        /// top-to-bottom reading order.
        public override func accessibilityChildren() -> [Any]? {
            accessibilityHasBeenQueried = true
            return accessibilityLineElements()
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
        /// in top-to-bottom reading order.
        public override var accessibilityElements: [Any]? {
            get {
                accessibilityHasBeenQueried = true
                return accessibilityLineElements()
            }
            set { _ = newValue }
        }
    #endif

    // MARK: Events — macOS

    #if canImport(AppKit)
        /// Translates an AppKit key event into a Gama `Key` and routes it
        /// to the host; keys with no mapping are ignored.
        public override func keyDown(with event: NSEvent) {
            guard let key = Self.key(from: event) else { return }
            handleEvent?(.key(key))
        }

        /// Routes a left-button press to the host as a pressed pointer
        /// event at the clicked cell.
        public override func mouseDown(with event: NSEvent) {
            handleEvent?(.pointer(gridPoint(event.locationInWindow), pressed: true))
        }

        /// Routes a left-button release to the host as a released pointer
        /// event at the clicked cell.
        public override func mouseUp(with event: NSEvent) {
            handleEvent?(.pointer(gridPoint(event.locationInWindow), pressed: false))
        }

        private func gridPoint(_ windowPoint: NSPoint) -> Point {
            let local = convert(windowPoint, from: nil)
            return Point(
                x: Int(local.x / cellSize.width),
                y: Int(local.y / cellSize.height))
        }

        private static func key(from event: NSEvent) -> Key? {
            switch event.keyCode {
            case 126: return .up
            case 125: return .down
            case 123: return .left
            case 124: return .right
            case 36, 76: return .enter
            case 53: return .escape
            case 48: return event.modifierFlags.contains(.shift) ? .backTab : .tab
            case 51: return .backspace
            case 117: return .delete
            case 115: return .home
            case 119: return .end
            case 116: return .pageUp
            case 121: return .pageDown
            default: break
            }
            guard let chars = event.charactersIgnoringModifiers, let ch = chars.first
            else { return nil }
            if event.modifierFlags.contains(.control), ch.isLetter {
                return .ctrl(Character(ch.lowercased()))
            }
            return .character(ch)
        }
    #else

        // MARK: Events — iOS/tvOS/visionOS

        /// Routes the first touch's landing to the host as a pressed
        /// pointer event at the touched cell.
        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            handleEvent?(.pointer(gridPoint(t.location(in: self)), pressed: true))
        }

        /// Routes the first touch's lift to the host as a released pointer
        /// event at the touched cell.
        public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            handleEvent?(.pointer(gridPoint(t.location(in: self)), pressed: false))
        }

        /// Treats a cancelled touch like a release, so a pressed pointer
        /// never sticks.
        public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            handleEvent?(.pointer(gridPoint(t.location(in: self)), pressed: false))
        }

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
            Point(
                x: Int(local.x / cellSize.width),
                y: Int(local.y / cellSize.height))
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
