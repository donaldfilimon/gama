//  Layout.swift — GamaCore
//  Two-pass layout: `measure` answers sizeThatFits(proposal); `layout`
//  assigns absolute frames producing a LaidOutNode tree. Integer cell
//  space; GUI backends scale cells to a font/point grid, the MLIR path
//  carries frames as op attributes.

/// The shared two-pass layout solver. `measure` is the bottom-up sizing
/// pass; `layout` is the top-down placement pass. Both are pure functions
/// of the node tree — the engine holds no state — so every backend derives
/// identical geometry from the same `RenderNode`. All arithmetic is in
/// integer layout units; a `LayoutMetrics` value says what a unit means
/// and how authored cell lengths convert to it, defaulting to `.cell`,
/// which reproduces today's cell-space layout exactly.
public enum LayoutEngine {
    // MARK: Measure

    /// Answers what size `node` wants under `proposal`, measuring cells
    /// with `LayoutMetrics.cell`. Forwards to
    /// ``measure(_:proposal:metrics:)``.
    public static func measure(_ node: RenderNode, proposal: ProposedSize) -> Size {
        measure(node, proposal: proposal, metrics: .cell)
    }

    /// Answers what size `node` wants under `proposal`, using `metrics`
    /// to resolve text, authored lengths, dividers, and controls. A
    /// `nil` axis in the proposal is unconstrained: content replies with
    /// its ideal extent on that axis. Inside stacks, flexible children
    /// contribute only their main-axis floors here — the leftover space
    /// is distributed to them during `layout` — but they still
    /// contribute their measured cross extent.
    public static func measure(
        _ node: RenderNode, proposal: ProposedSize, metrics: LayoutMetrics
    ) -> Size {
        switch node {
        case .empty:
            return .zero

        case .text(let s, let style):
            return metrics.textSize(s, style, proposal.width)

        case .spacer(let minLength):
            return Size(
                width: metrics.units(minLength, .horizontal),
                height: metrics.units(minLength, .vertical)
            )

        case .divider:
            // Axis-resolved by the stack; the thickness stands in for
            // both dimensions until the stack picks the main axis.
            return Size(width: metrics.dividerThickness, height: metrics.dividerThickness)

        case .padding(let insets, let child):
            let converted = convert(insets, using: metrics)
            let inner = ProposedSize(
                width: proposal.width.map { max(0, $0 - converted.horizontal) },
                height: proposal.height.map { max(0, $0 - converted.vertical) }
            )
            let c = measure(child, proposal: inner, metrics: metrics)
            return Size(width: c.width + converted.horizontal, height: c.height + converted.vertical)

        case .border(_, _, let title, let child):
            let leftRight = metrics.units(1, .horizontal)
            let topBottom = metrics.units(1, .vertical)
            let inner = ProposedSize(
                width: proposal.width.map { max(0, $0 - 2 * leftRight) },
                height: proposal.height.map { max(0, $0 - 2 * topBottom) }
            )
            let c = measure(child, proposal: inner, metrics: metrics)
            // BorderTitleLayout's minimum width is in cells; convert it so
            // it compares with the unit-converted content width.
            let titleWidth = metrics.units(BorderTitleLayout.minimumWidth(for: title), .horizontal)
            return Size(
                width: max(c.width + 2 * leftRight, titleWidth), height: c.height + 2 * topBottom)

        case .background(_, let child), .styled(_, let child):
            return measure(child, proposal: proposal, metrics: metrics)

        case .interactive(let id, _, let child):
            if let size = metrics.controlSize(id, proposal) {
                return size
            }
            return measure(child, proposal: proposal, metrics: metrics)

        case .frame(let w, let h, _, let child):
            let cw = w.map { metrics.units($0, .horizontal) }
            let ch = h.map { metrics.units($0, .vertical) }
            let inner = ProposedSize(width: cw ?? proposal.width, height: ch ?? proposal.height)
            let c = measure(child, proposal: inner, metrics: metrics)
            return Size(width: cw ?? c.width, height: ch ?? c.height)

        case .flexFrame(let minW, let maxW, let minH, let maxH, _, let child):
            let c = measure(child, proposal: proposal, metrics: metrics)
            var width = c.width
            var height = c.height
            if let maxW {
                width =
                    maxW == .max
                    ? (proposal.width ?? c.width) : min(width, metrics.units(maxW, .horizontal))
            }
            if let minW { width = max(width, metrics.units(minW, .horizontal)) }
            if let maxH {
                height =
                    maxH == .max
                    ? (proposal.height ?? c.height) : min(height, metrics.units(maxH, .vertical))
            }
            if let minH { height = max(height, metrics.units(minH, .vertical)) }
            return Size(width: width, height: height)

        case .overlay(_, let children), .group(let children):
            var s = Size.zero
            for c in children {
                let m = measure(c, proposal: proposal, metrics: metrics)
                s.width = max(s.width, m.width)
                s.height = max(s.height, m.height)
            }
            return s

        case .stack(let axis, let spacing, _, let children):
            return measureStack(
                axis: axis, spacing: spacing, children: children, proposal: proposal,
                metrics: metrics)
        }
    }

