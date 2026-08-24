//  Primitives.swift — GamaCore

// MARK: - Text

public struct Text: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }

    public var content: String
    public var style: TextStyle

    public init(_ content: String, style: TextStyle = .plain) {
        self.content = content
        self.style = style
    }

    public func render(in context: BuildContext) -> RenderNode {
        .text(content, style: context.inheritedStyle.merging(style))
    }

    public func bold() -> Text {
        var t = self; t.style.attributes.insert(.bold); return t
    }
    public func italic() -> Text {
        var t = self; t.style.attributes.insert(.italic); return t
    }
    public func underline() -> Text {
        var t = self; t.style.attributes.insert(.underline); return t
    }
}

// MARK: - Stacks

public struct VStack<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }

    public var alignment: HorizontalAlignment
    public var spacing: Int
    public var content: Content

    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public func render(in context: BuildContext) -> RenderNode {
        .stack(
            axis: .vertical,
            spacing: spacing,
            alignment: Alignment(horizontal: alignment, vertical: .top),
            children: flattenChildren(content.render(in: context.child(0)))
        )
    }
}

public struct HStack<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }

    public var alignment: VerticalAlignment
    public var spacing: Int
    public var content: Content

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public func render(in context: BuildContext) -> RenderNode {
        .stack(
            axis: .horizontal,
            spacing: spacing,
            alignment: Alignment(horizontal: .leading, vertical: alignment),
            children: flattenChildren(content.render(in: context.child(0)))
        )
    }
}

public struct ZStack<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }

    public var alignment: Alignment
    public var content: Content

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    public func render(in context: BuildContext) -> RenderNode {
        .overlay(
            alignment: alignment,
            children: flattenChildren(content.render(in: context.child(0)))
        )
    }
}

public struct Spacer: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var minLength: Int
    public init(minLength: Int = 0) { self.minLength = minLength }
    public func render(in context: BuildContext) -> RenderNode {
        .spacer(minLength: minLength)
    }
}

public struct Divider: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public init() {}
    public func render(in context: BuildContext) -> RenderNode {
        // Axis-resolved rule: the layout engine gives it 1 cell on the
        // stack's main axis and full length on the cross axis; backends
        // pick '─' or '│' by frame aspect.
        .divider(style: TextStyle(foreground: .gray))
    }
}

// MARK: - Button

public struct Button<Label: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }

    public var label: Label
    public var action: @Sendable () -> Void

    public init(action: @escaping @Sendable () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

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
    public init(_ title: String, action: @escaping @Sendable () -> Void) {
        self.init(action: action) { Text(" \(title) ") }
    }
}

// MARK: - Form controls

public struct TextField: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var placeholder: String
    public var text: Binding<String>

    public init(_ placeholder: String = "", text: Binding<String>) {
        self.placeholder = placeholder
        self.text = text
    }

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

public struct Toggle: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var title: String
    public var isOn: Binding<Bool>

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }

    public func render(in context: BuildContext) -> RenderNode {
        let binding = isOn
        return Button(action: { binding.wrappedValue.toggle() }) {
            Text("[\(binding.wrappedValue ? "x" : " ")] \(title)")
        }.render(in: context)
    }
}

public typealias Checkbox = Toggle

public struct ProgressView: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var value: Double
    public var total: Double
    public var label: String?

    public init(value: Double, total: Double = 1, label: String? = nil) {
        self.value = value
        self.total = total
        self.label = label
    }

    public func render(in context: BuildContext) -> RenderNode {
        let fraction = total > 0 ? min(1, max(0, value / total)) : 0
        let filled = Int(fraction * 20 + 0.5)
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
        let percent = Int(fraction * 100 + 0.5)
        return .text("\(label.map { "\($0) " } ?? "")[\(bar)] \(percent)%", style: context.inheritedStyle)
    }
}

public struct List<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

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

public struct _Padded<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var insets: EdgeInsets
    public var content: Content
    public func render(in context: BuildContext) -> RenderNode {
        .padding(insets, child: content.render(in: context.child(0)))
    }
}

public struct _Bordered<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var style: BorderStyle
    public var textStyle: TextStyle
    public var title: String?
    public var content: Content
    public func render(in context: BuildContext) -> RenderNode {
        .border(
            style, style: textStyle, title: title,
            child: content.render(in: context.child(0))
        )
    }
}

public struct _Framed<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var width: Int?
    public var height: Int?
    public var alignment: Alignment
    public var content: Content
    public func render(in context: BuildContext) -> RenderNode {
        .frame(
            width: width, height: height, alignment: alignment,
            child: content.render(in: context.child(0))
        )
    }
}

public struct _FlexFramed<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var minWidth: Int?
    public var maxWidth: Int?
    public var minHeight: Int?
    public var maxHeight: Int?
    public var alignment: Alignment
    public var content: Content
    public func render(in context: BuildContext) -> RenderNode {
        .flexFrame(
            minWidth: minWidth, maxWidth: maxWidth,
            minHeight: minHeight, maxHeight: maxHeight,
            alignment: alignment,
            child: content.render(in: context.child(0))
        )
    }
}

public struct _Styled<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var style: TextStyle
    public var content: Content
    public func render(in context: BuildContext) -> RenderNode {
        var ctx = context
        ctx.inheritedStyle = ctx.inheritedStyle.merging(style)
        return .styled(style, child: content.render(in: ctx.child(0)))
    }
}

public struct _Background<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public var color: Color
    public var content: Content
    public func render(in context: BuildContext) -> RenderNode {
        .background(color, child: content.render(in: context.child(0)))
    }
}

extension View {
    public func padding(_ insets: EdgeInsets) -> _Padded<Self> {
        _Padded(insets: insets, content: self)
    }
    public func padding(_ all: Int = 1) -> _Padded<Self> {
        _Padded(insets: EdgeInsets(all: all), content: self)
    }
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
    public func frame(
        width: Int? = nil, height: Int? = nil, alignment: Alignment = .center
    ) -> _Framed<Self> {
        _Framed(width: width, height: height, alignment: alignment, content: self)
    }
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
    public func foregroundColor(_ c: Color) -> _Styled<Self> {
        _Styled(style: TextStyle(foreground: c), content: self)
    }
    public func background(_ c: Color) -> _Background<Self> {
        _Background(color: c, content: self)
    }
    public func style(_ s: TextStyle) -> _Styled<Self> {
        _Styled(style: s, content: self)
    }
}

// MARK: - Environment transforms

/// Applies a mutation to the environment for an entire subtree.
public struct _EnvTransformed<Content: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }

    public var transform: @Sendable (inout EnvironmentValues) -> Void
    public var content: Content

    public init(
        transform: @escaping @Sendable (inout EnvironmentValues) -> Void,
        content: Content
    ) {
        self.transform = transform
        self.content = content
    }

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
