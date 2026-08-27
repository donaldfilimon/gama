//  Layout.swift — GamaCore
//  Two-pass layout: `measure` answers sizeThatFits(proposal); `layout`
//  assigns absolute frames producing a LaidOutNode tree. Integer cell
//  space; GUI backends scale cells to a font/point grid, the MLIR path
//  carries frames as op attributes.

/// The shared two-pass layout solver. `measure` is the bottom-up sizing
/// pass; `layout` is the top-down placement pass. Both are pure functions
/// of the node tree — the engine holds no state — so every backend derives
/// identical geometry from the same `RenderNode`. All arithmetic is in
/// integer cells; GUI backends scale the result to their own grid.
public enum LayoutEngine {
    // MARK: Measure

    /// Answers what size `node` wants under `proposal`. A `nil` axis in
    /// the proposal is unconstrained: content replies with its ideal
    /// extent on that axis. Inside stacks, flexible children contribute
    /// only their main-axis floors here — the leftover space is
    /// distributed to them during `layout`.
    public static func measure(_ node: RenderNode, proposal: ProposedSize) -> Size {
        switch node {
        case .empty:
            return .zero

        case .text(let s, _):
            return TextLayout.size(of: s, width: proposal.width)

        case .spacer(let minLength):
            return Size(width: minLength, height: minLength)

        case .divider:
            return Size(width: 1, height: 1)  // axis-resolved by the stack

        case .padding(let insets, let child):
            let inner = ProposedSize(
                width: proposal.width.map { max(0, $0 - insets.horizontal) },
                height: proposal.height.map { max(0, $0 - insets.vertical) }
            )
            let c = measure(child, proposal: inner)
            return Size(width: c.width + insets.horizontal, height: c.height + insets.vertical)

        case .border(_, _, let title, let child):
            let inner = ProposedSize(
                width: proposal.width.map { max(0, $0 - 2) },
                height: proposal.height.map { max(0, $0 - 2) }
            )
            let c = measure(child, proposal: inner)
            let titleWidth = title.map { TextLayout.displayWidth(of: $0) + 4 } ?? 0
            return Size(width: max(c.width + 2, titleWidth), height: c.height + 2)

        case .background(_, let child), .styled(_, let child),
            .interactive(_, _, let child):
            return measure(child, proposal: proposal)

        case .frame(let w, let h, _, let child):
            let inner = ProposedSize(width: w ?? proposal.width, height: h ?? proposal.height)
            let c = measure(child, proposal: inner)
            return Size(width: w ?? c.width, height: h ?? c.height)

        case .flexFrame(let minW, let maxW, let minH, let maxH, _, let child):
            let c = measure(child, proposal: proposal)
            var width = c.width
            var height = c.height
            if let maxW { width = maxW == .max ? (proposal.width ?? c.width) : min(width, maxW) }
            if let minW { width = max(width, minW) }
            if let maxH { height = maxH == .max ? (proposal.height ?? c.height) : min(height, maxH) }
            if let minH { height = max(height, minH) }
            return Size(width: width, height: height)

        case .overlay(_, let children):
            var s = Size.zero
            for c in children {
                let m = measure(c, proposal: proposal)
                s.width = max(s.width, m.width)
                s.height = max(s.height, m.height)
            }
            return s

        case .stack(let axis, let spacing, _, let children):
            return measureStack(axis: axis, spacing: spacing, children: children, proposal: proposal)
        }
    }