    private static func measureStack(
        axis: Axis, spacing: Int, children: [RenderNode], proposal: ProposedSize,
        metrics: LayoutMetrics
    ) -> Size {
        guard !children.isEmpty else { return .zero }
        let convertedSpacing = metrics.units(spacing, axis)
        let totalSpacing = convertedSpacing * (children.count - 1)
        var mainUsed = 0
        var crossMax = 0
        var flexWeight = 0

        for child in children {
            if case .divider = child {
                mainUsed += metrics.dividerThickness
                continue
            }
            if case .flexible(let w) = child.flexPriority(along: axis) {
                flexWeight += w
                mainUsed += flexMinimum(
                    of: child, axis: axis, proposal: openProposal(proposal, along: axis), metrics: metrics)
                // Only the main axis is deferred to `layout`; the child
                // still has a natural cross extent the stack must report.
                // A spacer is the exception: `minLength` is a main-axis
                // floor, so its axis-agnostic measurement says nothing
                // about the cross axis.
                if case .spacer = child { continue }
                let m = measure(child, proposal: openProposal(proposal, along: axis), metrics: metrics)
                crossMax = max(crossMax, axis == .horizontal ? m.height : m.width)
                continue
            }
            let m = measure(child, proposal: openProposal(proposal, along: axis), metrics: metrics)
            mainUsed += (axis == .horizontal ? m.width : m.height)
            crossMax = max(crossMax, axis == .horizontal ? m.height : m.width)
        }

        let mainProposal = axis == .horizontal ? proposal.width : proposal.height
        let main: Int
        if flexWeight > 0, let available = mainProposal {
            main = max(available, mainUsed + totalSpacing)
        } else {
            main = mainUsed + totalSpacing
        }
        // The one-unit floor a stack applies to an empty cross axis stays
        // one layout unit — it is not an authored length, so it is never
        // passed through `metrics.units`.
        if crossMax == 0 { crossMax = 1 }
        return axis == .horizontal
            ? Size(width: main, height: crossMax)
            : Size(width: crossMax, height: main)
    }

    /// Main-axis floor a flexible child may never shrink below.
    private static func flexMinimum(
        of node: RenderNode, axis: Axis, proposal: ProposedSize, metrics: LayoutMetrics
    ) -> Int {
        switch node {
        case .spacer(let minLength):
            return metrics.units(minLength, axis)
        case .flexFrame(let minW, _, let minH, _, _, _):
            let raw = (axis == .horizontal ? minW : minH) ?? 0
            return metrics.units(raw, axis)
        case .padding(let e, let c):
            let edgeSum =
                axis == .horizontal
                ? metrics.units(e.leading, .horizontal) + metrics.units(e.trailing, .horizontal)
                : metrics.units(e.top, .vertical) + metrics.units(e.bottom, .vertical)
            return flexMinimum(of: c, axis: axis, proposal: proposal, metrics: metrics) + edgeSum
        case .border(_, _, _, let c):
            return flexMinimum(of: c, axis: axis, proposal: proposal, metrics: metrics)
                + 2 * metrics.units(1, axis)
        case .background(_, let c), .styled(_, let c):
            return flexMinimum(of: c, axis: axis, proposal: proposal, metrics: metrics)
        case .interactive(let id, _, let c):
            if let size = metrics.controlSize(id, proposal) {
                return axis == .horizontal ? size.width : size.height
            }
            return flexMinimum(of: c, axis: axis, proposal: proposal, metrics: metrics)
        // Exhaustive on purpose: a new case must choose its minimum here
        // instead of silently contributing zero.
        case .empty, .text, .stack, .overlay, .group, .divider, .frame:
            return 0
        }
    }

    /// Keep the cross-axis constraint, open the main axis.
    private static func openProposal(_ p: ProposedSize, along axis: Axis) -> ProposedSize {
        axis == .horizontal
            ? ProposedSize(width: nil, height: p.height)
            : ProposedSize(width: p.width, height: nil)
    }

