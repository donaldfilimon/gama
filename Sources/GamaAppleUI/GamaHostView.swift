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
    public typealias GamaPlatformView = NSView
    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
#else
    import UIKit
    public typealias GamaPlatformView = UIView
    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
#endif

import GamaCore
import GamaDraw

@MainActor
public final class GamaHostView: GamaPlatformView {
    // Closure types carry explicit @MainActor so the isolation contract
    // survives any refactor that moves them off this class.
    private var driver: (@MainActor () -> Void)?  // erased frame pump
    private var invalidateHost: (@MainActor () -> Void)?
    private var handleEvent: (@MainActor (InputEvent) -> Void)?
    /// Cancels the current session's model subscriptions; called before a
    /// second `install` replaces the session wholesale.
    private var tearDownSession: (@MainActor () -> Void)?
    /// Most recently rendered shared draw list, exposed read-only for host
    /// accessibility adapters, diagnostics, and runtime smoke validation.
    public private(set) var currentDrawList = DrawList(size: Size(width: 0, height: 0))

    private let font = PlatformFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var cellSize: CGSize = .zero
    private let defaultForeground: PlatformColor = .white
    private let defaultBackground: PlatformColor = .black

    // MARK: Init

    public convenience init<A: App>(app: A) {
        self.init(frame: .zero)
        install(app: app)
    }

    #if canImport(AppKit)
        public override init(frame: NSRect) {
            super.init(frame: frame)
            commonInit()
        }
    #else
        public override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }
    #endif

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

    public func install<A: App>(app: A) {
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

        let session = Session<A>(app: app, size: gridSize())
        tearDownSession = {
            session.host.cancelSubscriptions()
        }

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
        public override func layout() {
            super.layout()
            handleEvent?(.resize(gridSize()))
            driver?()
        }
        public override var acceptsFirstResponder: Bool { true }
        public override var isFlipped: Bool { true }  // y-down, like the grid
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            _ = window?.makeFirstResponder(self)
        }
    #else
        public override func layoutSubviews() {
            super.layoutSubviews()
            handleEvent?(.resize(gridSize()))
            driver?()
        }
        public override var canBecomeFirstResponder: Bool { true }
        public override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }
    #endif

    // MARK: Drawing

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

    // MARK: Events — macOS

    #if canImport(AppKit)
        public override func keyDown(with event: NSEvent) {
            guard let key = Self.key(from: event) else { return }
            handleEvent?(.key(key))
        }

        public override func mouseDown(with event: NSEvent) {
            handleEvent?(.pointer(gridPoint(event.locationInWindow), pressed: true))
        }

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

        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            handleEvent?(.pointer(gridPoint(t.location(in: self)), pressed: true))
        }

        public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            handleEvent?(.pointer(gridPoint(t.location(in: self)), pressed: false))
        }

        public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            handleEvent?(.pointer(gridPoint(t.location(in: self)), pressed: false))
        }

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
