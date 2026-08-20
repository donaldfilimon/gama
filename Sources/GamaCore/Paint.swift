public enum Paint {
    public static func paint(_ box: LayoutBox, into grid: inout CellGrid, focus: NodeID?) {
        paintNode(box, into: &grid, focus: focus)
    }

    static func paintNode(_ box: LayoutBox, into grid: inout CellGrid, focus: NodeID?) {
        let focused = isFocused(box.node, focus: focus)
        let style = focused ? TextStyle.plain.inverted() : TextStyle.plain
        switch box.node {
        case .empty, .spacer:
            break
        case .text(let string, let textStyle):
            putString(string, at: box.rect.origin, into: &grid, style: focused ? textStyle.inverted() : textStyle, maxWidth: box.rect.size.width)
        case .button(let label, _):
            putString("[ " + label + " ]", at: box.rect.origin, into: &grid, style: style, maxWidth: box.rect.size.width)
        case .textField(let text, let placeholder, _):
            let shown = text.isEmpty ? placeholder : text
            var padded = shown
            let width = box.rect.size.width
            while DisplayWidth.of(padded) < width { padded.append(" ") }
            putString(padded, at: box.rect.origin, into: &grid, style: style, maxWidth: width)
        case .checkbox(let label, let checked, _):
            let prefix = checked ? "[x] " : "[ ] "
            putString(prefix + label, at: box.rect.origin, into: &grid, style: style, maxWidth: box.rect.size.width)
        case .progress(let value):
            let w = max(3, box.rect.size.width)
            let inner = max(0, w - 2)
            let filled = Int((min(1, max(0, value)) * Double(inner)).rounded(.down))
            var s = "["
            if inner > 0 {
                s += String(repeating: "#", count: min(inner, filled))
                s += String(repeating: "-", count: max(0, inner - filled))
            }
            s += "]"
            putString(s, at: box.rect.origin, into: &grid, style: style, maxWidth: w)
        case .divider(.horizontal):
            putString(
                String(repeating: "-", count: max(0, box.rect.size.width)),
                at: box.rect.origin,
                into: &grid,
                style: style,
                maxWidth: box.rect.size.width
            )
        case .divider(.vertical):
            for i in 0..<box.rect.size.height {
                grid.put(x: box.rect.origin.x, y: box.rect.origin.y + i, scalar: "|", style: style)
            }
        case .padding, .frame, .stack, .overlay, .list:
            if focused, case .list = box.node {
                fillInverse(box.rect, into: &grid)
            }
            for child in box.children {
                paintNode(child, into: &grid, focus: focus)
            }
        }
    }

    static func isFocused(_ node: ViewNode, focus: NodeID?) -> Bool {
        guard let focus else { return false }
        switch node {
        case .button(_, let id), .textField(_, _, let id), .checkbox(_, _, let id), .list(let id, _, _):
            return id == focus
        default:
            return false
        }
    }

    static func fillInverse(_ rect: Rect, into grid: inout CellGrid) {
        let style = TextStyle.plain.inverted()
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                if grid[x, y] == .blank {
                    grid.put(x: x, y: y, scalar: " ", style: style)
                }
            }
        }
    }

    static func putString(
        _ string: String,
        at origin: Point,
        into grid: inout CellGrid,
        style: TextStyle,
        maxWidth: Int
    ) {
        var x = origin.x
        let limit = origin.x + max(0, maxWidth)
        for scalar in string.unicodeScalars {
            let w = DisplayWidth.of(scalar)
            if x + w > limit { break }
            if w > 0 {
                grid.put(x: x, y: origin.y, scalar: scalar, style: style)
            }
            x += w
        }
    }
}
