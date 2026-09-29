//  NativeHostSession.swift — GamaAppleUI
//  One installed surface of a `GamaNativeHostView`: the frame pump, the
//  previous presentation tree, and the AppKit views keyed by presentation
//  identity. Applies each frame's `PresentationDiff` to those views.

#if canImport(AppKit)

    import AppKit
    import GamaCore

    /// Owns one surface's `HostPump` and its presented views. Non-Sendable
    /// by design: only the `@MainActor` host touches it.
    @MainActor
    final class NativeHostSession {
        var pump: HostPump
        /// The presentation tree the views currently show.
        private(set) var tree: [PresentedNode] = []
        /// Presented views by identity.
        private(set) var views: [PresentationID: any NSView & NativePresentedView] = [:]
        /// Descriptors of the most recent frame, for event write-back.
        private(set) var controls: [NodeID: ControlDescriptor] = [:]
        /// Focusable interactive nodes of the most recent frame, in Gama's
        /// focus order.
        private(set) var focusOrder: [NodeID] = []

        init(surface: SceneSurface, metrics: LayoutMetrics, size: Size) {
            pump = HostPump(host: FrameHost(surface: surface, metrics: metrics), size: size)
        }

        /// Advances the pump once and applies the resulting presentation to
        /// `host`. Returns the pump outcome.
        func advance(into host: GamaNativeHostView, metrics: AppKitLayoutMetrics) -> AdvanceOutcome {
            guard let advanced = pump.advance() else { return .clean }
            controls = pump.controls
            var interactive: [InteractiveRegion] = []
            advanced.frame.collectInteractive(into: &interactive)
            focusOrder = interactive.compactMap { $0.isFocusable ? $0.id : nil }
            let next = PresentedNode.tree(from: advanced.frame, controls: controls, regions: pump.nativeRegions)
            let ops = PresentationDiff.between(tree, next)
            apply(ops, in: host, metrics: metrics)
            reconcileControlValues()
            tree = next
            enforceOrder(of: next, parent: nil, in: host)
            linkKeyViews()
            return AdvanceOutcome(produced: true, followUp: advanced.followUp)
        }

        /// Writes each text field's and checkbox's value from the latest
        /// descriptors into its AppKit control. AppKit changes a control's
        /// value before Gama sees the edit, and the diff compares only
        /// descriptors, so a binding that clamps or refuses an edit would
        /// otherwise leave the control showing a value the model rejected.
        func reconcileControlValues() {
            for (id, descriptor) in controls {
                switch descriptor {
                case .textField(_, let text, _, _):
                    guard let field = views[.node(id)] as? NativeTextField, field.stringValue != text else { continue }
                    field.stringValue = text
                case .toggle(_, let isOn, _):
                    let state: NSControl.StateValue = isOn ? .on : .off
                    guard let checkbox = views[.node(id)] as? NativeButton, checkbox.state != state else { continue }
                    checkbox.state = state
                case .button, .progress:
                    continue
                }
            }
        }

        /// The view presenting `id`, if any.
        func view(for id: PresentationID) -> (any NSView & NativePresentedView)? { views[id] }

        /// Removes every presented view, for a host replacing its session.
        func removeAllViews() {
            for view in views.values { view.removeFromSuperview() }
            views.removeAll()
            tree = []
        }

        private func apply(_ ops: [PresentationOp], in host: GamaNativeHostView, metrics: AppKitLayoutMetrics) {
            for op in ops {
                switch op {
                case .remove(let id):
                    guard let view = views.removeValue(forKey: id) else {
                        assertionFailure("presentation op removes unknown id \(id)")
                        continue
                    }
                    view.removeFromSuperview()
                case .insert(let id, let kind, let style, let parent, _, let frame):
                    guard let container = container(for: parent, in: host) else {
                        assertionFailure("presentation op inserts under unknown parent")
                        continue
                    }
                    let view = NativeControlMapping.makeView(
                        for: kind, style: style, id: id, host: host, metrics: metrics)
                    view.frame = Self.rect(frame)
                    container.addSubview(view)
                    views[id] = view
                case .move(let id, let parent, _):
                    guard let view = views[id], let container = container(for: parent, in: host) else {
                        assertionFailure("presentation op moves unknown id \(id)")
                        continue
                    }
                    if unsafe view.superview !== container {
                        view.removeFromSuperview()
                        container.addSubview(view)
                    }
                case .setFrame(let id, let frame):
                    guard let view = views[id] else {
                        assertionFailure("presentation op frames unknown id \(id)")
                        continue
                    }
                    view.frame = Self.rect(frame)
                case .update(let id, let kind, let style):
                    guard let view = views[id] else {
                        assertionFailure("presentation op updates unknown id \(id)")
                        continue
                    }
                    NativeControlMapping.update(view, to: kind, style: style, metrics: metrics)
                }
            }
        }

        private func container(for parent: PresentationID?, in host: GamaNativeHostView) -> NSView? {
            guard let parent else { return host }
            return views[parent]
        }

        /// Puts every container's presented children in the tree's paint
        /// order. Views that are not presented (a border title, an attached
        /// native-region view) keep their place: decorations first, then
        /// presented views, then attached views on top.
        private func enforceOrder(of nodes: [PresentedNode], parent: PresentationID?, in host: GamaNativeHostView) {
            guard let container = parent.map({ views[$0] as NSView? }) ?? host else { return }
            let presented = nodes.compactMap { views[$0.id] as NSView? }
            let current = container.subviews
            let presentedSet = Set(presented.map(ObjectIdentifier.init))
            let currentPresented = current.filter { presentedSet.contains(ObjectIdentifier($0)) }
            if currentPresented.map(ObjectIdentifier.init) != presented.map(ObjectIdentifier.init) {
                let others = current.filter { !presentedSet.contains(ObjectIdentifier($0)) }
                let attached = others.filter { host.isAttachedNativeView($0) }
                let decorations = others.filter { !host.isAttachedNativeView($0) }
                // A kept view whose parent was replaced by a new view of the
                // same identity is still inside the old one; take it out
                // before re-parenting it here.
                for view in presented where unsafe view.superview !== container {
                    view.removeFromSuperview()
                }
                container.subviews = decorations + presented + attached
            }
            for node in nodes where !node.children.isEmpty {
                enforceOrder(of: node.children, parent: node.id, in: host)
            }
        }

        /// Chains `nextKeyView` through the presented controls in Gama's
        /// focus order, closing the loop.
        private func linkKeyViews() {
            let ordered = focusOrder.compactMap { views[.node($0)] as NSView? }
            guard !ordered.isEmpty else { return }
            for (index, view) in ordered.enumerated() {
                unsafe view.nextKeyView = ordered[(index + 1) % ordered.count]
            }
        }

        static func rect(_ frame: Rect) -> CGRect {
            CGRect(
                x: CGFloat(frame.minX), y: CGFloat(frame.minY),
                width: CGFloat(frame.size.width), height: CGFloat(frame.size.height))
        }
    }

#endif  // canImport(AppKit)