    private static func measureStack(
        axis: Axis, spacing: Int, children: [RenderNode], proposal: ProposedSize
    ) -> Size {
        guard !children.isEmpty else { return .zero }
        let totalSpacing = spacing * (children.count - 1)
        var mainUsed = 0
        var crossMax = 0
        var flexWeight = 0

        for child in children {
            if case .divider = child {
                mainUsed += 1
                continue
            }
            if case .flexible(let w) = child.flexPriority {
                flexWeight += w
                mainUsed += flexMinimum(of: child, axis: axis)
                continue
            }
            let m = measure(child, proposal: openProposal(proposal, along: axis))
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
        if crossMax == 0 { crossMax = 1 }
        return axis == .horizontal
            ? Size(width: main, height: crossMax)
            : Size(width: crossMax, height: main)
    }

    /// Main-axis floor a flexible child may never shrink below.
    private static func flexMinimum(of node: RenderNode, axis: Axis) -> Int {
        switch node {
        case .spacer(let minLength):
            return minLength
        case .flexFrame(let minW, _, let minH, _, _, _):
            return (axis == .horizontal ? minW : minH) ?? 0
        case .padding(let e, let c):
            return flexMinimum(of: c, axis: axis)
                + (axis == .horizontal ? e.horizontal : e.vertical)
        case .border(_, _, _, let c):
            return flexMinimum(of: c, axis: axis) + 2
        case .background(_, let c), .styled(_, let c), .interactive(_, _, let c):
            return flexMinimum(of: c, axis: axis)
        default:
            return 0
        }
    }

    /// Keep the cross-axis constraint, open the main axis.
    private static func openProposal(_ p: ProposedSize, along axis: Axis) -> ProposedSize {
        axis == .horizontal
            ? ProposedSize(width: nil, height: p.height)
            : ProposedSize(width: p.width, height: nil)
    }

    // MARK: Place

    /// Assigns `node` and its subtree absolute frames within `bounds`,
    /// re-invoking `measure` where alignment or flex distribution needs a
    /// child's ideal size. The returned tree mirrors the render tree with
    /// every frame resolved — the form `CellPainter` rasterizes and
    /// `FrameHost` hit-tests.
    public static func layout(_ node: RenderNode, in bounds: Rect) -> LaidOutNode {
        switch node {
        case .empty, .text, .spacer, .divider:
            return LaidOutNode(node: node, frame: bounds)

        case .padding(let insets, let child):
            let inner = layout(child, in: bounds.inset(by: insets))
            return LaidOutNode(node: node, frame: bounds, children: [inner])

        case .border(_, _, _, let child):
            let inner = layout(child, in: bounds.inset(by: EdgeInsets(all: 1)))
            return LaidOutNode(node: node, frame: bounds, children: [inner])

        case .background(_, let child), .styled(_, let child),
            .interactive(_, _, let child):
            let inner = layout(child, in: bounds)
            return LaidOutNode(node: node, frame: bounds, children: [inner])

        case .frame(_, _, let alignment, let child):
            let ownSize = measure(
                node,
                proposal: ProposedSize(width: bounds.size.width, height: bounds.size.height)
            ).clamped(to: bounds.size)
            let ownBounds = align(size: ownSize, in: bounds, alignment: alignment)
            let m = measure(
                child,
                proposal: ProposedSize(width: ownBounds.size.width, height: ownBounds.size.height)
            ).clamped(to: ownBounds.size)
            let rect = align(size: m, in: ownBounds, alignment: alignment)
            return LaidOutNode(node: node, frame: ownBounds, children: [layout(child, in: rect)])

        case .flexFrame(_, _, _, _, let alignment, let child):
            let m = measure(
                child,
                proposal: ProposedSize(width: bounds.size.width, height: bounds.size.height)
            ).clamped(to: bounds.size)
            let rect = align(size: m, in: bounds, alignment: alignment)
            return LaidOutNode(node: node, frame: bounds, children: [layout(child, in: rect)])

        case .overlay(let alignment, let children):
            let laid = children.map { c -> LaidOutNode in
                let m = measure(
                    c,
                    proposal: ProposedSize(width: bounds.size.width, height: bounds.size.height)
                ).clamped(to: bounds.size)
                return layout(c, in: align(size: m, in: bounds, alignment: alignment))
            }
            return LaidOutNode(node: node, frame: bounds, children: laid)

        case .stack(let axis, let spacing, let alignment, let children):
            return layoutStack(
                node: node, axis: axis, spacing: spacing,
                alignment: alignment, children: children, bounds: bounds
            )
        }
    }

    private static func layoutStack(
        node: RenderNode, axis: Axis, spacing: Int, alignment: Alignment,
        children: [RenderNode], bounds: Rect
    ) -> LaidOutNode {
        guard !children.isEmpty else { return LaidOutNode(node: node, frame: bounds) }

        let mainAvailable = axis == .horizontal ? bounds.size.width : bounds.size.height
        let crossAvailable = axis == .horizontal ? bounds.size.height : bounds.size.width
        let totalSpacing = spacing * (children.count - 1)

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
                // Axis-resolved: 1 on main, fill on cross.
                sizes[i] =
                    axis == .horizontal
                    ? Size(width: 1, height: crossAvailable)
                    : Size(width: crossAvailable, height: 1)
                fixedMain += 1
                continue
            }
            if case .flexible(let w) = child.flexPriority {
                flexTotal += w
                mins[i] = flexMinimum(of: child, axis: axis)
                fixedMain += mins[i]
            } else {
                let m = measure(child, proposal: crossProposal)
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
                guard case .flexible(let w) = child.flexPriority else { continue }
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

            let crossOffset: Int
            switch axis {
            case .horizontal:
                switch alignment.vertical {
                case .top: crossOffset = 0
                case .center: crossOffset = max(0, (crossAvailable - crossLen) / 2)
                case .bottom: crossOffset = max(0, crossAvailable - crossLen)
                }
            case .vertical:
                switch alignment.horizontal {
                case .leading: crossOffset = 0
                case .center: crossOffset = max(0, (crossAvailable - crossLen) / 2)
                case .trailing: crossOffset = max(0, crossAvailable - crossLen)
                }
            }

            let rect =
                axis == .horizontal
                ? Rect(x: cursor, y: bounds.minY + crossOffset, width: mainLen, height: crossLen)
                : Rect(x: bounds.minX + crossOffset, y: cursor, width: crossLen, height: mainLen)

            laid.append(layout(child, in: rect))
            cursor += mainLen + spacing
        }

        return LaidOutNode(node: node, frame: bounds, children: laid)
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
