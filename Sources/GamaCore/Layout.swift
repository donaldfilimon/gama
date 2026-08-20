public struct LayoutBox: Equatable, Sendable {
    public var node: ViewNode
    public var rect: Rect
    public var children: [LayoutBox]
    public init(node: ViewNode, rect: Rect, children: [LayoutBox]) {
        self.node = node
        self.rect = rect
        self.children = children
    }
    public var size: Size { rect.size }
}

public enum Layout {
    public static func layout(_ root: ViewNode, in proposed: Size) -> LayoutBox {
        place(root, origin: Point(x: 0, y: 0), proposed: proposed.clampedNonNegative)
    }

    static func measure(_ node: ViewNode, proposed: Size) -> Size {
        let p = proposed.clampedNonNegative
        switch node {
        case .empty:
            return .zero
        case .text(let string, _):
            return Size(width: DisplayWidth.of(string), height: 1)
        case .button(let label, _):
            return Size(width: DisplayWidth.of("[ " + label + " ]"), height: 1)
        case .textField(let text, let placeholder, _):
            let content = text.isEmpty ? placeholder : text
            let w = max(8, DisplayWidth.of(content))
            return Size(width: max(w, p.width), height: 1)
        case .checkbox(let label, let checked, _):
            let prefix = checked ? "[x] " : "[ ] "
            return Size(width: DisplayWidth.of(prefix + label), height: 1)
        case .progress:
            return Size(width: max(3, p.width), height: 1)
        case .divider(.horizontal):
            return Size(width: p.width, height: 1)
        case .divider(.vertical):
            return Size(width: 1, height: p.height)
        case .spacer(let minLength):
            return Size(width: minLength, height: 0)
        case .padding(let insets, let child):
            let inner = Size(
                width: max(0, p.width - insets.leading - insets.trailing),
                height: max(0, p.height - insets.top - insets.bottom)
            )
            let cs = measure(child, proposed: inner)
            return Size(
                width: cs.width + insets.leading + insets.trailing,
                height: cs.height + insets.top + insets.bottom
            )
        case .frame(let minW, let maxW, let minH, let maxH, let child):
            var s = measure(child, proposed: p)
            if let minW { s.width = max(s.width, minW) }
            if let maxW { s.width = min(s.width, maxW) }
            if let minH { s.height = max(s.height, minH) }
            if let maxH { s.height = min(s.height, maxH) }
            return Size(width: max(0, s.width), height: max(0, s.height))
        case .stack(let axis, _, let spacing, let children):
            return measureStack(axis: axis, spacing: spacing, children: children, proposed: p)
        case .overlay(let children):
            var w = 0
            var h = 0
            for child in children {
                let s = measure(child, proposed: p)
                w = max(w, s.width)
                h = max(h, s.height)
            }
            return Size(width: min(p.width, w), height: min(p.height, h))
        case .list(_, _, let children):
            return measureStack(axis: .vertical, spacing: 0, children: children, proposed: p)
        }
    }

    static func measureStack(
        axis: Axis,
        spacing: Int,
        children: [ViewNode],
        proposed: Size
    ) -> Size {
        let unbounded = Int.max / 4
        var along = 0
        var cross = 0
        var gaps = 0
        for (i, child) in children.enumerated() {
            if case .spacer = child { continue }
            let childProposed: Size
            switch axis {
            case .vertical:
                childProposed = Size(width: proposed.width, height: unbounded)
            case .horizontal:
                childProposed = Size(width: unbounded, height: proposed.height)
            }
            let s = measure(child, proposed: childProposed)
            switch axis {
            case .vertical:
                along += s.height
                cross = max(cross, s.width)
            case .horizontal:
                along += s.width
                cross = max(cross, s.height)
            }
            if i > 0 { gaps += 1 }
        }
        let space = max(0, spacing) * max(0, children.count - 1)
        // Recount gaps only between all children (including spacers) as spec: spacing between adjacent children.
        let gapCount = max(0, children.count - 1)
        along += max(0, spacing) * gapCount
        _ = space
        switch axis {
        case .vertical:
            return Size(width: min(proposed.width, cross), height: along)
        case .horizontal:
            return Size(width: along, height: min(proposed.height, cross))
        }
    }

