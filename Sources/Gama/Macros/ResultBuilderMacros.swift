import Foundation

/// Swift 6.2: Enhanced result builder with variadic generics support
/// This provides better type inference and performance
@resultBuilder
public struct EnhancedViewBuilder {
    /// Builds an empty view
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }
    
    /// Passes a single view through unmodified
    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }
    
    #if swift(>=6.0)
    /// Swift 6.2: Builds a view from variadic content using variadic generics
    public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
        TupleView((repeat each content))
    }
    #else
    /// Fallback for older Swift versions
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> {
        TupleView((c0, c1))
    }
    #endif
    
    /// Provides support for "if" statements
    public static func buildIf<Content: View>(_ content: Content?) -> Content? {
        content
    }
    
    /// Provides support for "if-else" statements
    public static func buildEither<TrueContent: View, FalseContent: View>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(trueContent: first)
    }
    
    /// Provides support for "if-else" statements
    public static func buildEither<TrueContent: View, FalseContent: View>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(falseContent: second)
    }
    
    /// Provides support for "for-in" loops
    public static func buildArray<Content: View>(_ contents: [Content]) -> [Content] {
        contents
    }
    
    /// Provides support for limited availability views
    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView {
        AnyView(content)
    }
}