    /// Converts insets edge by edge with the matching axis (top/bottom on
    /// `.vertical`, leading/trailing on `.horizontal`) rather than
    /// converting the pre-summed `horizontal`/`vertical` totals, so a
    /// non-linear `units` closure is honored per edge.
    private static func convert(_ insets: EdgeInsets, using metrics: LayoutMetrics) -> EdgeInsets {
        EdgeInsets(
            top: metrics.units(insets.top, .vertical),
            leading: metrics.units(insets.leading, .horizontal),
            bottom: metrics.units(insets.bottom, .vertical),
            trailing: metrics.units(insets.trailing, .horizontal)
        )
    }

    // MARK: Place

    /// Assigns `node` and its subtree absolute frames within `bounds`,
    /// measuring cells with `LayoutMetrics.cell`. Forwards to
    /// ``layout(_:in:metrics:)``.
    public static func layout(_ node: RenderNode, in bounds: Rect) -> LaidOutNode {
        layout(node, in: bounds, metrics: .cell)
    }

    /// Assigns `node` and its subtree absolute frames within `bounds`,
    /// using `metrics` to resolve text, authored lengths, dividers, and
    /// controls, re-invoking `measure` where alignment or flex
    /// distribution needs a child's ideal size. The returned tree mirrors
    /// the render tree with every frame resolved — the form `CellPainter`
    /// rasterizes and `FrameHost` hit-tests.
    public static func layout(
        _ node: RenderNode, in bounds: Rect, metrics: LayoutMetrics
    ) -> LaidOutNode {
        switch node {
        case .empty, .text, .spacer, .divider:
            return LaidOutNode(node: node, frame: bounds)

        case .padding(let insets, let child):
            let converted = convert(insets, using: metrics)
            let inner = layout(child, in: bounds.inset(by: converted), metrics: metrics)
            return LaidOutNode(node: node, frame: bounds, children: [inner])

        case .border(_, _, _, let child):
            let leftRight = metrics.units(1, .horizontal)
            let topBottom = metrics.units(1, .vertical)
            let insets = EdgeInsets(
                top: topBottom, leading: leftRight, bottom: topBottom, trailing: leftRight)
            let inner = layout(child, in: bounds.inset(by: insets), metrics: metrics)
            return LaidOutNode(node: node, frame: bounds, children: [inner])

        case .background(_, let child), .styled(_, let child),
            .interactive(_, _, let child):
            let inner = layout(child, in: bounds, metrics: metrics)
            return LaidOutNode(node: node, frame: bounds, children: [inner])

        case .frame(_, _, let alignment, let child):
            let ownSize = measure(
                node,
                proposal: ProposedSize(width: bounds.size.width, height: bounds.size.height),
                metrics: metrics
            ).clamped(to: bounds.size)
            let ownBounds = align(size: ownSize, in: bounds, alignment: alignment)
            let m = measure(
                child,
                proposal: ProposedSize(width: ownBounds.size.width, height: ownBounds.size.height),
                metrics: metrics
            ).clamped(to: ownBounds.size)
            let rect = align(size: m, in: ownBounds, alignment: alignment)
            return LaidOutNode(
                node: node, frame: ownBounds, children: [layout(child, in: rect, metrics: metrics)])

        case .flexFrame(_, _, _, _, let alignment, let child):
            let m = measure(
                child,
                proposal: ProposedSize(width: bounds.size.width, height: bounds.size.height),
                metrics: metrics
            ).clamped(to: bounds.size)
            let rect = align(size: m, in: bounds, alignment: alignment)
            return LaidOutNode(
                node: node, frame: bounds, children: [layout(child, in: rect, metrics: metrics)])

        case .overlay(let alignment, let children):
            let laid = children.map { c -> LaidOutNode in
                let m = measure(
                    c,
                    proposal: ProposedSize(width: bounds.size.width, height: bounds.size.height),
                    metrics: metrics
                ).clamped(to: bounds.size)
                return layout(c, in: align(size: m, in: bounds, alignment: alignment), metrics: metrics)
            }
            return LaidOutNode(node: node, frame: bounds, children: laid)

        case .group(let children):
            return layout(
                .overlay(alignment: .topLeading, children: children),
                in: bounds, metrics: metrics
            )

        case .stack(let axis, let spacing, let alignment, let children):
            return layoutStack(
                node: node, axis: axis, spacing: spacing,
                alignment: alignment, children: children, bounds: bounds, metrics: metrics
            )
        }
    }

