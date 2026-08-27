//  Primitives.swift — GamaCore

// MARK: - Text

/// A run of styled text. Measured in display cells via `TextLayout`
/// (combining marks are zero width; scalars in the implemented wide table
/// — East Asian Wide/Fullwidth ranges, common emoji blocks, and anything
/// followed by variation selector-16 — are two; emoji outside that table
/// measure one) and greedily word-wrapped when the proposal constrains
/// width.
public struct Text: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// The string to draw. Embedded newlines start new lines; width is
    /// measured in display cells, not characters.
    public var content: String
    /// Style merged over the inherited style at render time — non-default
    /// fields here win, attributes accumulate.
    public var style: TextStyle

    /// Creates styled text; with the default `.plain` style the text
    /// simply inherits its surroundings.
    public init(_ content: String, style: TextStyle = .plain) {
        self.content = content
        self.style = style
    }

    /// Compiles to a `.text` node carrying the inherited style merged
    /// under this text's own style.
    public func render(in context: BuildContext) -> RenderNode {
        .text(content, style: context.inheritedStyle.merging(style))
    }

    /// A copy with the bold attribute added; chainable.
    public func bold() -> Text {
        var t = self; t.style.attributes.insert(.bold); return t
    }
    /// A copy with the italic attribute added; chainable.
    public func italic() -> Text {
        var t = self; t.style.attributes.insert(.italic); return t
    }
    /// A copy with the underline attribute added; chainable.
    public func underline() -> Text {
        var t = self; t.style.attributes.insert(.underline); return t
    }
}

// MARK: - Stacks

/// Arranges children top to bottom. Fixed children keep their measured
/// heights; `Spacer`s and greedy flex frames split the leftover height by
/// weight.
public struct VStack<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// Cross-axis placement of children narrower than the stack.
    public var alignment: HorizontalAlignment
    /// Cells inserted between adjacent children — not before the first or
    /// after the last.
    public var spacing: Int
    /// The stacked children; builder containers flatten into a plain
    /// child list at render time.
    public var content: Content

    /// Creates a vertical stack; by default children are leading-aligned
    /// with no spacing.
    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    /// Compiles to a vertical `.stack`, flattening tuple/loop sentinels
    /// into direct children.
    public func render(in context: BuildContext) -> RenderNode {
        .stack(
            axis: .vertical,
            spacing: spacing,
            alignment: Alignment(horizontal: alignment, vertical: .top),
            children: flattenChildren(content.render(in: context.child(0)))
        )
    }
}

/// Arranges children left to right. Fixed children keep their measured
/// widths; `Spacer`s and greedy flex frames split the leftover width by
/// weight.
public struct HStack<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// Cross-axis placement of children shorter than the stack.
    public var alignment: VerticalAlignment
    /// Cells inserted between adjacent children — not before the first or
    /// after the last.
    public var spacing: Int
    /// The stacked children; builder containers flatten into a plain
    /// child list at render time.
    public var content: Content

    /// Creates a horizontal stack; by default children are vertically
    /// centered with no spacing.
    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    /// Compiles to a horizontal `.stack`, flattening tuple/loop sentinels
    /// into direct children.
    public func render(in context: BuildContext) -> RenderNode {
        .stack(
            axis: .horizontal,
            spacing: spacing,
            alignment: Alignment(horizontal: .leading, vertical: alignment),
            children: flattenChildren(content.render(in: context.child(0)))
        )
    }
}

/// Layers children back to front in shared bounds; later children draw on
/// top and win pointer hit-tests. Every alignment (including `.topLeading`)
/// stays layered: the ViewBuilder flatten sentinel is the distinct
/// ``RenderNode/group(children:)`` case, so `flattenChildren` never unpacks
/// a `ZStack`.
public struct ZStack<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// Placement of each child within the stack's bounds when the child
    /// measures smaller.
    public var alignment: Alignment
    /// The layered children, first is bottommost; builder containers
    /// flatten into a plain child list at render time.
    public var content: Content

    /// Creates an overlay stack; children are centered by default.
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    /// Compiles to an `.overlay` node with the flattened children.
    public func render(in context: BuildContext) -> RenderNode {
        .overlay(
            alignment: alignment,
            children: flattenChildren(content.render(in: context.child(0)))
        )
    }
}

