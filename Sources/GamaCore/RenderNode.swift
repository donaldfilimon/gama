//  RenderNode.swift — GamaCore
//  The framework's IR. Views compile down to this pure value tree in the
//  build pass; layout annotates it with frames; backends (TUI, GUI, MLIR)
//  consume it. Indirect enum = no classes, no existentials → Embedded-safe.

public enum FlexPriority: Hashable, Sendable {
    /// Fixed content size (Text, fixed Frame).
    case fixed
    /// Absorbs leftover space with the given weight (Spacer, flexible Frame).
    case flexible(weight: Int)
}

/// Stable identity for event routing (buttons/focus). Derived from tree
/// path so it survives rebuilds without allocation-heavy ID schemes.
public struct NodeID: Hashable, Sendable {
    public var raw: UInt64
    public init(raw: UInt64) { self.raw = raw }

    public func child(_ index: Int) -> NodeID {
        // FNV-1a style mix — deterministic, no Foundation.
        var h = raw ^ 0x9E37_79B9_7F4A_7C15
        h = h &* 0x100_0000_01B3
        h ^= UInt64(truncatingIfNeeded: index) &+ 0x517C_C1B7_2722_0A95
        return NodeID(raw: h)
    }

    public static let root = NodeID(raw: 0xCBF2_9CE4_8422_2325)
}

public indirect enum RenderNode: Hashable, Sendable {
    case empty
    case text(String, style: TextStyle)
    case stack(axis: Axis, spacing: Int, alignment: Alignment, children: [RenderNode])
    /// Layered children of a ``ZStack``. Never used as a flatten sentinel.
    case overlay(alignment: Alignment, children: [RenderNode])
    /// ViewBuilder / ForEach flatten sentinel. Containers unpack this via
    /// `flattenChildren`; it is not a ``ZStack``.
    case group(children: [RenderNode])
    case spacer(minLength: Int)
    /// Axis-resolved rule: 1 cell on the enclosing stack's main axis,
    /// full length on the cross axis. Backends pick the glyph by aspect.
    case divider(style: TextStyle)
    case padding(EdgeInsets, child: RenderNode)
    case border(BorderStyle, style: TextStyle, title: String?, child: RenderNode)
    case background(Color, child: RenderNode)
    case frame(width: Int?, height: Int?, alignment: Alignment, child: RenderNode)
    case flexFrame(
        minWidth: Int?, maxWidth: Int?, minHeight: Int?, maxHeight: Int?,
        alignment: Alignment, child: RenderNode
    )
    case styled(TextStyle, child: RenderNode)
    /// Interactive region: backends route key/pointer events by `id`.
    case interactive(id: NodeID, focusable: Bool, child: RenderNode)

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
    public var node: RenderNode
    public var frame: Rect
    public var children: [LaidOutNode]
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

