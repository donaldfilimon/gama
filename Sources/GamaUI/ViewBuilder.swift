// ViewBuilder.swift — Result builder for composing child views
// Part of GamaUI

// MARK: - ViewBuilder

/// A result builder that constructs views from closures.
///
/// `ViewBuilder` enables SwiftUI-style declarative syntax for composing
/// multiple child views within container types like `VStack` and `HStack`.
@resultBuilder
public struct ViewBuilder: Sendable {
    /// Builds an empty block with no views.
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    /// Builds a single view expression.
    public static func buildBlock<V: View>(_ component: V) -> V {
        component
    }

    /// Builds a tuple of two views.
    public static func buildBlock<V0: View, V1: View>(
        _ v0: V0, _ v1: V1
    ) -> TupleView2<V0, V1> {
        TupleView2(v0, v1)
    }

    /// Builds a tuple of three views.
    public static func buildBlock<V0: View, V1: View, V2: View>(
        _ v0: V0, _ v1: V1, _ v2: V2
    ) -> TupleView3<V0, V1, V2> {
        TupleView3(v0, v1, v2)
    }

    /// Builds a tuple of four views.
    public static func buildBlock<V0: View, V1: View, V2: View, V3: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3
    ) -> TupleView4<V0, V1, V2, V3> {
        TupleView4(v0, v1, v2, v3)
    }

    /// Builds a tuple of five views.
    public static func buildBlock<V0: View, V1: View, V2: View, V3: View, V4: View>(
        _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4
    ) -> TupleView5<V0, V1, V2, V3, V4> {
        TupleView5(v0, v1, v2, v3, v4)
    }

    /// Builds a conditional view for `if` statements.
    public static func buildEither<TrueContent: View, FalseContent: View>(
        first component: TrueContent
    ) -> ConditionalView<TrueContent, FalseContent> {
        .trueContent(component)
    }

    /// Builds a conditional view for `else` branches.
    public static func buildEither<TrueContent: View, FalseContent: View>(
        second component: FalseContent
    ) -> ConditionalView<TrueContent, FalseContent> {
        .falseContent(component)
    }

    /// Builds an optional view.
    public static func buildOptional<V: View>(_ component: V?) -> OptionalView<V> {
        OptionalView(component)
    }
}

// MARK: - Tuple Views

/// A view that holds two child views.
public struct TupleView2<V0: View, V1: View>: View, Sendable {
    public typealias Body = Never

    /// The first child view.
    public let v0: V0
    /// The second child view.
    public let v1: V1

    /// Creates a tuple view from two child views.
    public init(_ v0: V0, _ v1: V1) {
        self.v0 = v0
        self.v1 = v1
    }

    public var body: Never {
        fatalError("TupleView2.body should never be called")
    }
}

/// A view that holds three child views.
public struct TupleView3<V0: View, V1: View, V2: View>: View, Sendable {
    public typealias Body = Never

    public let v0: V0
    public let v1: V1
    public let v2: V2

    public init(_ v0: V0, _ v1: V1, _ v2: V2) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
    }

    public var body: Never {
        fatalError("TupleView3.body should never be called")
    }
}

/// A view that holds four child views.
public struct TupleView4<V0: View, V1: View, V2: View, V3: View>: View, Sendable {
    public typealias Body = Never

    public let v0: V0
    public let v1: V1
    public let v2: V2
    public let v3: V3

    public init(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
    }

    public var body: Never {
        fatalError("TupleView4.body should never be called")
    }
}

/// A view that holds five child views.
public struct TupleView5<V0: View, V1: View, V2: View, V3: View, V4: View>: View, Sendable {
    public typealias Body = Never

    public let v0: V0
    public let v1: V1
    public let v2: V2
    public let v3: V3
    public let v4: V4

    public init(_ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
        self.v3 = v3
        self.v4 = v4
    }

    public var body: Never {
        fatalError("TupleView5.body should never be called")
    }
}

// MARK: - Conditional Views

/// A view that represents one of two possible views.
public enum ConditionalView<TrueContent: View, FalseContent: View>: View, Sendable {
    case trueContent(TrueContent)
    case falseContent(FalseContent)

    public typealias Body = Never

    public var body: Never {
        fatalError("ConditionalView.body should never be called")
    }
}

/// A view that wraps an optional view.
public struct OptionalView<Wrapped: View>: View, Sendable {
    public typealias Body = Never

    /// The wrapped view, or `nil`.
    public let wrapped: Wrapped?

    /// Creates an optional view.
    public init(_ wrapped: Wrapped?) {
        self.wrapped = wrapped
    }

    public var body: Never {
        fatalError("OptionalView.body should never be called")
    }
}