/// Flexible blank space: absorbs leftover main-axis length in the
/// enclosing stack (flex weight 1). Outside a stack it measures
/// `minLength` on both axes.
public struct Spacer: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Main-axis floor in cells the spacer never shrinks below, even when
    /// the stack is over-full.
    public var minLength: Int
    /// Creates a spacer that can collapse to nothing unless `minLength`
    /// says otherwise.
    public init(minLength: Int = 0) { self.minLength = minLength }
    /// Compiles to a `.spacer` node; the stack layout distributes leftover
    /// space to it.
    public func render(in context: BuildContext) -> RenderNode {
        .spacer(minLength: minLength)
    }
}

/// A separator rule drawn in gray. Orientation is chosen from the
/// laid-out frame's aspect — vertical only when height exceeds width —
/// which normally matches the enclosing stack's axis; a square frame
/// (for example a divider in a one-row `HStack`) renders the horizontal
/// glyph.
public struct Divider: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Creates a rule; it has no configuration — style and orientation are
    /// decided by context.
    public init() {}
    /// Compiles to a `.divider` node in gray.
    public func render(in context: BuildContext) -> RenderNode {
        // Axis-resolved rule: the layout engine gives it 1 cell on the
        // stack's main axis and full length on the cross axis; backends
        // pick '─' or '│' by frame aspect.
        .divider(style: TextStyle(foreground: .gray))
    }
}

// MARK: - Button

/// A focusable action target. The owning `FrameHost` invokes `action` on
/// Enter/Space while focused or on pointer press; while focused a bold
/// black-on-cyan style wraps the label, fully recoloring labels that use
/// default styling — a label that sets its own foreground or background
/// keeps it, because deeper styles win through `TextStyle.merging`.
/// Disabled buttons render dimmed, register no action, and leave the
/// focus order.
public struct Button<Label: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// The button's visual content; drawn bold, and highlighted while
    /// focused.
    public var label: Label
    /// Invoked by the owning host each time the button is activated;
    /// typically mutates observed state, which marks the host dirty.
    public var action: @Sendable () -> Void

    /// Creates a button from an action and a label subtree.
    public init(action: @escaping @Sendable () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    /// Registers `action` with the host and compiles to a focusable
    /// `.interactive` node; when the environment is disabled it skips
    /// registration and renders dimmed and non-focusable.
    public func render(in context: BuildContext) -> RenderNode {
        let id = context.id
        guard context.environment.isEnabled else {
            // Disabled: no action registered, not focusable, dimmed.
            return .interactive(
                id: id,
                focusable: false,
                child: .styled(
                    TextStyle(foreground: .gray, attributes: [.dim]),
                    child: label.render(in: context.child(0))
                )
            )
        }
        context.registerAction(id, action)
        let focused = context.environment.focusedID == id
        let style: TextStyle =
            focused
            ? TextStyle(foreground: .black, background: .cyan, attributes: [.bold])
            : TextStyle(attributes: [.bold])
        return .interactive(
            id: id,
            focusable: true,
            child: .styled(style, child: label.render(in: context.child(0)))
        )
    }
}

extension Button where Label == Text {
    /// Creates a button whose label is `title` padded with one space on
    /// each side, so the focus highlight reads as a block.
    public init(_ title: String, action: @escaping @Sendable () -> Void) {
        self.init(action: action) { Text(" \(title) ") }
    }
}

// MARK: - Form controls

