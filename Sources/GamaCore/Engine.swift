public struct Engine: Sendable {
    public var root: ViewNode
    public var focus: NodeID?
    public var size: Size

    public init(root: ViewNode, size: Size) {
        self.root = root
        self.size = size.clampedNonNegative
        self.focus = FocusOrder.focusableIDs(root).first
    }

    public mutating func setRoot(_ root: ViewNode) {
        self.root = root
        let ids = FocusOrder.focusableIDs(root)
        if let focus, ids.contains(focus) {
            return
        }
        self.focus = ids.first
    }

    public mutating func handle(_ event: Event) -> Action? {
        switch event {
        case .resize(let size):
            self.size = size.clampedNonNegative
            return nil
        case .mouse(let mouse):
            return handleMouse(mouse)
        case .key(let key):
            return handleKey(key)
        }
    }

    mutating func handleKey(_ key: Key) -> Action? {
        let ids = FocusOrder.focusableIDs(root)
        switch key {
        case .tab:
            moveFocus(ids: ids, delta: 1)
            return nil
        case .backTab:
            moveFocus(ids: ids, delta: -1)
            return nil
        case .enter:
            return activate(space: false)
        case .character(" "):
            return activate(space: true)
        case .character(let ch):
            return editField(insert: String(ch))
        case .backspace:
            return editField(insert: nil)
        case .up:
            return moveList(delta: -1)
        case .down:
            return moveList(delta: 1)
        case .left, .right, .escape, .ctrlC:
            return nil
        }
    }

    mutating func handleMouse(_ mouse: Mouse) -> Action? {
        guard mouse.kind == .press else { return nil }
        let box = Layout.layout(root, in: size)
        guard let id = HitTest.hit(box, at: Point(x: mouse.x, y: mouse.y)) else { return nil }
        focus = id
        if let node = findNode(id, in: root) {
            switch node {
            case .button:
                return .tap(id)
            case .checkbox:
                return .toggle(id)
            case .textField:
                return nil
            case .list(_, _, let children):
                if let index = rowIndex(in: box, listID: id, at: Point(x: mouse.x, y: mouse.y), count: children.count) {
                    return .select(id, index)
                }
                return nil
            default:
                return nil
            }
        }
        return nil
    }

    mutating func moveFocus(ids: [NodeID], delta: Int) {
        guard !ids.isEmpty else {
            focus = nil
            return
        }
        if let focus, let idx = ids.firstIndex(of: focus) {
            let next = (idx + delta + ids.count * 4) % ids.count
            self.focus = ids[next]
        } else {
            self.focus = delta >= 0 ? ids.first : ids.last
        }
    }

    func activate(space: Bool) -> Action? {
        guard let focus, let node = findNode(focus, in: root) else { return nil }
        switch node {
        case .button:
            return .tap(focus)
        case .checkbox:
            return .toggle(focus)
        case .textField:
            if space { return editField(insert: " ") }
            return .submit(focus)
        default:
            return nil
        }
    }

    func editField(insert: String?) -> Action? {
        guard let focus, let node = findNode(focus, in: root) else { return nil }
        guard case .textField(let text, _, _) = node else { return nil }
        var next = text
        if let insert {
            next.append(contentsOf: insert)
        } else if !next.isEmpty {
            next.removeLast()
        }
        return .edit(focus, next)
    }

    func moveList(delta: Int) -> Action? {
        guard let focus, let node = findNode(focus, in: root) else { return nil }
        guard case .list(_, let selected, let children) = node else { return nil }
        let count = children.count
        guard count > 0 else { return .select(focus, 0) }
        let next = min(count - 1, max(0, selected + delta))
        return .select(focus, next)
    }

    func findNode(_ id: NodeID, in node: ViewNode) -> ViewNode? {
        switch node {
        case .button(_, let nid) where nid == id,
             .textField(_, _, let nid) where nid == id,
             .checkbox(_, _, let nid) where nid == id,
             .list(let nid, _, _) where nid == id:
            return node
        case .padding(_, let child), .frame(_, _, _, _, let child):
            return findNode(id, in: child)
        case .stack(_, _, _, let children), .overlay(let children), .list(_, _, let children):
            for child in children {
                if let found = findNode(id, in: child) { return found }
            }
            return nil
        default:
            return nil
        }
    }

    func rowIndex(in box: LayoutBox, listID: NodeID, at point: Point, count: Int) -> Int? {
        let listBox = findBox(listID, in: box) ?? box
        for (i, child) in listBox.children.enumerated() {
            if child.rect.contains(point) { return min(i, count - 1) }
        }
        return nil
    }

    func findBox(_ id: NodeID, in box: LayoutBox) -> LayoutBox? {
        if HitTest.nodeID(box.node) == id { return box }
        for child in box.children {
            if let found = findBox(id, in: child) { return found }
        }
        return nil
    }
}