    static func place(_ node: ViewNode, origin: Point, proposed: Size) -> LayoutBox {
        let p = proposed.clampedNonNegative
        switch node {
        case .empty:
            return LayoutBox(node: node, rect: Rect(origin: origin, size: .zero), children: [])
        case .text, .button, .checkbox:
            let s = measure(node, proposed: p)
            return LayoutBox(node: node, rect: Rect(origin: origin, size: s), children: [])
        case .textField:
            let s = measure(node, proposed: p)
            return LayoutBox(node: node, rect: Rect(origin: origin, size: s), children: [])
        case .progress:
            let s = Size(width: max(3, p.width), height: 1)
            return LayoutBox(node: node, rect: Rect(origin: origin, size: s), children: [])
        case .divider(.horizontal):
            let s = Size(width: p.width, height: 1)
            return LayoutBox(node: node, rect: Rect(origin: origin, size: s), children: [])
        case .divider(.vertical):
            let s = Size(width: 1, height: p.height)
            return LayoutBox(node: node, rect: Rect(origin: origin, size: s), children: [])
        case .spacer(let minLength):
            let s: Size
            // Standalone spacer: minLength along x, 0 height. Stacks override via placeStack.
            s = Size(width: minLength, height: 0)
            return LayoutBox(node: node, rect: Rect(origin: origin, size: s), children: [])
        case .padding(let insets, let child):
            let innerProposed = Size(
                width: max(0, p.width - insets.leading - insets.trailing),
                height: max(0, p.height - insets.top - insets.bottom)
            )
            let childBox = place(
                child,
                origin: Point(x: origin.x + insets.leading, y: origin.y + insets.top),
                proposed: innerProposed
            )
            let size = Size(
                width: childBox.size.width + insets.leading + insets.trailing,
                height: childBox.size.height + insets.top + insets.bottom
            )
            return LayoutBox(
                node: node,
                rect: Rect(origin: origin, size: size),
                children: [childBox]
            )
        case .frame(let minW, let maxW, let minH, let maxH, let child):
            var childProposed = p
            if let maxW { childProposed.width = min(childProposed.width, maxW) }
            if let maxH { childProposed.height = min(childProposed.height, maxH) }
            let childBox = place(child, origin: origin, proposed: childProposed)
            var size = childBox.size
            if let minW { size.width = max(size.width, minW) }
            if let maxW { size.width = min(size.width, maxW) }
            if let minH { size.height = max(size.height, minH) }
            if let maxH { size.height = min(size.height, maxH) }
            size = size.clampedNonNegative
            return LayoutBox(
                node: node,
                rect: Rect(origin: origin, size: size),
                children: [childBox]
            )
        case .stack(let axis, let alignment, let spacing, let children):
            return placeStack(
                node: node,
                axis: axis,
                alignment: alignment,
                spacing: spacing,
                children: children,
                origin: origin,
                proposed: p,
                clipList: false
            )
        case .overlay(let children):
            let size = measure(node, proposed: p)
            let placed = children.map { place($0, origin: origin, proposed: size) }
            return LayoutBox(
                node: node,
                rect: Rect(origin: origin, size: size),
                children: placed
            )
        case .list(_, _, let children):
            return placeStack(
                node: node,
                axis: .vertical,
                alignment: .leading,
                spacing: 0,
                children: children,
                origin: origin,
                proposed: p,
                clipList: true
            )
        }
    }

