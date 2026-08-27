//  GamaHostView.swift — GamaAppleUI
//  Native Apple GUI backend: an NSView/UIView that hosts a Gama app,
//  drawing the shared DrawList through CoreGraphics with a monospaced
//  system font. Keyboard + mouse on macOS; taps on iOS/tvOS/visionOS.
//  Entire target is @MainActor — UIKit/AppKit isolation is enforced by
//  the compiler, not convention.
//
//  macOS:  window.contentView = GamaHostView(app: MyApp())
//  iOS:    view.addSubview(GamaHostView(app: MyApp(), frame: view.bounds))

#if canImport(AppKit) || canImport(UIKit)

#if canImport(AppKit)
    import AppKit
    /// The platform view class `GamaHostView` extends — `NSView` on macOS.
    public typealias GamaPlatformView = NSView
    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
#else
    import UIKit
    /// The platform view class `GamaHostView` extends — `UIView` on
    /// iOS/tvOS/visionOS.
    public typealias GamaPlatformView = UIView
    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
#endif

import GamaCore
import GamaDraw

/// A native AppKit/UIKit view hosting one Gama app: it pumps the app's
/// `FrameHost`, paints the shared `DrawList` through CoreGraphics as a
/// monospaced character grid, and translates platform keyboard, mouse, and
/// touch input into `InputEvent`s. Like every backend it only carries
/// events in and frames out — interaction semantics stay in GamaCore.
/// `@MainActor` end to end, so AppKit/UIKit isolation is enforced by the
/// compiler rather than convention.
@MainActor
public final class GamaHostView: GamaPlatformView {
    private var driver: (() -> Void)?  // erased frame pump
    private var invalidateHost: (() -> Void)?
    private var handleEvent: ((InputEvent) -> Void)?
    /// Most recently rendered shared draw list, exposed read-only for host
    /// accessibility adapters, diagnostics, and runtime smoke validation.
    public private(set) var currentDrawList = DrawList(size: Size(width: 0, height: 0))

    private let font = PlatformFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var cellSize: CGSize = .zero
    private var defaultForeground: PlatformColor = .white
    private var defaultBackground: PlatformColor = .black

    // MARK: Init

    /// Creates a zero-frame view with `app` installed — one-step shorthand
    /// for `init(frame:)` followed by `install(app:)`.
    public convenience init<A: App>(app: A) {
        self.init(frame: .zero)
        install(app: app)
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
    public func install<A: App>(app: A) {
        // `driver` and `handleEvent` are separately-stored, type-erased
        // closures (the view can't be generic over A without breaking the
        // two-phase init this class exposes), yet both must read and
        // mutate the same FrameHost/CellBuffer pair every frame. Boxing
        // that pair in one owner — rather than letting two closures each
        // implicitly share Swift's promoted capture storage for two loose
        // `var`s — makes the shared ownership visible at the call site
        // and keeps it intact if either closure is ever hoisted out.
        let session = Session<A>(app: app, size: gridSize())

        driver = { [weak self] in
            guard let self else { return }
            let grid = self.gridSize()
            if session.buffer.size != grid { session.buffer.resize(grid) }
            guard session.host.needsFrame else { return }
            let laid = session.host.pump(size: grid)
            session.buffer.clearBack()
            CellPainter.paint(laid, into: &session.buffer)
            self.currentDrawList = DrawList.from(session.buffer)
            self.setNeedsDisplayCompat()
        }
        invalidateHost = {
            session.host.invalidate()
        }
        handleEvent = { [weak self] event in
            session.host.handle(event)
            self?.pumpIfNeeded(session.host.needsFrame)
        }
        driver?()
    }

    /// Requests a frame after application state changes outside a Gama event.
    public func invalidate() {
        invalidateHost?()
        driver?()
    }

    /// Owns one app instance's live FrameHost + back buffer. Non-Sendable
    /// by design — it's only ever touched from `driver`/`handleEvent`,
    /// which are themselves MainActor-isolated because they're stored on
    /// this @MainActor class.
    private final class Session<A: App> {
        var host: FrameHost<A>
        var buffer: CellBuffer
        init(app: A, size: Size) {
            host = FrameHost<A>(app: app)
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
            if window != nil { window?.makeFirstResponder(self) }
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

    private func styledFont(for style: TextStyle) -> PlatformFont {
        var weight: PlatformFont.Weight = .regular
        if style.attributes.contains(.bold) { weight = .bold }
        var f = PlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: weight)
        if style.attributes.contains(.italic) {
            #if canImport(AppKit)
                f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
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
