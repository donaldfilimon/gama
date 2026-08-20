public struct ViewList: Equatable, Sendable {
    public var nodes: [ViewNode]
    public init(nodes: [ViewNode]) {
        self.nodes = nodes
    }
    public var singleOrStack: ViewNode {
        if nodes.isEmpty { return .empty }
        if nodes.count == 1 { return nodes[0] }
        return .stack(axis: .vertical, alignment: .leading, spacing: 0, nodes)
    }
}

@resultBuilder
public enum ViewBuilder {
    public static func buildBlock() -> ViewList {
        ViewList(nodes: [])
    }
    public static func buildBlock(_ parts: ViewNode...) -> ViewList {
        ViewList(nodes: Array(parts))
    }
    public static func buildOptional(_ part: ViewNode?) -> ViewNode {
        part ?? .empty
    }
    public static func buildEither(first: ViewNode) -> ViewNode {
        first
    }
    public static func buildEither(second: ViewNode) -> ViewNode {
        second
    }
    public static func buildArray(_ parts: [ViewNode]) -> ViewNode {
        .stack(axis: .vertical, alignment: .leading, spacing: 0, parts)
    }
    public static func buildExpression(_ node: ViewNode) -> ViewNode {
        node
    }
    public static func buildLimitedAvailability(_ list: ViewList) -> ViewList {
        list
    }
}

public func Text(_ string: String, style: TextStyle = .plain) -> ViewNode {
    .text(string, style)
}

public func Button(_ label: String, id: NodeID) -> ViewNode {
    .button(label: label, id: id)
}

public func TextField(_ text: String, placeholder: String = "", id: NodeID) -> ViewNode {
    .textField(text: text, placeholder: placeholder, id: id)
}

public func Checkbox(_ label: String, checked: Bool, id: NodeID) -> ViewNode {
    .checkbox(label: label, checked: checked, id: id)
}

public func Progress(_ value: Double) -> ViewNode {
    .progress(min(1, max(0, value)))
}

public func Divider(_ axis: Axis = .horizontal) -> ViewNode {
    .divider(axis)
}

public func Spacer(minLength: Int = 0) -> ViewNode {
    .spacer(minLength: minLength)
}

public func VStack(
    alignment: Alignment = .leading,
    spacing: Int = 0,
    @ViewBuilder content: () -> ViewList
) -> ViewNode {
    .stack(axis: .vertical, alignment: alignment, spacing: spacing, content().nodes)
}

public func HStack(
    alignment: Alignment = .leading,
    spacing: Int = 0,
    @ViewBuilder content: () -> ViewList
) -> ViewNode {
    .stack(axis: .horizontal, alignment: alignment, spacing: spacing, content().nodes)
}

public func ZStack(@ViewBuilder content: () -> ViewList) -> ViewNode {
    .overlay(content().nodes)
}

public func Padding(_ insets: EdgeInsets, @ViewBuilder content: () -> ViewList) -> ViewNode {
    .padding(insets, content().singleOrStack)
}

public func Padding(_ all: Int, @ViewBuilder content: () -> ViewList) -> ViewNode {
    Padding(EdgeInsets.all(all), content: content)
}

public func Frame(
    minWidth: Int? = nil,
    maxWidth: Int? = nil,
    minHeight: Int? = nil,
    maxHeight: Int? = nil,
    @ViewBuilder content: () -> ViewList
) -> ViewNode {
    .frame(
        minWidth: minWidth,
        maxWidth: maxWidth,
        minHeight: minHeight,
        maxHeight: maxHeight,
        content().singleOrStack
    )
}

public func List(
    id: NodeID,
    selected: Int,
    @ViewBuilder content: () -> ViewList
) -> ViewNode {
    .list(id: id, selected: selected, content().nodes)
}
