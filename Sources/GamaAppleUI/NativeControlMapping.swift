//  NativeControlMapping.swift — GamaAppleUI
//  Maps a presented Gama view (ADR 0017, Decision 4) to the AppKit view
//  that shows it, and updates that view in place when its kind or style
//  changes. Each mapped view carries its presentation identity so the host
//  can route its events back to `FrameHost`.

#if canImport(AppKit)

    import AppKit
    import GamaCore

    /// Implemented by every view the native host creates, so events and
    /// focus changes can be routed back by identity.
    @MainActor
    protocol NativePresentedView: AnyObject {
        /// The presentation identity this view shows.
        var presentationID: PresentationID { get set }
        /// The host that created the view; weak, the host owns the view tree.
        var nativeHost: GamaNativeHostView? { get set }
    }

    extension NativePresentedView {
        /// The interactive node this view presents, when it is one.
        var nodeID: NodeID? {
            if case .node(let id) = presentationID { return id }
            return nil
        }
    }

    /// A top-left-origin container, so child frames computed by
    /// `LayoutEngine` (y grows down) apply unchanged.
    class NativeFlippedView: NSView, NativePresentedView {
        var presentationID: PresentationID = .path(0)
        weak var nativeHost: GamaNativeHostView?
        override var isFlipped: Bool { true }
    }

    /// Static text: a non-editable, non-bezeled `NSTextField` that wraps at
    /// its frame width.
    final class NativeLabel: NSTextField, NativePresentedView {
        var presentationID: PresentationID = .path(0)
        weak var nativeHost: GamaNativeHostView?
    }

    /// A push button or checkbox that reports activation and focus.
    final class NativeButton: NSButton, NativePresentedView {
        var presentationID: PresentationID = .path(0)
        weak var nativeHost: GamaNativeHostView?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted, let nodeID { nativeHost?.controlDidTakeFocus(nodeID) }
            return accepted
        }
    }

    /// An editable single-line text field that reports focus.
    final class NativeTextField: NSTextField, NativePresentedView {
        var presentationID: PresentationID = .path(0)
        weak var nativeHost: GamaNativeHostView?

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted, let nodeID { nativeHost?.controlDidTakeFocus(nodeID) }
            return accepted
        }
    }

    /// A determinate bar, or a spinner when the fraction is unknown.
    final class NativeProgress: NSProgressIndicator, NativePresentedView {
        var presentationID: PresentationID = .path(0)
        weak var nativeHost: GamaNativeHostView?
    }

    /// A rule drawn by `NSBox`.
    final class NativeSeparator: NSBox, NativePresentedView {
        var presentationID: PresentationID = .path(0)
        weak var nativeHost: GamaNativeHostView?
    }

    /// A `background` or `border` container: a layer-backed view with a fill
    /// and an optional border, plus the border's title when it has one.
    final class NativeContainer: NativeFlippedView {
        /// Host-owned decoration showing the border title; not a presented
        /// view, so the op applier leaves it in place.
        var titleLabel: NSTextField?
        /// The fill, or `nil` for none.
        var fillColor: NSColor? { didSet { applyLayerColors() } }
        /// The border color, or `nil` for no border. Often a dynamic
        /// system color, so it is re-resolved on every appearance change.
        var strokeColor: NSColor? { didSet { applyLayerColors() } }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyLayerColors()
        }

        /// Resolves the colors against this view's appearance into the
        /// layer, which only holds static `CGColor`s.
        func applyLayerColors() {
            guard let layer else { return }
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = fillColor?.cgColor
                layer.borderColor = strokeColor?.cgColor
            }
        }
    }

    /// An interactive node with no descriptor or region: takes focus when
    /// focusable and forwards keys to the host. Also the clickable container
    /// for a button whose label is not plain text.
    final class NativeFocusGroup: NativeFlippedView {
        var isFocusable = false
        var isClickable = false

        override var acceptsFirstResponder: Bool { isFocusable }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted, let nodeID { nativeHost?.controlDidTakeFocus(nodeID) }
            return accepted
        }

        override func keyDown(with event: NSEvent) {
            guard let key = AppKitKeyTranslation.key(from: event) else {
                super.keyDown(with: event)
                return
            }
            nativeHost?.send(.key(key))
        }

        override func mouseUp(with event: NSEvent) {
            guard isClickable, let nodeID else {
                super.mouseUp(with: event)
                return
            }
            nativeHost?.controlDidActivate(nodeID)
        }

        override func accessibilityRole() -> NSAccessibility.Role? {
            isClickable ? .button : .group
        }

        override func isAccessibilityElement() -> Bool { isClickable || isFocusable }

        override func accessibilityPerformPress() -> Bool {
            guard isClickable, let nodeID else { return false }
            nativeHost?.controlDidActivate(nodeID)
            return true
        }
    }

    /// A native region (ADR 0016). It presents the region's fallback
    /// children; the host hides it while an application view is attached.
    final class NativeRegionContainer: NativeFlippedView {}

    /// Builds and updates the AppKit view for one presented kind.
    @MainActor
    enum NativeControlMapping {
        /// A new view for `kind`, configured for `style`.
        static func makeView(
            for kind: PresentedKind, style: TextStyle, id: PresentationID,
            host: GamaNativeHostView, metrics: AppKitLayoutMetrics
        ) -> any NSView & NativePresentedView {
            let view: any NSView & NativePresentedView
            switch kind {
            case .label:
                let label = NativeLabel(wrappingLabelWithString: "")
                label.isSelectable = false
                view = label
            case .separator:
                let box = NativeSeparator()
                box.boxType = .separator
                view = box
            case .container:
                let container = NativeContainer()
                container.wantsLayer = true
                view = container
            case .control(let descriptor):
                switch descriptor {
                case .button(let title, _):
                    if title == nil {
                        let group = NativeFocusGroup()
                        group.isClickable = true
                        group.isFocusable = true
                        view = group
                    } else {
                        let button = NativeButton(title: "", target: host, action: #selector(GamaNativeHostView.nativeControlFired(_:)))
                        button.bezelStyle = .push
                        view = button
                    }
                case .toggle:
                    view = NativeButton(checkboxWithTitle: "", target: host, action: #selector(GamaNativeHostView.nativeControlFired(_:)))
                case .textField:
                    let field = NativeTextField(string: "")
                    field.isEditable = true
                    field.isBezeled = true
                    field.bezelStyle = .squareBezel
                    field.delegate = host
                    field.usesSingleLineMode = true
                    field.cell?.isScrollable = true
                    view = field
                case .progress:
                    view = NativeProgress()
                }
            case .nativeRegion:
                view = NativeRegionContainer()
            case .focusGroup:
                view = NativeFocusGroup()
            }
            view.presentationID = id
            view.nativeHost = host
            update(view, to: kind, style: style, metrics: metrics)
            return view
        }

        /// Reconfigures `view` in place for `kind` and `style`. The diff only
        /// updates a view with a kind of the same view class.
        static func update(_ view: NSView, to kind: PresentedKind, style: TextStyle, metrics: AppKitLayoutMetrics) {
            switch kind {
            case .label(let text):
                guard let label = view as? NativeLabel else { return }
                if label.stringValue != text { label.stringValue = text }
                label.font = metrics.font(for: style.attributes)
                label.textColor = color(style.foreground, fallback: .labelColor)
                if style.attributes.contains(.dim) {
                    label.textColor = color(style.foreground, fallback: .secondaryLabelColor)
                }
                label.drawsBackground = !style.background.isDefault
                if !style.background.isDefault { label.backgroundColor = color(style.background, fallback: .clear) }
            case .separator:
                break
            case .container(let background, let border, let title):
                guard let container = view as? NativeContainer, let layer = container.layer else { return }
                container.fillColor = background.isDefault ? nil : color(background, fallback: .clear)
                if let border {
                    layer.borderWidth = 1
                    container.strokeColor = color(style.foreground, fallback: .separatorColor)
                    layer.cornerRadius = border == .rounded ? 6 : 0
                } else {
                    layer.borderWidth = 0
                    container.strokeColor = nil
                    layer.cornerRadius = 0
                }
                updateTitle(of: container, title: title, style: style, metrics: metrics)
            case .control(let descriptor):
                updateControl(view, descriptor: descriptor, style: style)
            case .nativeRegion:
                break
            case .focusGroup(let focusable):
                (view as? NativeFocusGroup)?.isFocusable = focusable
            }
        }

        private static func updateControl(_ view: NSView, descriptor: ControlDescriptor, style: TextStyle) {
            switch descriptor {
            case .button(let title, let isEnabled):
                if let button = view as? NativeButton {
                    if button.title != (title ?? "") { button.title = title ?? "" }
                    button.isEnabled = isEnabled
                } else if let group = view as? NativeFocusGroup {
                    group.isFocusable = isEnabled
                    group.isClickable = isEnabled
                }
            case .toggle(let title, let isOn, let isEnabled):
                guard let button = view as? NativeButton else { return }
                if button.title != title { button.title = title }
                button.state = isOn ? .on : .off
                button.isEnabled = isEnabled
            case .textField(let placeholder, let text, let isEnabled, _):
                guard let field = view as? NativeTextField else { return }
                if field.placeholderString != placeholder { field.placeholderString = placeholder }
                // Only a real change is written back, so a binding echoing
                // the field's own edit never moves the caret.
                if field.stringValue != text { field.stringValue = text }
                field.isEnabled = isEnabled
            case .progress(let fraction, let label):
                guard let indicator = view as? NativeProgress else { return }
                if let fraction {
                    indicator.style = .bar
                    indicator.isIndeterminate = false
                    indicator.minValue = 0
                    indicator.maxValue = 1
                    indicator.doubleValue = fraction
                } else {
                    indicator.style = .spinning
                    indicator.isIndeterminate = true
                    indicator.startAnimation(nil)
                }
                indicator.setAccessibilityLabel(label)
            }
        }

        private static func updateTitle(
            of container: NativeContainer, title: String?, style: TextStyle, metrics: AppKitLayoutMetrics
        ) {
            guard let title, !title.isEmpty else {
                container.titleLabel?.removeFromSuperview()
                container.titleLabel = nil
                container.setAccessibilityLabel(nil)
                return
            }
            let label = container.titleLabel ?? NSTextField(labelWithString: "")
            if container.titleLabel == nil {
                container.titleLabel = label
                container.addSubview(label)
            }
            label.stringValue = title
            label.font = metrics.font(for: [.bold])
            label.textColor = color(style.foreground, fallback: .secondaryLabelColor)
            let width = CGFloat(metrics.textSize(title, style: TextStyle(attributes: [.bold]), width: nil).width)
            label.frame = CGRect(x: metrics.cellSize.width, y: 0, width: width + 4, height: metrics.cellSize.height)
            container.setAccessibilityLabel(title)
        }

        /// The fixed AppKit color for an explicit Gama color, or `fallback`
        /// (a dynamic system color) for the default color.
        static func color(_ color: Color, fallback: NSColor) -> NSColor {
            color.isDefault
                ? fallback
                : NSColor(
                    srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                    blue: CGFloat(color.b) / 255, alpha: 1)
        }
    }

    /// Translates an AppKit key event into a Gama `Key`. The one table both
    /// AppKit hosts use: `GamaHostView` and `GamaNativeHostView`.
    enum AppKitKeyTranslation {
        @MainActor
        static func key(from event: NSEvent) -> Key? {
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
            guard let chars = event.charactersIgnoringModifiers, let ch = chars.first else { return nil }
            if event.modifierFlags.contains(.control), ch.isLetter {
                return .ctrl(Character(ch.lowercased()))
            }
            return .character(ch)
        }
    }

#endif  // canImport(AppKit)
