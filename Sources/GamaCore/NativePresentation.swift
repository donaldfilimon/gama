//  NativePresentation.swift — GamaCore
//  The portable half of native presentation (ADR 0017): a laid-out frame
//  reduced to the minimal tree of views a native host creates, and the diff
//  between two such trees as an ordered list of operations the host
//  applies. Stdlib-only and tested without any platform framework; hosts
//  map each kind to a platform view and never decide layout.

/// Identity of one presented view, stable across identical rebuilds.
///
/// An interactive node keeps its ``NodeID``, so a text field keeps its
/// platform editor across frames. Every other view is keyed by its path of
/// child indices from the root of the laid-out tree, mixed the way
/// ``NodeID/child(_:)`` mixes them. The two cases never compare equal, so a
/// path cannot collide with a real node identity.
public enum PresentationID: Hashable, Sendable {
    /// An interactive node's own identity.
    case node(NodeID)
    /// The mixed child-index path of a non-interactive view.
    case path(UInt64)
}

/// What a presented view is. A native host maps each case to one platform
/// view class.
///
/// Equality compares every field except closures: two
/// ``ControlDescriptor/textField(placeholder:text:isEnabled:setText:)``
/// descriptors are equal when their placeholder, text, and enabled state
/// match, whatever their `setText` closures are, because a host rebinds the
/// closure from the newest tree on every frame.
public enum PresentedKind: Equatable {
    /// Static text.
    case label(String)
    /// A rule. The payload is the orientation of the line itself: a
    /// divider between the children of a horizontal stack is a
    /// `.vertical` line.
    case separator(Axis)
    /// A plain view grouping its children: a filled background, a border
    /// with an optional title, or both. `background` is ``Color/default``
    /// when the container only draws a border.
    case container(background: Color, border: BorderStyle?, title: String?)
    /// A platform control described by the control's registration.
    case control(ControlDescriptor)
    /// A native region (ADR 0016); the host shows an attached view here and
    /// otherwise presents the fallback children.
    case nativeRegion(NativeRegionID)
    /// An interactive node with no descriptor or region: a generic view
    /// that takes focus when `focusable` and forwards input to the host.
    case focusGroup(focusable: Bool)

    /// Compares every non-closure field.
    public static func == (lhs: PresentedKind, rhs: PresentedKind) -> Bool {
        switch (lhs, rhs) {
        case (.label(let a), .label(let b)): return a == b
        case (.separator(let a), .separator(let b)): return a == b
        case (.container(let a1, let a2, let a3), .container(let b1, let b2, let b3)):
            return a1 == b1 && a2 == b2 && a3 == b3
        case (.control(let a), .control(let b)): return a.presentsSame(as: b)
        case (.nativeRegion(let a), .nativeRegion(let b)): return a == b
        case (.focusGroup(let a), .focusGroup(let b)): return a == b
        default: return false
        }
    }

    /// Whether a host can update a view of kind `self` in place to
    /// `other`, as opposed to replacing it: the same case and, for
    /// controls, the same control kind. A button with a `nil` title (a
    /// composite label the host presents inside a generic view) and a
    /// titled button are different view classes.
    public func isSameViewClass(as other: PresentedKind) -> Bool {
        switch (self, other) {
        case (.label, .label), (.separator, .separator), (.container, .container),
            (.nativeRegion, .nativeRegion), (.focusGroup, .focusGroup):
            return true
        case (.control(let a), .control(let b)):
            return a.controlKindIndex == b.controlKindIndex
        default:
            return false
        }
    }
}

extension ControlDescriptor {
    /// Small integer naming the case, for view-class comparison.
    fileprivate var controlKindIndex: Int {
        switch self {
        case .button(let title, _): return title == nil ? 4 : 0
        case .toggle: return 1
        case .textField: return 2
        case .progress: return 3
        }
    }

