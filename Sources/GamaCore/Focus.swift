public enum FocusOrder {
    public static func focusableIDs(_ root: ViewNode) -> [NodeID] {
        var ids: [NodeID] = []
        walk(root, into: &ids)
        return ids
    }

    static func walk(_ node: ViewNode, into ids: inout [NodeID]) {
        switch node {
        case .button(_, let id), .textField(_, _, let id), .checkbox(_, _, let id):
            ids.append(id)
        case .list(let id, _, let children):
            ids.append(id)
            for child in children { walk(child, into: &ids) }
        case .padding(_, let child), .frame(_, _, _, _, let child):
            walk(child, into: &ids)
        case .stack(_, _, _, let children), .overlay(let children):
            for child in children { walk(child, into: &ids) }
        default:
            break
        }
    }
}

public enum HitTest {
    public static func hit(_ box: LayoutBox, at point: Point) -> NodeID? {
        for child in box.children.reversed() {
            if let id = hit(child, at: point) { return id }
        }
        if box.rect.contains(point) {
            return nodeID(box.node)
        }
        return nil
    }

    static func nodeID(_ node: ViewNode) -> NodeID? {
        switch node {
        case .button(_, let id), .textField(_, _, let id), .checkbox(_, _, let id), .list(let id, _, _):
            return id
        default:
            return nil
        }
    }
}
