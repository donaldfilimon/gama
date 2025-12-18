import Foundation

/// A custom parameter attribute that constructs views from closures.
///
/// You typically use `@ViewBuilder` as a parameter attribute for child
/// view-producing closure parameters, allowing those closures to provide
/// multiple child views. For example, the following `Stack` accepts a
/// closure that produces one or more views via the view builder:
///
/// ```swift
/// struct Stack<Content: View>: View {
///     @ViewBuilder var content: () -> Content
///     var body: some View {
///         content()
///     }
/// }
/// ```
///
/// Clients of `Stack` can then use multiple-statement closures to provide
/// several child views at once:
///
/// ```swift
/// Stack {
///     Text("First")
///     Text("Second")
///     Text("Third")
/// }
/// ```
@resultBuilder
public struct ViewBuilder {
    /// Builds an empty view from a block containing no statements.
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }
    
    /// Passes a single view written as a child view through unmodified.
    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }
    
    /// Builds a view from two child views.
    public static func buildBlock<C0: View, C1: View>(
        _ c0: C0, _ c1: C1
    ) -> TupleView<(C0, C1)> {
        TupleView((c0, c1))
    }
    
    /// Builds a view from three child views.
    public static func buildBlock<C0: View, C1: View, C2: View>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleView<(C0, C1, C2)> {
        TupleView((c0, c1, c2))
    }
    
    /// Builds a view from four child views.
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleView<(C0, C1, C2, C3)> {
        TupleView((c0, c1, c2, c3))
    }
    
    /// Builds a view from five child views.
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleView<(C0, C1, C2, C3, C4)> {
        TupleView((c0, c1, c2, c3, c4))
    }
    
    /// Builds a view from six child views.
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> TupleView<(C0, C1, C2, C3, C4, C5)> {
        TupleView((c0, c1, c2, c3, c4, c5))
    }
    
    /// Builds a view from seven child views.
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6
    ) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6))
    }
    
    /// Builds a view from eight child views.
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7
    ) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6, c7))
    }
    
    /// Builds a view from nine child views.
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8))
    }
    
    /// Builds a view from ten child views.
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> {
        TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9))
    }
    
    /// Provides support for "if" statements in multi-statement closures.
    public static func buildIf<Content: View>(_ content: Content?) -> Content? {
        content
    }
    
    /// Provides support for "if-else" statements in multi-statement closures.
    public static func buildEither<TrueContent: View, FalseContent: View>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(trueContent: first)
    }
    
    /// Provides support for "if-else" statements in multi-statement closures.
    public static func buildEither<TrueContent: View, FalseContent: View>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(falseContent: second)
    }
    
    /// Provides support for "for-in" loops in multi-statement closures.
    public static func buildArray<Content: View>(_ contents: [Content]) -> [Content] {
        contents
    }
    
    /// Provides support for limited availability views.
    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView {
        AnyView(content)
    }
}

/// A view that represents a tuple of views.
public struct TupleView<T>: View {
    public typealias Body = Never
    
    let value: T
    
    public init(_ value: T) {
        self.value = value
    }
}

/// A view type that conditionally shows one of two views.
public struct _ConditionalContent<TrueContent: View, FalseContent: View>: View {
    public typealias Body = Never
    
    private enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }
    
    private let storage: Storage
    
    init(trueContent: TrueContent) {
        self.storage = .trueContent(trueContent)
    }
    
    init(falseContent: FalseContent) {
        self.storage = .falseContent(falseContent)
    }
}

/// A type-erased view.
///
/// An `AnyView` allows you to hide the specific type of a view. This is
/// useful when you need to store views of different types in the same
/// container.
public struct AnyView: View {
    public typealias Body = Never
    
    private let _makeBody: () -> Any
    
    public init<V: View>(_ view: V) {
        self._makeBody = { view }
    }
}