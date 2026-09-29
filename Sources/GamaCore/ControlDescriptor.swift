//  ControlDescriptor.swift — GamaCore
//  What a native presentation host needs to show a control as a platform
//  control (ADR 0017). Controls register a descriptor in a per-build side
//  table through `BuildContext.registerControl`, the same pattern as
//  actions and native regions, so `RenderNode`, the MLIR dialect, and the
//  DrawList wire format stay unchanged and the cell path never reads it.

/// What a native host needs to present a control; closures write back.
///
/// Not `Equatable`, `Hashable`, or `Sendable`: ``textField(placeholder:text:isEnabled:setText:)``
/// carries a closure that writes the field's host-confined binding, and a
/// descriptor lives only for the build that registered it.
public enum ControlDescriptor {
    /// A push button. `title` is the label's text when the label compiles
    /// to a single text run, and `nil` for a composite label, which a host
    /// presents as a clickable container around the label's own views.
    case button(title: String?, isEnabled: Bool)
    /// A checkbox showing `isOn`; activating it runs the node's action,
    /// which flips the bound value.
    case toggle(title: String, isOn: Bool, isEnabled: Bool)
    /// An editable single-line field showing `text`, or `placeholder` while
    /// `text` is empty. `setText` writes a new value through the field's
    /// binding.
    case textField(placeholder: String, text: String, isEnabled: Bool, setText: (String) -> Void)
    /// A read-only progress indicator at `fraction` (0...1), or indeterminate
    /// when `nil`, with an optional `label`.
    case progress(fraction: Double?, label: String?)
}
