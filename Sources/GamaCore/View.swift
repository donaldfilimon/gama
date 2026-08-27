//  View.swift — GamaCore
//  Declarative layer. Fully generic — user code never touches `any View`,
//  which keeps the whole declarative layer Embedded-Swift compatible.

/// Build context threaded through the view → RenderNode compilation pass.
/// Carries identity path and inherited style. Value type, no globals.
public struct BuildContext: Sendable {
    /// Identity of the node being built; children derive theirs through
    /// `child(_:)`, so the path stays stable across rebuilds.
    public var id: NodeID
    /// Style accumulated from enclosing `.styled` modifiers; primitives
    /// merge their own style over it when they compile.
    public var inheritedStyle: TextStyle
    /// Environment in effect for this subtree (enabled state, focus).
    public var environment: EnvironmentValues
    /// Registers an interaction with the `FrameHost` that owns this build.
    /// The default is a no-op so views can still be rendered in isolation.
    public var registerAction: @Sendable (NodeID, @escaping @Sendable () -> Void) -> Void
    /// Registers focused text/key editing for the owning host.
    public var registerKeyHandler: @Sendable (
        NodeID, @escaping @Sendable (Key) -> Bool
    ) -> Void

    /// Creates a build context. Every parameter defaults to the isolated
    /// case — root identity, plain style, fresh environment, no-op
    /// registration — so a view can be compiled without any host.
    public init(
        id: NodeID = .root,
        inheritedStyle: TextStyle = .plain,
        environment: EnvironmentValues = EnvironmentValues(),
        registerAction: @escaping @Sendable (NodeID, @escaping @Sendable () -> Void) -> Void = { _, _ in },
        registerKeyHandler: @escaping @Sendable (
            NodeID, @escaping @Sendable (Key) -> Bool
        ) -> Void = { _, _ in }
    ) {
        self.id = id
        self.inheritedStyle = inheritedStyle
        self.environment = environment
        self.registerAction = registerAction
        self.registerKeyHandler = registerKeyHandler
    }

    /// The context for the child at `index`: identity descends one step;
    /// style, environment, and registration callbacks are inherited.
    public func child(_ index: Int) -> BuildContext {
        var c = self
        c.id = id.child(index)
        return c
    }
}

/// Minimal environment — a fixed-key value bag (Embedded-safe: no
/// reflection, no type-erased dictionaries).
public struct EnvironmentValues: Sendable {
    /// When `false`, interactive descendants render dimmed, skip action
    /// registration, and drop out of the focus order.
    public var isEnabled: Bool = true
    /// Identity of the currently focused node, set by the owning
    /// `FrameHost` before each build; `nil` when nothing has focus.
    public var focusedID: NodeID? = nil
    /// Creates the default environment: enabled, nothing focused.
    public init() {}
}

/// A declarative UI element. Composites describe themselves through
/// `body`; primitives use `Never_` as `Body` and compile directly in
/// `render(in:)`. The protocol stays fully generic — no `any View`
/// anywhere — which is what keeps the layer Embedded-Swift compatible.
public protocol View: Sendable {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
    /// Compile this view into render IR. Primitives override; composites
    /// inherit the default that recurses into `body`.
    func render(in context: BuildContext) -> RenderNode
}

extension View {
    /// Default for composites: recurse into `body` under a derived child
    /// identity.
    public func render(in context: BuildContext) -> RenderNode {
        body.render(in: context.child(0))
    }
}

/// Terminal case for primitives whose `body` is never called.
public struct Never_: View {
    /// Self-referential terminator: `Never_` is its own `Body`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Compiles to `.empty`; unreachable for well-formed primitives, which
    /// never call into their `body`.
    public func render(in context: BuildContext) -> RenderNode { .empty }
}

// MARK: - Result builder

/// Result builder behind `@ViewBuilder` closures. Emits concrete generic
/// containers (`TupleView`, `ConditionalView`, `ForEachView`) rather than
/// erased types, preserving the no-existential rule.
@resultBuilder
public enum ViewBuilder {
    /// An empty closure produces `EmptyView`.
    public static func buildBlock() -> EmptyView { EmptyView() }

    /// A single child passes through unchanged — no wrapper node.
    public static func buildBlock<V: View>(_ v: V) -> V { v }

    /// Multiple statements collect into a `TupleView` via parameter packs.
    public static func buildBlock<each V: View>(_ v: repeat each V) -> TupleView<repeat each V> {
        TupleView(repeat each v)
    }

    /// `if` without `else`: the absent branch becomes `EmptyView`, keeping
    /// both branches distinct identities.
    public static func buildOptional<V: View>(_ v: V?) -> ConditionalView<V, EmptyView> {
        v.map { .first($0) } ?? .second(EmptyView())
    }

    /// The `if` branch of an `if`/`else`, kept identity-distinct from the
    /// `else` branch.
    public static func buildEither<T: View, F: View>(first: T) -> ConditionalView<T, F> {
        .first(first)
    }

    /// The `else` branch of an `if`/`else`, kept identity-distinct from
    /// the `if` branch.
    public static func buildEither<T: View, F: View>(second: F) -> ConditionalView<T, F> {
        .second(second)
    }

    /// `for` loops collect into a `ForEachView`; children are identified
    /// by position, so prefer `IdentifiedForEach` for insert/remove flows.
    public static func buildArray<V: View>(_ vs: [V]) -> ForEachView<V> {
        ForEachView(views: vs)
    }