    /// Every non-closure field equal.
    fileprivate func presentsSame(as other: ControlDescriptor) -> Bool {
        switch (self, other) {
        case (.button(let t1, let e1), .button(let t2, let e2)):
            return t1 == t2 && e1 == e2
        case (.toggle(let t1, let o1, let e1), .toggle(let t2, let o2, let e2)):
            return t1 == t2 && o1 == o2 && e1 == e2
        case (.textField(let p1, let x1, let e1, _), .textField(let p2, let x2, let e2, _)):
            return p1 == p2 && x1 == x2 && e1 == e2
        case (.progress(let f1, let l1), .progress(let f2, let l2)):
            return f1 == f2 && l1 == l2
        default:
            return false
        }
    }
}

/// One view of a presentation tree.
public struct PresentedNode: Equatable {
    /// Stable identity the diff keys on.
    public var id: PresentationID
    /// Which platform view presents this node.
    public var kind: PresentedKind
    /// Bounds in layout units, relative to the nearest presented ancestor
    /// (or to the laid-out root's origin for a top-level view).
    public var frame: Rect
    /// The text style in effect here, resolved with the same precedence
    /// `CellPainter` uses: for text, enclosing `styled` wrappers win over
    /// the node's own style; for a divider or a border, the node's own
    /// style wins over the enclosing ones.
    public var style: TextStyle
    /// Presented descendants, in paint order.
    public var children: [PresentedNode]

    /// Creates a node.
    public init(
        id: PresentationID, kind: PresentedKind, frame: Rect, style: TextStyle,
        children: [PresentedNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.style = style
        self.children = children
    }

    /// Reduces a laid-out frame to the views a native host creates.
    ///
    /// `text`, `divider`, `background`, `border`, and `interactive` produce
    /// a view; `stack`, `overlay`, `group`, `spacer`, `padding`, `frame`,
    /// `flexFrame`, and `styled` only contribute frames and inherited style;
    /// `empty` produces nothing. An interactive node becomes a
    /// ``PresentedKind/control(_:)`` when `controls` has its identity, else
    /// a ``PresentedKind/nativeRegion(_:)`` when `regions` names it, else a
    /// ``PresentedKind/focusGroup(focusable:)``. A control presents no
    /// children, except a button with a `nil` title, which presents its
    /// label subtree inside itself; for an enabled one, the `styled`
    /// wrapper `Button` puts directly around its label (the cell focus
    /// highlight and bold) is skipped, because the platform draws focus
    /// itself. Returns the top-level views in paint order.
    ///
    /// Identities in the result are unique. When an interactive identity
    /// occurs more than once (``FrameHost/duplicateIDs`` reports it), only
    /// its last occurrence in pre-order is presented, matching the
    /// last-registration-wins rule of the control table; earlier
    /// occurrences are dropped with their subtrees, and so is any
    /// occurrence of another identity inside a dropped subtree.
    public static func tree(
        from laid: LaidOutNode,
        controls: [NodeID: ControlDescriptor],
        regions: [NativeRegionFrame]
    ) -> [PresentedNode] {
        var regionTable: [NodeID: NativeRegionID] = [:]
        for region in regions { regionTable[region.node] = region.id }
        var builder = TreeBuilder(controls: controls, regions: regionTable)
        return deduplicated(builder.present(laid, path: NodeID.root, origin: laid.frame.origin, style: .plain))
    }

    /// `nodes` with every identity kept once: its last occurrence in
    /// pre-order. An earlier occurrence is dropped with its whole subtree.
    static func deduplicated(_ nodes: [PresentedNode]) -> [PresentedNode] {
        var remaining: [PresentationID: Int] = [:]
        count(nodes, into: &remaining)
        guard remaining.values.contains(where: { $0 > 1 }) else { return nodes }
        return keepLast(nodes, remaining: &remaining)
    }

    private static func count(_ nodes: [PresentedNode], into remaining: inout [PresentationID: Int]) {
        for node in nodes {
            remaining[node.id, default: 0] += 1
            count(node.children, into: &remaining)
        }
    }

    /// Keeps each node whose occurrence is the last one left, consuming
    /// one count per visited node (dropped subtrees included).
    private static func keepLast(
        _ nodes: [PresentedNode], remaining: inout [PresentationID: Int]
    ) -> [PresentedNode] {
        var out: [PresentedNode] = []
        for var node in nodes {
            let left = (remaining[node.id] ?? 1) - 1
            remaining[node.id] = left
            guard left == 0 else {
                discard(node.children, remaining: &remaining)
                continue
            }
            node.children = keepLast(node.children, remaining: &remaining)
            out.append(node)
        }
        return out
    }

    private static func discard(_ nodes: [PresentedNode], remaining: inout [PresentationID: Int]) {
        for node in nodes {
            remaining[node.id, default: 1] -= 1
            discard(node.children, remaining: &remaining)
        }
    }
}

/// Recursive reduction state for ``PresentedNode/tree(from:controls:regions:)``.
private struct TreeBuilder {
    let controls: [NodeID: ControlDescriptor]
    let regions: [NodeID: NativeRegionID]

