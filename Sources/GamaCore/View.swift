//  View.swift — GamaCore
//  Declarative layer. Fully generic — user code never touches `any View`,
//  which keeps the whole declarative layer Embedded-Swift compatible.

/// Build context threaded through the view → RenderNode compilation pass.
/// Carries identity path and inherited style. Value type, no globals.
public struct BuildContext: Sendable {
    public var id: NodeID
    public var inheritedStyle: TextStyle
    public var environment: EnvironmentValues
    /// Registers an interaction with the `FrameHost` that owns this build.
    /// The default is a no-op so views can still be rendered in isolation.
    public var registerAction: @Sendable (NodeID, @escaping @Sendable () -> Void) -> Void
    /// Registers focused text/key editing for the owning host.
    public var registerKeyHandler: @Sendable (
        NodeID, @escaping @Sendable (Key) -> Bool
    ) -> Void

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

    public func child(_ index: Int) -> BuildContext {
        var c = self
        c.id = id.child(index)
        return c
    }
}

/// Minimal environment — a fixed-key value bag (Embedded-safe: no
/// reflection, no type-erased dictionaries).
public struct EnvironmentValues: Sendable {
    public var isEnabled: Bool = true
    public var focusedID: NodeID? = nil
    public init() {}
}

public protocol View: Sendable {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
    /// Compile this view into render IR. Primitives override; composites
    /// inherit the default that recurses into `body`.
    func render(in context: BuildContext) -> RenderNode
}

extension View {
    public func render(in context: BuildContext) -> RenderNode {
        body.render(in: context.child(0))
    }
}

/// Terminal case for primitives whose `body` is never called.
public struct Never_: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public func render(in context: BuildContext) -> RenderNode { .empty }
}

// MARK: - Result builder

@resultBuilder
public enum ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }

    public static func buildBlock<V: View>(_ v: V) -> V { v }

    public static func buildBlock<each V: View>(_ v: repeat each V) -> TupleView<repeat each V> {
        TupleView(repeat each v)
    }

    public static func buildOptional<V: View>(_ v: V?) -> ConditionalView<V, EmptyView> {
        v.map { .first($0) } ?? .second(EmptyView())
    }

    public static func buildEither<T: View, F: View>(first: T) -> ConditionalView<T, F> {
        .first(first)
    }

    public static func buildEither<T: View, F: View>(second: F) -> ConditionalView<T, F> {
        .second(second)
    }

    public static func buildArray<V: View>(_ vs: [V]) -> ForEachView<V> {
        ForEachView(views: vs)
    }

    public static func buildExpression<V: View>(_ v: V) -> V { v }
}

// MARK: - Structural views

public struct EmptyView: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public init() {}
    public func render(in context: BuildContext) -> RenderNode { .empty }
}

public struct TupleView<each V: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public let content: (repeat each V)

    public init(_ content: repeat each V) {
        self.content = (repeat each content)
    }

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

public enum ConditionalView<T: View, F: View>: View {
    case first(T)
    case second(F)

    public typealias Body = Never_
    public var body: Never_ { Never_() }

    public func render(in context: BuildContext) -> RenderNode {
        switch self {
        case .first(let v): return v.render(in: context.child(0))
        case .second(let v): return v.render(in: context.child(1))
        }
    }
}

public struct ForEachView<V: View>: View {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public let views: [V]
    public init(views: [V]) { self.views = views }

    public func render(in context: BuildContext) -> RenderNode {
        .group(
            children: views.enumerated().map { i, v in v.render(in: context.child(i)) }
        )
    }
}

public struct ForEach<Data: RandomAccessCollection & Sendable, Content: View>: View
where Data.Index == Int {
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public let data: Data
    public let content: @Sendable (Data.Element) -> Content

    public init(_ data: Data, @ViewBuilder content: @escaping @Sendable (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

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
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    public let data: Data
    public let identity: @Sendable (Data.Element) -> NodeID
    public let content: @Sendable (Data.Element) -> Content

    public init(
        _ data: Data,
        id: @escaping @Sendable (Data.Element) -> NodeID,
        @ViewBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) {
        self.data = data
        self.identity = id
        self.content = content
    }

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