    /// Passes view expressions through so plain literals type-check in
    /// builder position.
    public static func buildExpression<V: View>(_ v: V) -> V { v }
}

// MARK: - Structural views

/// Renders nothing and measures zero cells; the `buildOptional` absent
/// branch and the empty-block result.
public struct EmptyView: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// Creates a view that renders nothing.
    public init() {}
    /// Compiles to `.empty`, which containers drop during flattening.
    public func render(in context: BuildContext) -> RenderNode { .empty }
}

/// Fixed-arity group produced by `ViewBuilder` for multi-statement blocks.
/// Renders as the dedicated ``RenderNode/group(children:)`` sentinel that
/// stacking containers unpack via `flattenChildren(_:)` — never as an
/// overlay, so it cannot collide with `ZStack`.
public struct TupleView<each V: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// The grouped child views, in declaration order.
    public let content: (repeat each V)

    /// Groups the given views; normally called only by `ViewBuilder`.
    public init(_ content: repeat each V) {
        self.content = (repeat each content)
    }

    /// Renders each element under a positional child identity and wraps
    /// the results in the flattening sentinel.
    public func render(in context: BuildContext) -> RenderNode {
        var children: [RenderNode] = []
        var index = 0
        for view in repeat each content {
            children.append(view.render(in: context.child(index)))
            index += 1
        }
        // A bare tuple flattens into its parent container via `.group`.
        return .group(children: children)
    }
}

/// Either/or container from `if`/`else` in a builder. The branches render
/// under different child identities, so switching branches also switches
/// identity — focus and actions do not leak across.
public enum ConditionalView<T: View, F: View>: View {
    /// The `if` (true) branch.
    case first(T)
    /// The `else` (false) branch — `EmptyView` for a bare `if`.
    case second(F)

    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// Renders whichever branch is active, under that branch's own child
    /// identity (0 for `first`, 1 for `second`).
    public func render(in context: BuildContext) -> RenderNode {
        switch self {
        case .first(let v): return v.render(in: context.child(0))
        case .second(let v): return v.render(in: context.child(1))
        }
    }
}

/// Positional collection container produced by `buildArray` for `for`
/// loops. Children are identified by index, so inserting or removing
/// shifts the identity of everything after the change — use
/// `IdentifiedForEach` when that matters.
public struct ForEachView<V: View>: View {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// The element views, rendered in order and identified by position.
    public let views: [V]
    /// Wraps an already-built array of views; normally called only by
    /// `ViewBuilder`.
    public init(views: [V]) { self.views = views }

    /// Renders each element under a positional child identity, wrapped in
    /// the flattening sentinel.
    public func render(in context: BuildContext) -> RenderNode {
        .group(
            children: views.enumerated().map { i, v in v.render(in: context.child(i)) }
        )
    }
}

/// Renders one view per element of an integer-indexed collection.
/// Identity is positional (the element's index), so mutations shift
/// downstream identities — use `IdentifiedForEach` for stable identity.
public struct ForEach<Data: RandomAccessCollection & Sendable, Content: View>: View
where Data.Index == Int {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// The source collection; re-evaluated on every build pass.
    public let data: Data
    /// Produces the view for one element; called once per element per
    /// build pass.
    public let content: @Sendable (Data.Element) -> Content

    /// Creates a per-element rendering of `data`.
    public init(_ data: Data, @ViewBuilder content: @escaping @Sendable (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    /// Renders each element under a child identity derived from its index,
    /// wrapped in the flattening sentinel.
    public func render(in context: BuildContext) -> RenderNode {
        .group(
            children: data.indices.map { i in
                content(data[i]).render(in: context.child(i))
            }
        )
    }
}

/// Identity-explicit collection rendering for dynamic insert/remove flows.
public struct IdentifiedForEach<Data: RandomAccessCollection & Sendable, Content: View>: View
where Data.Index == Int {
    /// Terminates `body` recursion; this view compiles in `render(in:)`.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }
    /// The source collection; re-evaluated on every build pass.
    public let data: Data
    /// Maps an element to the stable `NodeID` its subtree renders under —
    /// this replaces positional identity entirely.
    public let identity: @Sendable (Data.Element) -> NodeID
    /// Produces the view for one element; called once per element per
    /// build pass.
    public let content: @Sendable (Data.Element) -> Content

    /// Creates a per-element rendering of `data` where each element's
    /// subtree is identified by `id(element)` rather than by position.
    public init(
        _ data: Data,
        id: @escaping @Sendable (Data.Element) -> NodeID,
        @ViewBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) {
        self.data = data
        self.identity = id
        self.content = content
    }

    /// Renders each element under its element-derived identity (not its
    /// index), wrapped in the flattening sentinel.
    public func render(in context: BuildContext) -> RenderNode {
        .group(
            children: data.indices.map { index in
                let element = data[index]
                var childContext = context
                childContext.id = identity(element)
                return content(element).render(in: childContext)
            }
        )
    }
}

/// Flatten the tuple/forEach sentinel so containers get a plain child list.
/// Only ``RenderNode/group(children:)`` unpacks; a ``ZStack`` overlay does not.
@inlinable
public func flattenChildren(_ node: RenderNode) -> [RenderNode] {
    if case .group(let children) = node {
        return children.flatMap(flattenChildren)
    }
    if case .empty = node { return [] }
    return [node]
}