/// Editable text bound to external storage, rendered as a single row.
/// While focused, character key events append (the field itself does not
/// filter control characters — a host that delivers `"\n"`, such as the
/// C embedding entry point, embeds it verbatim), backspace removes the
/// last character, and Delete clears the field; there is no cursor
/// movement. Every keystroke writes through the binding immediately.
public struct TextField: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Shown dimmed while the bound text is empty; never written back to
    /// the binding.
    public var placeholder: String
    /// Storage for the field's contents; edits write through on every
    /// keystroke.
    public var text: Binding<String>

    /// Creates a field editing `text`, with an optional placeholder for
    /// the empty state.
    public init(_ placeholder: String = "", text: Binding<String>) {
        self.placeholder = placeholder
        self.text = text
    }

    /// Registers a key handler when enabled and compiles to an
    /// `.interactive` node styled for the empty, disabled, and focused
    /// states.
    public func render(in context: BuildContext) -> RenderNode {
        let id = context.id
        let enabled = context.environment.isEnabled
        let focused = context.environment.focusedID == id
        if enabled {
            let binding = text
            context.registerKeyHandler(id) { key in
                switch key {
                case .character(let character):
                    var value = binding.wrappedValue
                    value.append(character)
                    binding.wrappedValue = value
                    return true
                case .backspace:
                    var value = binding.wrappedValue
                    guard !value.isEmpty else { return false }
                    value.removeLast()
                    binding.wrappedValue = value
                    return true
                case .delete:
                    binding.wrappedValue = ""
                    return true
                default:
                    return false
                }
            }
        }
        let value = text.wrappedValue
        let visible = value.isEmpty ? placeholder : value
        var style = TextStyle()
        if value.isEmpty { style.attributes.insert(.dim) }
        if !enabled { style.foreground = .gray; style.attributes.insert(.dim) }
        if focused { style.background = .cyan; style.foreground = .black }
        return .interactive(
            id: id,
            focusable: enabled,
            child: .styled(style, child: .text(" \(visible) ", style: .plain))
        )
    }
}

/// A checkbox-style boolean control rendered as a `Button` labelled
/// `[x]`/`[ ]`; activation flips the binding.
public struct Toggle: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Text drawn after the checkbox glyph.
    public var title: String
    /// Bound flag flipped on each activation; the glyph tracks it.
    public var isOn: Binding<Bool>

    /// Creates a toggle controlling `isOn`.
    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }

    /// Delegates to `Button` under the same identity, so a toggle focuses
    /// and activates exactly like a button.
    public func render(in context: BuildContext) -> RenderNode {
        let binding = isOn
        return Button(action: { binding.wrappedValue.toggle() }) {
            Text("[\(binding.wrappedValue ? "x" : " ")] \(title)")
        }.render(in: context)
    }
}

/// `Toggle` under its checkbox name — the rendered control is identical.
public typealias Checkbox = Toggle

/// Read-only progress indicator: a fixed 20-cell bar plus a percentage.
/// Finite fractions clamp to 0...1; a non-finite `value` degrades to the
/// empty 0% bar.
public struct ProgressView: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Progress in the same units as `total`; finite out-of-range values
    /// clamp to the 0%/100% ends, and non-finite values render as 0%.
    public var value: Double
    /// The amount that maps to 100%; non-positive totals render as 0%.
    public var total: Double
    /// Optional prefix drawn before the bar.
    public var label: String?

    /// Creates a progress bar showing `value` out of `total` (a fraction
    /// of 1 by default).
    public init(value: Double, total: Double = 1, label: String? = nil) {
        self.value = value
        self.total = total
        self.label = label
    }

    /// Compiles to a single `.text` node — bar, glyphs, and percentage are
    /// all plain characters in the inherited style.
    public func render(in context: BuildContext) -> RenderNode {
        let fraction = total > 0 ? min(1, max(0, value / total)) : 0
        let filled = Int(fraction * 20 + 0.5)
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
        let percent = Int(fraction * 100 + 0.5)
        return .text("\(label.map { "\($0) " } ?? "")[\(bar)] \(percent)%", style: context.inheritedStyle)
    }
}

/// A zero-spacing, top-leading vertical stack of its rows — presentation
/// only; scrolling and selection are not provided.
public struct List<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// The row content; builder containers flatten into a plain child
    /// list at render time.
    public var content: Content

    /// Creates a list from a row builder.
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    /// Compiles to a vertical `.stack` with zero spacing, top-leading
    /// aligned.
    public func render(in context: BuildContext) -> RenderNode {
        .stack(
            axis: .vertical,
            spacing: 0,
            alignment: .topLeading,
            children: flattenChildren(content.render(in: context.child(0)))
        )
    }
}

