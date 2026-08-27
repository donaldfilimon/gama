//  RenderNode.swift — GamaCore
//  The framework's IR. Views compile down to this pure value tree in the
//  build pass; layout annotates it with frames; backends (TUI, GUI, MLIR)
//  consume it. Indirect enum = no classes, no existentials → Embedded-safe.

/// How a node competes for main-axis space inside a stack: the layout
/// pass measures `fixed` children first, then divides the leftover
/// among `flexible` children in proportion to their weights.
public enum FlexPriority: Hashable, Sendable {
    /// Fixed content size (Text, fixed Frame).
    case fixed
    /// Absorbs leftover space with the given weight (Spacer, flexible Frame).
    case flexible(weight: Int)
}

/// Stable identity for event routing (buttons/focus). Derived from tree
/// path so it survives rebuilds without allocation-heavy ID schemes.
public struct NodeID: Hashable, Sendable {
    /// The mixed 64-bit path hash; the same tree position always hashes
    /// to the same value, which is what makes ids rebuild-stable.
    public var raw: UInt64
    /// Wraps a precomputed hash. Ids are normally derived from `root`
    /// via `child(_:)` rather than constructed from raw values.
    public init(raw: UInt64) { self.raw = raw }

    /// Derives the id of the child at `index` by mixing the index into
    /// this id — pure arithmetic, so identical tree paths yield
    /// identical ids on every rebuild.
    public func child(_ index: Int) -> NodeID {
        // FNV-1a style mix — deterministic, no Foundation.
        var h = raw ^ 0x9E37_79B9_7F4A_7C15
        h = h &* 0x100_0000_01B3
        h ^= UInt64(truncatingIfNeeded: index) &+ 0x517C_C1B7_2722_0A95
        return NodeID(raw: h)
    }

    /// The well-known id of the tree root; every other id descends from
    /// it through `child(_:)`.
    public static let root = NodeID(raw: 0xCBF2_9CE4_8422_2325)
}

/// One node of the render tree — the value IR the build pass emits,
/// `LayoutEngine` measures and places, and every backend paints.
/// Wrapper cases (`padding` through `interactive`) carry exactly one
/// child; `stack` and `overlay` carry ordered children.
public indirect enum RenderNode: Hashable, Sendable {
    /// Nothing: measures to `.zero` and paints no cells.
    case empty
    /// One run of text in one style; the style merges over whatever the
    /// tree above it established.
    case text(String, style: TextStyle)
    /// Children placed sequentially along `axis`, `spacing` cells
    /// apart, aligned on the cross axis.
    case stack(axis: Axis, spacing: Int, alignment: Alignment, children: [RenderNode])
    /// Children sharing the same bounds, each placed by `alignment` and
    /// painted in order (later entries over earlier) — the `ZStack`
    /// lowering.
    case overlay(alignment: Alignment, children: [RenderNode])  // ZStack
    /// ViewBuilder / ForEach flatten sentinel. Containers unpack this via
    /// `flattenChildren`; it is not a ``ZStack`` — `overlay` is never used
    /// as a sentinel.
    case group(children: [RenderNode])
    /// Flexible blank space, at least `minLength` cells on the stack's
    /// main axis; absorbs leftover space with weight 1.
    case spacer(minLength: Int)
    /// Axis-resolved rule: 1 cell on the enclosing stack's main axis,
    /// full length on the cross axis. Backends pick the glyph by aspect.
    case divider(style: TextStyle)
    /// Insets the child by the given edges; the child lays out in the
    /// carved-down bounds (`Rect.inset(by:)`).
    case padding(EdgeInsets, child: RenderNode)
    /// A one-cell box of `BorderStyle` glyphs around the child, with an
    /// optional title in the top edge; the child is inset by one cell
    /// on every side.
    case border(BorderStyle, style: TextStyle, title: String?, child: RenderNode)
    /// Fills the child's whole frame with the color before the child
    /// paints; adds nothing to the child's measured size.
    case background(Color, child: RenderNode)
    /// Pins the given axes to exact cell counts (`nil` leaves an axis
    /// to the child) and aligns the child inside the fixed bounds.
    case frame(width: Int?, height: Int?, alignment: Alignment, child: RenderNode)
    /// Range-constrained frame: each axis is clamped between its
    /// min/max, and a `.max` bound turns the node flexible (see
    /// `flexPriority`).
    case flexFrame(
        minWidth: Int?, maxWidth: Int?, minHeight: Int?, maxHeight: Int?,
        alignment: Alignment, child: RenderNode
    )
    /// Cascades the style over the child subtree with `merging(_:)`
    /// semantics — non-default fields win, attributes accumulate; a
    /// non-default background is filled across the whole region.
    case styled(TextStyle, child: RenderNode)
    /// Interactive region: backends route key/pointer events by `id`.
    case interactive(id: NodeID, focusable: Bool, child: RenderNode)

    /// How this node competes for stack space. Single-child wrappers
    /// are transparent and report their child's priority; a `flexFrame`
    /// is flexible only when an axis is unbounded (`.max`); everything
    /// else is fixed.
    public var flexPriority: FlexPriority {
        switch self {
        case .spacer: return .flexible(weight: 1)
        case .flexFrame(_, let maxW, _, let maxH, _, _):
            return (maxW == .max || maxH == .max) ? .flexible(weight: 1) : .fixed
        case .padding(_, let c), .border(_, _, _, let c), .background(_, let c),
             .styled(_, let c), .interactive(_, _, let c):
            return c.flexPriority
        // Exhaustive on purpose: a new case must choose its flex behavior
        // here instead of silently inheriting `.fixed`.
        case .empty, .text, .stack, .overlay, .group, .divider, .frame:
            return .fixed
        }
    }
}

/// Layout output: the same tree shape, annotated with absolute frames.
public struct LaidOutNode: Hashable, Sendable {
    /// The IR node this entry annotates; painters switch on it to
    /// decide what to draw at `frame`.
    public var node: RenderNode
    /// Absolute bounds in cell space — placement resolves every frame
    /// against the root bounds, not the parent's origin.
    public var frame: Rect
    /// Laid-out subtrees, in the same order as the node's own children.
    public var children: [LaidOutNode]
    /// Assembles an annotated node; `LayoutEngine.layout(_:in:)` is the
    /// normal producer.
    public init(node: RenderNode, frame: Rect, children: [LaidOutNode] = []) {
        self.node = node
        self.frame = frame
        self.children = children
    }

    /// Depth-first visit of interactive nodes in visual order.
    public func collectInteractive(into out: inout [InteractiveRegion]) {
        if case .interactive(let id, let focusable, _) = node {
            out.append(InteractiveRegion(id: id, frame: frame, isFocusable: focusable))
        }
        for c in children { c.collectInteractive(into: &out) }
    }
}

/// One interactive node of a laid-out frame: the hit-test/focus record
/// produced by ``LaidOutNode/collectInteractive(into:)``.
public struct InteractiveRegion: Hashable, Sendable {
    /// The stable identity backends route key and pointer events by.
    public let id: NodeID
    /// The node's absolute frame in grid cells.
    public let frame: Rect
    /// Whether the node participates in keyboard focus order.
    public let isFocusable: Bool

    /// Creates a region record.
    public init(id: NodeID, frame: Rect, isFocusable: Bool) {
        self.id = id
        self.frame = frame
        self.isFocusable = isFocusable
    }
}