    static func placeStack(
        node: ViewNode,
        axis: Axis,
        alignment: Alignment,
        spacing: Int,
        children: [ViewNode],
        origin: Point,
        proposed: Size,
        clipList: Bool
    ) -> LayoutBox {
        let gap = max(0, spacing)
        var nonSpacerAlong = 0
        var spacerCount = 0
        var measured: [Size] = []
        measured.reserveCapacity(children.count)
        let unbounded = Int.max / 4
        for child in children {
            if case .spacer = child {
                spacerCount += 1
                measured.append(.zero)
                continue
            }
            let childProposed: Size
            switch axis {
            case .vertical:
                childProposed = Size(width: proposed.width, height: unbounded)
            case .horizontal:
                childProposed = Size(width: unbounded, height: proposed.height)
            }
            let s = measure(child, proposed: childProposed)
            measured.append(s)
            switch axis {
            case .vertical: nonSpacerAlong += s.height
            case .horizontal: nonSpacerAlong += s.width
            }
        }
        let gapTotal = gap * max(0, children.count - 1)
        let proposedAlong = axis == .vertical ? proposed.height : proposed.width
        let leftover = proposedAlong - nonSpacerAlong - gapTotal
        let spacerShare: Int
        if spacerCount > 0 {
            spacerShare = leftover > 0 ? leftover / spacerCount : 0
        } else {
            spacerShare = 0
        }

        var cursor = axis == .vertical ? origin.y : origin.x
        var boxes: [LayoutBox] = []
        var maxCross = 0
        for (i, child) in children.enumerated() {
            if clipList, axis == .vertical, cursor >= origin.y + proposed.height {
                break
            }
            let childSize: Size
            if case .spacer(let minLength) = child {
                let along = max(minLength, spacerShare)
                childSize = axis == .vertical
                    ? Size(width: 0, height: along)
                    : Size(width: along, height: 0)
            } else {
                childSize = measured[i]
            }
            if clipList, axis == .vertical {
                let remaining = origin.y + proposed.height - cursor
                if remaining <= 0 { break }
                if childSize.height > remaining { break }
            }
            let cross: Int
            let containerCross = axis == .vertical ? proposed.width : proposed.height
            let childCross = axis == .vertical ? childSize.width : childSize.height
            switch alignment {
            case .leading: cross = 0
            case .trailing: cross = max(0, containerCross - childCross)
            case .center: cross = max(0, (containerCross - childCross) / 2)
            }
            let childOrigin: Point
            let childProposed: Size
            switch axis {
            case .vertical:
                childOrigin = Point(x: origin.x + cross, y: cursor)
                childProposed = Size(width: proposed.width, height: childSize.height)
                maxCross = max(maxCross, childSize.width)
            case .horizontal:
                childOrigin = Point(x: cursor, y: origin.y + cross)
                childProposed = Size(width: childSize.width, height: proposed.height)
                maxCross = max(maxCross, childSize.height)
            }
            let box: LayoutBox
            if case .spacer = child {
                box = LayoutBox(
                    node: child,
                    rect: Rect(origin: childOrigin, size: childSize),
                    children: []
                )
            } else {
                box = place(child, origin: childOrigin, proposed: childProposed)
            }
            boxes.append(box)
            switch axis {
            case .vertical:
                cursor += box.rect.size.height + gap
            case .horizontal:
                cursor += box.rect.size.width + gap
            }
        }
        let usedAlong: Int
        if boxes.isEmpty {
            usedAlong = 0
        } else {
            switch axis {
            case .vertical:
                usedAlong = boxes.last!.rect.maxY - origin.y
            case .horizontal:
                usedAlong = boxes.last!.rect.maxX - origin.x
            }
        }
        let size: Size
        switch axis {
        case .vertical:
            size = Size(width: min(proposed.width, max(maxCross, boxes.map { $0.size.width }.max() ?? 0)), height: usedAlong)
        case .horizontal:
            size = Size(width: usedAlong, height: min(proposed.height, max(maxCross, boxes.map { $0.size.height }.max() ?? 0)))
        }
        return LayoutBox(node: node, rect: Rect(origin: origin, size: size), children: boxes)
    }
}