    private static func layoutStack(
        node: RenderNode, axis: Axis, spacing: Int, alignment: Alignment,
        children: [RenderNode], bounds: Rect, metrics: LayoutMetrics
    ) -> LaidOutNode {
        guard !children.isEmpty else { return LaidOutNode(node: node, frame: bounds) }

        let mainAvailable = axis == .horizontal ? bounds.size.width : bounds.size.height
        let crossAvailable = axis == .horizontal ? bounds.size.height : bounds.size.width
        let convertedSpacing = metrics.units(spacing, axis)
        let totalSpacing = convertedSpacing * (children.count - 1)

        // 1. Measure fixed children; record flexible minima and weights.
        var sizes = [Size](repeating: .zero, count: children.count)
        var mins = [Int](repeating: 0, count: children.count)
        var flexTotal = 0
        var fixedMain = 0
        let crossProposal =
            axis == .horizontal
            ? ProposedSize(width: nil, height: crossAvailable)
            : ProposedSize(width: crossAvailable, height: nil)

        for (i, child) in children.enumerated() {
            if case .divider = child {
                // Axis-resolved: dividerThickness on main, fill on cross.
                sizes[i] =
                    axis == .horizontal
                    ? Size(width: metrics.dividerThickness, height: crossAvailable)
                    : Size(width: crossAvailable, height: metrics.dividerThickness)
                fixedMain += metrics.dividerThickness
                continue
            }
            if case .flexible(let w) = child.flexPriority(along: axis) {
                flexTotal += w
                mins[i] = flexMinimum(of: child, axis: axis, proposal: crossProposal, metrics: metrics)
                fixedMain += mins[i]
            } else {
                let m = measure(child, proposal: crossProposal, metrics: metrics)
                sizes[i] = m
                fixedMain += (axis == .horizontal ? m.width : m.height)
            }
        }

        // 2. Distribute leftover above minima to flexibles, weighted; the
        //    integer remainder spreads across the earliest flex items.
        if flexTotal > 0 {
            var remaining = max(0, mainAvailable - fixedMain - totalSpacing)
            var weightLeft = flexTotal
            for (i, child) in children.enumerated() {
                if case .divider = child { continue }
                guard case .flexible(let w) = child.flexPriority(along: axis) else { continue }
                let share = weightLeft > 0 ? (remaining * w + weightLeft - 1) / weightLeft : 0
                let granted = min(share, remaining)
                remaining -= granted
                weightLeft -= w
                let mainLen = mins[i] + granted
                sizes[i] =
                    axis == .horizontal
                    ? Size(width: mainLen, height: crossAvailable)
                    : Size(width: crossAvailable, height: mainLen)
            }
        }

        // 3. Place along main axis, align on cross axis.
        var cursor = axis == .horizontal ? bounds.minX : bounds.minY
        var laid: [LaidOutNode] = []
        laid.reserveCapacity(children.count)

        for (i, child) in children.enumerated() {
            let s = sizes[i]
            let mainLen = axis == .horizontal ? s.width : s.height
            let crossLen = axis == .horizontal ? s.height : s.width

            let offset = crossOffset(
                axis: axis, alignment: alignment, available: crossAvailable, length: crossLen
            )

            let rect =
                axis == .horizontal
                ? Rect(x: cursor, y: bounds.minY + offset, width: mainLen, height: crossLen)
                : Rect(x: bounds.minX + offset, y: cursor, width: crossLen, height: mainLen)

            if case .divider(let style, _) = child {
                laid.append(
                    LaidOutNode(
                        node: .divider(style: style, axis: axis),
                        frame: rect
                    )
                )
            } else {
                laid.append(layout(child, in: rect, metrics: metrics))
            }
            cursor += mainLen + convertedSpacing
        }

        return LaidOutNode(node: node, frame: bounds, children: laid)
    }

    /// Cross-axis offset of a stack child. Unlike `align`, trailing and
    /// bottom are clamped, so an oversized child never gets a negative offset.
    private static func crossOffset(
        axis: Axis, alignment: Alignment, available: Int, length: Int
    ) -> Int {
        switch axis {
        case .horizontal:
            switch alignment.vertical {
            case .top: return 0
            case .center: return max(0, (available - length) / 2)
            case .bottom: return max(0, available - length)
            }
        case .vertical:
            switch alignment.horizontal {
            case .leading: return 0
            case .center: return max(0, (available - length) / 2)
            case .trailing: return max(0, available - length)
            }
        }
    }

    private static func align(size: Size, in bounds: Rect, alignment: Alignment) -> Rect {
        let x: Int
        switch alignment.horizontal {
        case .leading: x = bounds.minX
        case .center: x = bounds.minX + max(0, (bounds.size.width - size.width) / 2)
        case .trailing: x = bounds.maxX - size.width
        }
        let y: Int
        switch alignment.vertical {
        case .top: y = bounds.minY
        case .center: y = bounds.minY + max(0, (bounds.size.height - size.height) / 2)
        case .bottom: y = bounds.maxY - size.height
        }
        return Rect(x: x, y: y, width: size.width, height: size.height)
    }
}
