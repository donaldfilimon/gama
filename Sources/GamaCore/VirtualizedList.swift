//  VirtualizedList.swift — GamaCore
//  A collection view that builds only the rows the surface could show.
//  `ForEach` and `IdentifiedForEach` compile every element on every build
//  pass, which is correct for a menu and untenable for ten thousand rows.
//  This view keeps their identity discipline — a row renders under
//  `id(element)`, never its position — and adds a scroll offset so the
//  built window follows the viewer instead of the collection.

/// A vertically scrolling list that compiles only the rows its surface can
/// display, plus a host-owned scroll offset the arrow keys move.
///
/// Rows are assumed to be `rowHeight` cells tall (one by default). That
/// uniformity is what makes windowing possible without laying out the
/// whole collection first: the visible range is arithmetic on the offset,
/// not a measurement pass. A list of variably sized rows is a different
/// design and is not this type.
///
/// The window is bounded by ``EnvironmentValues/surfaceSize``, the whole
/// surface rather than this view's own frame, because layout has not run
/// when a view compiles. The result is conservative — a list sharing the
/// screen with a header builds a few rows it cannot show — and still turns
/// a collection-sized build into a screen-sized one.
///
/// Host-less rendering has no surface, so every row is built. That keeps
/// `gama-demo --emit-mlir` and isolated `render(in:)` calls total.
public struct VirtualizedList<Data: RandomAccessCollection, Content: View>: View
where Data.Index == Int {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// The source collection; re-read on every build pass.
    public let data: Data
    /// Maps an element to the stable `NodeID` its row renders under.
    public let identity: (Data.Element) -> NodeID
    /// Produces the view for one element; called once per *visible*
    /// element per build pass.
    public let content: (Data.Element) -> Content
    /// Cell height of a single row; the window is computed from it.
    public let rowHeight: Int
    /// Host-owned first visible index, resolved against this node's
    /// identity so the scroll position survives the rebuild that follows
    /// every keystroke.
    private let offsetSlot = ReactiveSlot<Int>(0)

    /// Creates a windowed list over `data`, identifying each row by
    /// `id(element)` and assuming rows `rowHeight` cells tall.
    public init(
        _ data: Data,
        id: @escaping (Data.Element) -> NodeID,
        rowHeight: Int = 1,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.identity = id
        self.rowHeight = rowHeight
        self.content = content
    }

    /// Compiles the visible window into a top-leading vertical stack
    /// wrapped in an `.interactive` node, and registers the scroll keys
    /// when enabled.
    public func render(in context: BuildContext) -> RenderNode {
        let id = context.id
        let enabled = context.environment.isEnabled
        offsetSlot._bind(in: context, slot: 0)
        let offsetBinding = offsetSlot.binding()

        let count = data.count
        let step = max(1, rowHeight)
        // No surface means no viewport to window against; build it all.
        let capacity =
            context.environment.surfaceSize.map { max(1, $0.height / step) } ?? count
        let maxOffset = max(0, count - capacity)

        if enabled {
            context.registerKeyHandler(id) { key in
                let current = min(max(0, offsetBinding.wrappedValue), maxOffset)
                switch key {
                case .up:
                    offsetBinding.wrappedValue = max(0, current - 1)
                case .down:
                    offsetBinding.wrappedValue = min(maxOffset, current + 1)
                case .pageUp:
                    offsetBinding.wrappedValue = max(0, current - capacity)
                case .pageDown:
                    offsetBinding.wrappedValue = min(maxOffset, current + capacity)
                case .home:
                    offsetBinding.wrappedValue = 0
                case .end:
                    offsetBinding.wrappedValue = maxOffset
                default:
                    return false
                }
                // Consumed even when the offset did not move. Declining at
                // an end would hand the key to spatial navigation, whose
                // no-neighbour fallback is tab order — so overshooting the
                // last row would eject focus from the list instead of
                // doing nothing. Same reasoning as ADR 0014's arrow keys.
                return true
            }
        }

        let offset = min(max(0, offsetBinding.wrappedValue), maxOffset)
        let upper = min(count, offset + capacity)
        let rows: [RenderNode] = (offset..<upper).map { index in
            let element = data[index]
            var rowContext = context
            rowContext.id = identity(element)
            return content(element).render(in: rowContext)
        }

        return .interactive(
            id: id,
            focusable: enabled,
            child: .stack(
                axis: .vertical, spacing: 0, alignment: .topLeading, children: rows)
        )
    }
}