    /// Presents `laid` (at index path `path`) and returns the views it
    /// contributes; frames are made relative to `origin`.
    mutating func present(
        _ laid: LaidOutNode, path: NodeID, origin: Point, style: TextStyle
    ) -> [PresentedNode] {
        let relative = Rect(
            x: laid.frame.minX - origin.x, y: laid.frame.minY - origin.y,
            width: laid.frame.size.width, height: laid.frame.size.height)
        let pathID = PresentationID.path(path.raw)
        switch laid.node {
        case .empty:
            return []
        case .text(let string, let own):
            return [PresentedNode(id: pathID, kind: .label(string), frame: relative, style: own.merging(style))]
        case .divider(let own, let axis):
            let vertical: Bool
            if let axis {
                vertical = axis == .horizontal
            } else {
                vertical = laid.frame.size.height > laid.frame.size.width
            }
            return [
                PresentedNode(
                    id: pathID, kind: .separator(vertical ? .vertical : .horizontal),
                    frame: relative, style: style.merging(own))
            ]
        case .background(let color, _):
            return [
                PresentedNode(
                    id: pathID, kind: .container(background: color, border: nil, title: nil),
                    frame: relative, style: style,
                    children: presentChildren(laid, path: path, origin: laid.frame.origin, style: style))
            ]
        case .border(let border, let own, let title, _):
            return [
                PresentedNode(
                    id: pathID, kind: .container(background: .default, border: border, title: title),
                    frame: relative, style: style.merging(own),
                    children: presentChildren(laid, path: path, origin: laid.frame.origin, style: style))
            ]
        case .styled(let own, _):
            return presentChildren(laid, path: path, origin: origin, style: own.merging(style))
        case .interactive(let id, let focusable, _):
            let kind: PresentedKind
            var presentsChildren = true
            if let descriptor = controls[id] {
                kind = .control(descriptor)
                if case .button(let title, _) = descriptor, title == nil {
                    presentsChildren = true
                } else {
                    presentsChildren = false
                }
            } else if let region = regions[id] {
                kind = .nativeRegion(region)
            } else {
                kind = .focusGroup(focusable: focusable)
            }
            var children: [PresentedNode] = []
            if case .control(.button(title: nil, isEnabled: true)) = kind,
                laid.children.count == 1, case .styled = laid.children[0].node
            {
                // `Button`'s own focus/bold wrapper is cell-only styling.
                children = presentChildren(
                    laid.children[0], path: path.child(0), origin: laid.frame.origin, style: style)
            } else if presentsChildren {
                children = presentChildren(laid, path: path, origin: laid.frame.origin, style: style)
            }
            return [PresentedNode(id: .node(id), kind: kind, frame: relative, style: style, children: children)]
        case .stack, .overlay, .group, .spacer, .padding, .frame, .flexFrame:
            return presentChildren(laid, path: path, origin: origin, style: style)
        }
    }

