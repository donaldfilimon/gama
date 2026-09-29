#if canImport(AppKit)
    import AppKit
    import GamaAppleUI
    import GamaCore
    import Testing

    @Suite("AppKit layout metrics")
    @MainActor
    struct AppKitLayoutMetricsTests {
        @Test("the cell probe is positive and matches the system font")
        func cellProbe() {
            let measurer = AppKitLayoutMetrics()
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let probe = NSAttributedString(string: "M", attributes: [.font: font]).size()
            #expect(measurer.cellSize.width > 0 && measurer.cellSize.height > 0)
            #expect(measurer.cellSize.width == probe.width.rounded(.up))
            #expect(measurer.cellSize.height == probe.height.rounded(.up))
            let metrics = measurer.metrics
            #expect(metrics.units(3, .horizontal) == 3 * Int(measurer.cellSize.width))
            #expect(metrics.units(2, .vertical) == 2 * Int(measurer.cellSize.height))
        }

        @Test("text is proportional: iiii is narrower than WWWW")
        func proportional() {
            let metrics = AppKitLayoutMetrics().metrics
            let narrow = metrics.textSize("iiii", .plain, nil)
            let wide = metrics.textSize("WWWW", .plain, nil)
            #expect(narrow.width > 0)
            #expect(narrow.width < wide.width)
            #expect(narrow.height == wide.height)
        }

        @Test("wrapping at a maximum width increases height")
        func wraps() {
            let metrics = AppKitLayoutMetrics().metrics
            let text = "The quick brown fox jumps over the lazy dog again and again"
            let unwrapped = metrics.textSize(text, .plain, nil)
            let wrapped = metrics.textSize(text, .plain, 80)
            #expect(wrapped.height > unwrapped.height)
            #expect(wrapped.width <= 80)
        }

        @Test("results round AppKit's measurement up to whole points")
        func roundsUp() {
            let measurer = AppKitLayoutMetrics()
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let raw = NSAttributedString(string: "Gama", attributes: [.font: font])
                .boundingRect(
                    with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
            let size = measurer.metrics.textSize("Gama", .plain, nil)
            // The label cell's line-fragment padding is part of the width.
            #expect(CGFloat(size.width) == (raw.width + AppKitLayoutMetrics.labelPadding).rounded(.up))
            #expect(CGFloat(size.height) == raw.height.rounded(.up))
        }

        @Test("a label given its measured size shows its whole text on one line")
        func labelFits() {
            let measurer = AppKitLayoutMetrics()
            for text in ["Gama", "Native presentation", "Proportional system text measured by AppKit.", "W"] {
                for style in [TextStyle.plain, TextStyle(attributes: [.bold])] {
                    let size = measurer.metrics.textSize(text, style, nil)
                    let label = NSTextField(wrappingLabelWithString: text)
                    label.font = measurer.font(for: style.attributes)
                    let fitting = label.fittingSize
                    #expect(fitting.width <= CGFloat(size.width), "\(text) is clipped")
                    #expect(fitting.height <= CGFloat(size.height), "\(text) wraps")
                }
            }
        }

        @Test("bold text measures wider than plain text")
        func bold() {
            let metrics = AppKitLayoutMetrics().metrics
            let plain = metrics.textSize("Measure me", .plain, nil)
            let bold = metrics.textSize("Measure me", TextStyle(attributes: [.bold]), nil)
            #expect(bold.width > plain.width)
        }

        @Test("the cache returns identical values without measuring again")
        func cache() {
            let measurer = AppKitLayoutMetrics()
            let metrics = measurer.metrics
            let first = metrics.textSize("cached", .plain, 200)
            let count = measurer.textMeasurementCount
            let second = metrics.textSize("cached", .plain, 200)
            #expect(first == second)
            #expect(measurer.textMeasurementCount == count)
            _ = metrics.textSize("cached", .plain, 100)
            #expect(measurer.textMeasurementCount == count + 1)
        }

        @Test("control sizes are positive for every mapped control")
        func controlSizes() throws {
            let metrics = AppKitLayoutMetrics().metrics
            let proposal = ProposedSize(width: nil, height: nil)
            let descriptors: [ControlDescriptor] = [
                .button(title: "Push", isEnabled: true),
                .toggle(title: "Check", isOn: true, isEnabled: true),
                .textField(placeholder: "Name", text: "", isEnabled: true, setText: { _ in }),
                .progress(fraction: 0.5, label: nil),
            ]
            for descriptor in descriptors {
                let size = try #require(metrics.descriptorSize(descriptor, proposal))
                #expect(size.width > 0 && size.height > 0)
            }
            // A composite button label measures its own children.
            #expect(metrics.descriptorSize(.button(title: nil, isEnabled: true), proposal) == nil)
        }

        @Test("text AppKit cannot measure falls back to cell metrics scaled by the cell size")
        func fallback() {
            let measurer = AppKitLayoutMetrics()
            let empty = measurer.metrics.textSize("", .plain, nil)
            let cells = LayoutMetrics.cell.textSize("", .plain, nil)
            #expect(empty.width == cells.width * Int(measurer.cellSize.width))
            #expect(empty.height == cells.height * Int(measurer.cellSize.height))
        }
    }
    @Suite("AppKit native host")
    @MainActor
    struct AppleNativeHostTests {
        private struct FormApp: App {
            let title = Signal("Push")
            let name = Signal("")
            let flag = Signal(false)
            let clicks = Signal(0)
            var scenes: some Scene {
                Window("Form", id: "main", role: .primary) {
                    VStack(spacing: 1) {
                        Text("Heading")
                        TextField("Name", text: name.binding())
                        Button(title.get()) { clicks.update { $0 += 1 } }
                        Toggle("Flag", isOn: flag.binding())
                        ProgressView(value: 0.5)
                        Divider()
                        Text("Styled").foregroundColor(.red)
                    }
                }
            }
        }

        private func installed<A: App>(_ app: A) throws -> GamaNativeHostView {
            _ = NSApplication.shared
            let view = GamaNativeHostView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
            try view.install(app: app)
            view.layoutSubtreeIfNeeded()
            view.invalidate()
            return view
        }

        /// Every presented node, depth first.
        private func flatten(_ nodes: [PresentedNode]) -> [PresentedNode] {
            nodes.flatMap { [$0] + flatten($0.children) }
        }

        private func node(
            in host: GamaNativeHostView, where match: (PresentedKind) -> Bool
        ) throws -> PresentedNode {
            try #require(flatten(host.presentedTree).first { match($0.kind) })
        }

        private func view<T: NSView>(
            _ type: T.Type, in host: GamaNativeHostView, where match: (PresentedKind) -> Bool
        ) throws -> T {
            let found = try node(in: host, where: match)
            return try #require(host.presentedView(for: found.id) as? T)
        }

        private func frame(_ rect: Rect) -> CGRect {
            CGRect(x: rect.minX, y: rect.minY, width: rect.size.width, height: rect.size.height)
        }

        private static func isButton(_ kind: PresentedKind) -> Bool {
            if case .control(.button) = kind { return true }
            return false
        }
        private static func isToggle(_ kind: PresentedKind) -> Bool {
            if case .control(.toggle) = kind { return true }
            return false
        }
        private static func isField(_ kind: PresentedKind) -> Bool {
            if case .control(.textField) = kind { return true }
            return false
        }
        private static func isProgress(_ kind: PresentedKind) -> Bool {
            if case .control(.progress) = kind { return true }
            return false
        }
        private static func isLabel(_ text: String) -> (PresentedKind) -> Bool {
            { kind in
                if case .label(let value) = kind { return value == text }
                return false
            }
        }

        @Test("each control kind is the mapped AppKit class at its computed frame")
        func mapping() throws {
            let host = try installed(FormApp())
            #expect(host.isFlipped)
            let pairs: [((PresentedKind) -> Bool, NSView.Type)] = [
                (Self.isButton, NSButton.self),
                (Self.isToggle, NSButton.self),
                (Self.isField, NSTextField.self),
                (Self.isProgress, NSProgressIndicator.self),
                (Self.isLabel("Heading"), NSTextField.self),
                ({ if case .separator = $0 { return true } else { return false } }, NSBox.self),
            ]
            for (match, expected) in pairs {
                let found = try node(in: host, where: match)
                let view = try #require(host.presentedView(for: found.id))
                #expect(view.isKind(of: expected))
                #expect(view.frame == frame(found.frame))
                #expect(view.frame.width > 0 && view.frame.height > 0)
            }
            let button = try view(NSButton.self, in: host, where: Self.isButton)
            #expect(button.title == "Push")
            let toggle = try view(NSButton.self, in: host, where: Self.isToggle)
            #expect(toggle.title == "Flag")
            let field = try view(NSTextField.self, in: host, where: Self.isField)
            #expect(field.isEditable)
            #expect(field.placeholderString == "Name")
            let label = try view(NSTextField.self, in: host, where: Self.isLabel("Heading"))
            #expect(!label.isEditable)
            #expect(!label.isBezeled)
        }

        @Test("performClick on a button runs the node's action")
        func click() throws {
            let app = FormApp()
            let host = try installed(app)
            let button = try view(NSButton.self, in: host, where: Self.isButton)
            button.performClick(nil)
            #expect(app.clicks.get() == 1)
        }

        @Test("editing a field writes its binding")
        func typing() throws {
            let app = FormApp()
            let host = try installed(app)
            let field = try view(NSTextField.self, in: host, where: Self.isField)
            field.stringValue = "Ada"
            field.delegate?.controlTextDidChange?(
                Notification(name: NSControl.textDidChangeNotification, object: field))
            #expect(app.name.get() == "Ada")
            #expect(field.stringValue == "Ada")
        }

        @Test("a checkbox flips its binding")
        func toggle() throws {
            let app = FormApp()
            let host = try installed(app)
            let checkbox = try view(NSButton.self, in: host, where: Self.isToggle)
            #expect(checkbox.state == .off)
            checkbox.performClick(nil)
            #expect(app.flag.get() == true)
            let after = try view(NSButton.self, in: host, where: Self.isToggle)
            #expect(after === checkbox)
            #expect(after.state == .on)
        }

        @Test("nextKeyView follows Gama focus order")
        func tabOrder() throws {
            let host = try installed(FormApp())
            let field = try view(NSTextField.self, in: host, where: Self.isField)
            let button = try view(NSButton.self, in: host, where: Self.isButton)
            let checkbox = try view(NSButton.self, in: host, where: Self.isToggle)
            #expect(field.nextKeyView === button)
            #expect(button.nextKeyView === checkbox)
            #expect(checkbox.nextKeyView === field)
        }

        private struct TwoFieldApp: App {
            let first = Signal("")
            let second = Signal("")
            var scenes: some Scene {
                Window("Fields", id: "main", role: .primary) {
                    VStack {
                        TextField("First", text: first.binding())
                        TextField("Second", text: second.binding())
                    }
                }
            }
        }

        private static func isField(_ placeholder: String) -> (PresentedKind) -> Bool {
            { kind in
                if case .control(.textField(let value, _, _, _)) = kind { return value == placeholder }
                return false
            }
        }

        /// Whether `field` or its field editor is the window's first responder.
        private func isEditing(_ field: NSTextField, in window: NSWindow) -> Bool {
            window.firstResponder === field || field.currentEditor() != nil
                && window.firstResponder === field.currentEditor()
        }

        @Test("Gama focus changes move first responder and native focus reports back")
        func focus() throws {
            let host = try installed(TwoFieldApp())
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = host
            let first = try view(NSTextField.self, in: host, where: Self.isField("First"))
            let second = try view(NSTextField.self, in: host, where: Self.isField("Second"))
            let firstNode = try node(in: host, where: Self.isField("First"))
            let secondNode = try node(in: host, where: Self.isField("Second"))

            // Gama focuses the first focusable node; the host mirrors it.
            #expect(host.focusedID.map(PresentationID.node) == firstNode.id)
            #expect(isEditing(first, in: window))

            // Gama moves focus: first responder follows.
            host.send(.key(.tab))
            #expect(host.focusedID.map(PresentationID.node) == secondNode.id)
            #expect(isEditing(second, in: window))

            // A native focus change is reported back to FrameHost.
            #expect(window.makeFirstResponder(first))
            #expect(host.focusedID.map(PresentationID.node) == firstNode.id)
            #expect(isEditing(first, in: window))
        }

        @Test("accessibility roles are button, checkbox, text field and static text")
        func accessibility() throws {
            let host = try installed(FormApp())
            let button = try view(NSButton.self, in: host, where: Self.isButton)
            let checkbox = try view(NSButton.self, in: host, where: Self.isToggle)
            let field = try view(NSTextField.self, in: host, where: Self.isField)
            let label = try view(NSTextField.self, in: host, where: Self.isLabel("Heading"))
            // An AppKit control exposes itself to accessibility through its
            // cell; the control view reports an unknown role.
            #expect(button.cell?.accessibilityRole() == .button)
            #expect(checkbox.cell?.accessibilityRole() == .checkBox)
            #expect(field.cell?.accessibilityRole() == .textField)
            #expect(label.cell?.accessibilityRole() == .staticText)
        }

        @Test("labels use labelColor by default and resolve under aqua and darkAqua")
        func appearance() throws {
            let host = try installed(FormApp())
            let label = try view(NSTextField.self, in: host, where: Self.isLabel("Heading"))
            #expect(label.textColor == NSColor.labelColor)
            func resolved(_ name: NSAppearance.Name) -> NSColor? {
                var color: NSColor?
                NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                    color = label.textColor?.usingColorSpace(.sRGB)
                }
                return color
            }
            let light = try #require(resolved(.aqua))
            let dark = try #require(resolved(.darkAqua))
            #expect(light != dark)
            let styled = try view(NSTextField.self, in: host, where: Self.isLabel("Styled"))
            #expect(styled.textColor != NSColor.labelColor)
        }

        @Test("a changed title updates the control in place")
        func updateInPlace() throws {
            let app = FormApp()
            let host = try installed(app)
            let button = try view(NSButton.self, in: host, where: Self.isButton)
            app.title.set("Pushed")
            host.invalidate()
            let after = try view(NSButton.self, in: host, where: Self.isButton)
            #expect(after === button)
            #expect(after.title == "Pushed")
        }

        @Test("the surface is laid out in points, not cells")
        func points() throws {
            let host = try installed(FormApp())
            let heading = try node(in: host, where: Self.isLabel("Heading"))
            // A point-measured label is far wider than its seven-cell count.
            #expect(heading.frame.size.width > 7)
            #expect(heading.frame.size.height >= Int(host.layoutMetrics.cellSize.height) - 4)
        }
    }
    @Suite("AppKit native host regions")
    @MainActor
    struct AppleNativeHostRegionTests {
        private struct ViewportApp: App {
            let show = Signal(true)
            var scenes: some Scene {
                Window("Studio", id: "main", role: .primary) {
                    VStack {
                        Button("Panel") {}
                        NativeRegion(NativeRegionID("viewport")) { Text("3D viewport") }
                            .frame(width: show.get() ? 20 : 0, height: show.get() ? 5 : 0)
                    }
                }
            }
        }

        private final class FocusableView: NSView {
            override var acceptsFirstResponder: Bool { true }
        }

        private func installed(_ app: ViewportApp) throws -> GamaNativeHostView {
            _ = NSApplication.shared
            let view = GamaNativeHostView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
            try view.install(app: app)
            view.layoutSubtreeIfNeeded()
            view.invalidate()
            return view
        }

        private func region(in host: GamaNativeHostView) throws -> NativeRegionFrame {
            try #require(host.nativeRegions.first { $0.id == NativeRegionID("viewport") })
        }

        private func fallbackLabel(in host: GamaNativeHostView) -> PresentedNode? {
            func flatten(_ nodes: [PresentedNode]) -> [PresentedNode] {
                nodes.flatMap { [$0] + flatten($0.children) }
            }
            return flatten(host.presentedTree).first {
                if case .label("3D viewport") = $0.kind { return true }
                return false
            }
        }

        @Test("an attached view is placed on the region's point frame and hides the fallback")
        func placed() throws {
            let host = try installed(ViewportApp())
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            let region = try region(in: host)
            #expect(native.superview === host)
            #expect(native.isHidden == false)
            #expect(
                native.frame
                    == CGRect(
                        x: region.frame.minX, y: region.frame.minY,
                        width: region.frame.size.width, height: region.frame.size.height))
            // Points, not cells: twenty cells are wider than twenty points.
            #expect(native.frame.width > 20)
            let fallback = try #require(host.presentedView(for: .node(region.node)))
            #expect(fallback.isHidden)
        }

        @Test("detaching removes the view and shows the fallback presented natively")
        func detach() throws {
            let host = try installed(ViewportApp())
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            host.detach(NativeRegionID("viewport"))
            #expect(native.superview == nil)
            let region = try region(in: host)
            let fallback = try #require(host.presentedView(for: .node(region.node)))
            #expect(!fallback.isHidden)
            let label = try #require(fallbackLabel(in: host))
            let labelView = try #require(host.presentedView(for: label.id) as? NSTextField)
            #expect(labelView.isDescendant(of: fallback))
            #expect(labelView.stringValue == "3D viewport")
        }

        @Test("the view hides when its region goes away and stays attached")
        func hidesWhenAbsent() throws {
            let app = ViewportApp()
            let host = try installed(app)
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            app.show.set(false)
            host.invalidate()
            #expect(native.isHidden)
            #expect(native.superview === host)
        }

        @Test("Gama focus on the region hands first responder to the attached view")
        func focusHandoff() throws {
            let host = try installed(ViewportApp())
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = host
            let native = FocusableView()
            host.attach(native, to: NativeRegionID("viewport"))
            host.send(.key(.tab))  // button → region
            #expect(window.firstResponder === native)
            host.send(.key(.tab))  // region → button: the attached view gives it up
            #expect(window.firstResponder !== native)
        }
    }
#endif
