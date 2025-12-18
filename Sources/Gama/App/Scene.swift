import Foundation

/// A protocol that represents a scene.
///
/// A scene is a container for a view hierarchy that you use as a content
/// root for an app or window.
public protocol Scene: Sendable {
    /// The type of scene representing the body of this scene.
    associatedtype Body: Scene = Never
    
    /// The content and behavior of the scene.
    @SceneBuilder var body: Self.Body { get }
}

/// Extension to support scenes with Never body
extension Scene where Body == Never {
    public var body: Never {
        fatalError("This scene should not have its body accessed")
    }
}

/// A scene builder for constructing scenes from closures.
@resultBuilder
public struct SceneBuilder {
    /// Builds a scene from a single scene.
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content {
        content
    }
    
    /// Builds a scene from two child scenes.
    public static func buildBlock<C0: Scene, C1: Scene>(
        _ c0: C0, _ c1: C1
    ) -> TupleScene<(C0, C1)> {
        TupleScene((c0, c1))
    }
    
    /// Provides support for "if" statements in multi-statement closures.
    public static func buildIf<Content: Scene>(_ content: Content?) -> Content? {
        content
    }
    
    /// Provides support for "if-else" statements.
    public static func buildEither<TrueContent: Scene, FalseContent: Scene>(
        first: TrueContent
    ) -> _ConditionalScene<TrueContent, FalseContent> {
        _ConditionalScene(trueContent: first)
    }
    
    /// Provides support for "if-else" statements.
    public static func buildEither<TrueContent: Scene, FalseContent: Scene>(
        second: FalseContent
    ) -> _ConditionalScene<TrueContent, FalseContent> {
        _ConditionalScene(falseContent: second)
    }
}

/// A scene that represents a tuple of scenes.
public struct TupleScene<T>: Scene {
    let value: T
    
    public init(_ value: T) {
        self.value = value
    }
}

/// A scene type that conditionally shows one of two scenes.
public struct _ConditionalScene<TrueContent: Scene, FalseContent: Scene>: Scene {
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