    mutating func presentChildren(
        _ laid: LaidOutNode, path: NodeID, origin: Point, style: TextStyle
    ) -> [PresentedNode] {
        var out: [PresentedNode] = []
        for (index, child) in laid.children.enumerated() {
            out.append(contentsOf: present(child, path: path.child(index), origin: origin, style: style))
        }
        return out
    }
}

/// One change a native host applies to its views, produced by
/// ``PresentationDiff/between(_:_:)``.
public enum PresentationOp: Equatable {
    /// Create a view of `kind` with `style` at `frame`, as child number
    /// `index` of `parent` (`nil` for the host's own content view).
    case insert(id: PresentationID, kind: PresentedKind, style: TextStyle, parent: PresentationID?, index: Int, frame: Rect)
    /// Update an existing view in place to `kind` and `style`.
    case update(id: PresentationID, kind: PresentedKind, style: TextStyle)
    /// Move an existing view to `frame`.
    case setFrame(id: PresentationID, frame: Rect)
    /// Re-parent or reorder an existing view to child number `index` of
    /// `parent`.
    case move(id: PresentationID, parent: PresentationID?, index: Int)
    /// Remove the view (only that view; its surviving descendants receive
    /// their own `move` or `remove`).
    case remove(id: PresentationID)
}

/// Computes the operations that turn one presentation tree into another.
public enum PresentationDiff {
    /// The ordered operations that turn `old` into `new`.
    ///
    /// The order is deterministic: first a `remove` for every old view,
    /// in old pre-order, whose identity is absent from `new` or whose kind
    /// changed view class (see ``PresentedKind/isSameViewClass(as:)``);
    /// then, walking `new` in pre-order, an `insert` for each view that is
    /// not kept, and for each kept view a `move` when its parent or index
    /// changed, a `setFrame` when its frame changed, and an `update` when
    /// its kind or style changed, in that order. Identical trees produce
    /// no operations.
    ///
    /// Each identity is expected once per tree, as
    /// ``PresentedNode/tree(from:controls:regions:)`` guarantees. A tree
    /// that repeats an identity is first reduced the same way: the last
    /// occurrence in pre-order is kept and earlier ones are dropped with
    /// their subtrees.
    public static func between(_ old: [PresentedNode], _ new: [PresentedNode]) -> [PresentationOp] {
        let old = PresentedNode.deduplicated(old)
        let new = PresentedNode.deduplicated(new)
        var oldIndex: [PresentationID: Placement] = [:]
        var oldOrder: [PresentationID] = []
        index(old, parent: nil, into: &oldIndex, order: &oldOrder)
        var newIndex: [PresentationID: Placement] = [:]
        var newOrder: [PresentationID] = []
        index(new, parent: nil, into: &newIndex, order: &newOrder)

        var ops: [PresentationOp] = []
        var kept: Set<PresentationID> = []
        for id in oldOrder {
            guard let before = oldIndex[id] else { continue }
            if let after = newIndex[id], before.node.kind.isSameViewClass(as: after.node.kind) {
                kept.insert(id)
            } else {
                ops.append(.remove(id: id))
            }
        }
        for id in newOrder {
            guard let after = newIndex[id] else { continue }
            guard kept.contains(id), let before = oldIndex[id] else {
                ops.append(
                    .insert(
                        id: id, kind: after.node.kind, style: after.node.style,
                        parent: after.parent, index: after.index, frame: after.node.frame))
                continue
            }
            if before.parent != after.parent || before.index != after.index {
                ops.append(.move(id: id, parent: after.parent, index: after.index))
            }
            if before.node.frame != after.node.frame {
                ops.append(.setFrame(id: id, frame: after.node.frame))
            }
            if before.node.kind != after.node.kind || before.node.style != after.node.style {
                ops.append(.update(id: id, kind: after.node.kind, style: after.node.style))
            }
        }
        return ops
    }

    /// Where one view sits in its tree.
    private struct Placement {
        var node: PresentedNode
        var parent: PresentationID?
        var index: Int
    }

    private static func index(
        _ nodes: [PresentedNode], parent: PresentationID?,
        into table: inout [PresentationID: Placement], order: inout [PresentationID]
    ) {
        for (position, node) in nodes.enumerated() {
            order.append(node.id)
            table[node.id] = Placement(node: node, parent: parent, index: position)
            index(node.children, parent: node.id, into: &table, order: &order)
        }
    }
}