// MARK: - Modifiers

/// Output of `padding(_:)` — inserts empty cells around its content.
/// Public only as a modifier return type; not meant to be built directly.
public struct _Padded<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Cells of blank space added on each edge of the content.
    public var insets: EdgeInsets
    /// The wrapped view.
    public var content: Content
    /// Compiles to a `.padding` node; the layout engine shrinks the
    /// child's bounds by `insets`.
    public func render(in context: BuildContext) -> RenderNode {
        .padding(insets, child: content.render(in: context.child(0)))
    }
}

/// Output of `border(_:color:title:)` — draws a box-glyph frame one cell
/// thick around its content. Public only as a modifier return type.
public struct _Bordered<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Glyph set for the frame (single, double, rounded, heavy, ascii).
    public var style: BorderStyle
    /// Color and attributes the frame glyphs are drawn with.
    public var textStyle: TextStyle
    /// Optional caption. The measure pass reserves `displayWidth + 4`
    /// cells for it, but the painter draws it only when the laid-out frame
    /// is strictly wider than that; at exactly the natural width the
    /// reserved top-edge space stays blank.
    public var title: String?
    /// The wrapped view; laid out inset by one cell on every edge.
    public var content: Content
    /// Compiles to a `.border` node around the rendered content.
    public func render(in context: BuildContext) -> RenderNode {
        .border(
            style, style: textStyle, title: title,
            child: content.render(in: context.child(0))
        )
    }
}

/// Output of `frame(width:height:alignment:)` — fixes one or both axes to
/// exact cell sizes. Public only as a modifier return type.
public struct _Framed<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Exact width in cells, or `nil` to adopt the child's measured width.
    public var width: Int?
    /// Exact height in cells, or `nil` to adopt the child's measured height.
    public var height: Int?
    /// Placement of the child when the frame is larger than the child's
    /// measured size.
    public var alignment: Alignment
    /// The wrapped view.
    public var content: Content
    /// Compiles to a `.frame` node around the rendered content.
    public func render(in context: BuildContext) -> RenderNode {
        .frame(
            width: width, height: height, alignment: alignment,
            child: content.render(in: context.child(0))
        )
    }
}

/// Output of the min/max `frame` modifier — constrains each axis between
/// bounds. A `.max` maximum makes the frame greedy (flex weight 1 in
/// stacks). Public only as a modifier return type.
public struct _FlexFramed<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Width floor in cells; `nil` imposes no minimum.
    public var minWidth: Int?
    /// Width ceiling in cells; `nil` imposes no maximum, `.max` expands to
    /// fill the proposal.
    public var maxWidth: Int?
    /// Height floor in cells; `nil` imposes no minimum.
    public var minHeight: Int?
    /// Height ceiling in cells; `nil` imposes no maximum, `.max` expands to
    /// fill the proposal.
    public var maxHeight: Int?
    /// Placement of the child when the frame ends up larger than the
    /// child's measured size.
    public var alignment: Alignment
    /// The wrapped view.
    public var content: Content
    /// Compiles to a `.flexFrame` node around the rendered content.
    public func render(in context: BuildContext) -> RenderNode {
        .flexFrame(
            minWidth: minWidth, maxWidth: maxWidth,
            minHeight: minHeight, maxHeight: maxHeight,
            alignment: alignment,
            child: content.render(in: context.child(0))
        )
    }
}

/// Output of `foregroundColor(_:)` / `style(_:)` — merges a style over the
/// subtree's inherited style. Public only as a modifier return type.
public struct _Styled<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Merged over the inherited style for the whole subtree; non-default
    /// fields win, attributes accumulate.
    public var style: TextStyle
    /// The wrapped view.
    public var content: Content
    /// Compiles to a `.styled` node and threads the merged style through
    /// the build context so descendants inherit it.
    public func render(in context: BuildContext) -> RenderNode {
        var ctx = context
        ctx.inheritedStyle = ctx.inheritedStyle.merging(style)
        return .styled(style, child: content.render(in: ctx.child(0)))
    }
}

