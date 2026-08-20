public enum ViewNode: Equatable, Sendable {
    case empty
    case text(String, TextStyle)
    case button(label: String, id: NodeID)
    case textField(text: String, placeholder: String, id: NodeID)
    case checkbox(label: String, checked: Bool, id: NodeID)
    case progress(Double)
    case divider(Axis)
    case spacer(minLength: Int)
    indirect case padding(EdgeInsets, ViewNode)
    indirect case frame(
        minWidth: Int?,
        maxWidth: Int?,
        minHeight: Int?,
        maxHeight: Int?,
        ViewNode
    )
    indirect case stack(axis: Axis, alignment: Alignment, spacing: Int, [ViewNode])
    indirect case overlay([ViewNode])
    indirect case list(id: NodeID, selected: Int, [ViewNode])
}