/// Output of `background(_:)` — fills the content's frame with a color
/// behind it. Public only as a modifier return type.
public struct _Background<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Fill painted behind the content across the node's frame.
    public var color: Color
    /// The wrapped view.
    public var content: Content
    /// Compiles to a `.background` node around the rendered content.
    public func render(in context: BuildContext) -> RenderNode {
        .background(color, child: content.render(in: context.child(0)))
    }
}

extension View {
    /// Adds per-edge blank space around this view.
    public func padding(_ insets: EdgeInsets) -> _Padded<Self> {
        _Padded(insets: insets, content: self)
    }
    /// Adds uniform blank space on all four edges — one cell by default.
    public func padding(_ all: Int = 1) -> _Padded<Self> {
        _Padded(insets: EdgeInsets(all: all), content: self)
    }
    /// Draws a one-cell box-glyph border in `color` around this view,
    /// reserving room for `title` in the top edge when given.
    public func border(
        _ style: BorderStyle = .single,
        color: Color = .default,
        title: String? = nil
    ) -> _Bordered<Self> {
        _Bordered(
            style: style,
            textStyle: TextStyle(foreground: color),
            title: title,
            content: self
        )
    }
    /// Fixes the given axes to exact cell sizes; `nil` axes track the
    /// content. `alignment` places the content inside the fixed frame.
    public func frame(
        width: Int? = nil, height: Int? = nil, alignment: Alignment = .center
    ) -> _Framed<Self> {
        _Framed(width: width, height: height, alignment: alignment, content: self)
    }
    /// Constrains this view between per-axis bounds. Passing `.max` as a
    /// maximum makes the view greedy — it absorbs leftover stack space
    /// like `Spacer`.
    public func frame(
        minWidth: Int? = nil, maxWidth: Int? = nil,
        minHeight: Int? = nil, maxHeight: Int? = nil,
        alignment: Alignment = .center
    ) -> _FlexFramed<Self> {
        _FlexFramed(
            minWidth: minWidth, maxWidth: maxWidth,
            minHeight: minHeight, maxHeight: maxHeight,
            alignment: alignment, content: self
        )
    }
    /// Sets the text color for this subtree; deeper non-default colors
    /// still win.
    public func foregroundColor(_ c: Color) -> _Styled<Self> {
        _Styled(style: TextStyle(foreground: c), content: self)
    }
    /// Fills this view's frame with `c` behind its content.
    public func background(_ c: Color) -> _Background<Self> {
        _Background(color: c, content: self)
    }
    /// Merges an arbitrary `TextStyle` over this subtree's inherited
    /// style — the general form of `foregroundColor(_:)`.
    public func style(_ s: TextStyle) -> _Styled<Self> {
        _Styled(style: s, content: self)
    }
}

// MARK: - Environment transforms

/// Applies a mutation to the environment for an entire subtree.
public struct _EnvTransformed<Content: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// Applied to a copy of the environment before the subtree builds;
    /// enclosing scopes are unaffected.
    public var transform: @Sendable (inout EnvironmentValues) -> Void
    /// The subtree that builds under the mutated environment.
    public var content: Content

    /// Wraps `content` so it builds under the transformed environment.
    public init(
        transform: @escaping @Sendable (inout EnvironmentValues) -> Void,
        content: Content
    ) {
        self.transform = transform
        self.content = content
    }

    /// Renders `content` in the mutated environment; no node of its own —
    /// the transform exists only during the build pass.
    public func render(in context: BuildContext) -> RenderNode {
        var ctx = context
        transform(&ctx.environment)
        return content.render(in: ctx)
    }
}

extension View {
    /// Disable all interactive descendants: buttons stop registering
    /// actions, drop out of the focus order, and draw dimmed.
    public func disabled(_ disabled: Bool = true) -> _EnvTransformed<Self> {
        _EnvTransformed(transform: { $0.isEnabled = !disabled }, content: self)
    }

    /// Arbitrary environment mutation for a subtree.
    public func environment(
        _ transform: @escaping @Sendable (inout EnvironmentValues) -> Void
    ) -> _EnvTransformed<Self> {
        _EnvTransformed(transform: transform, content: self)
    }
}
