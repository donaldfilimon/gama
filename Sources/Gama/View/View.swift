import Foundation

/// A type that represents part of your app's user interface and provides
/// modifiers that you use to configure views.
///
/// You create custom views by declaring types that conform to the `View`
/// protocol. Implement the required `body` computed property to provide the
/// content for your custom view.
///
/// Swift 6.2: Enhanced with improved Sendable conformance and isolation
public protocol View: @retroactive Sendable {
    /// The type of view representing the body of this view.
    ///
    /// When you create a custom view, Swift infers this type from your
    /// implementation of the required `body` property.
    associatedtype Body: View = Never
    
    /// The content and behavior of the view.
    ///
    /// When you implement a custom view, you must implement a computed
    /// `body` property to provide the content for your view. Return a view
    /// that's composed of built-in views that Gama provides, plus other
    /// composite views that you've already defined.
    @ViewBuilder var body: Self.Body { get }
}

/// Extension to support views with Never body
extension View where Body == Never {
    public var body: Never {
        fatalError("This view should not have its body accessed")
    }
}

/// A view that contains no content.
///
/// `EmptyView` can be used as a placeholder view when you need to
/// conditionally hide content.
public struct EmptyView: View {
    public typealias Body = Never
    
    public init() {}
}

/// View identity for efficient updates.
public struct ViewID: Hashable, Sendable {
    private let id: UUID
    
    public init() {
        self.id = UUID()
    }
    
    public init(_ id: UUID) {
        self.id = id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ViewID, rhs: ViewID) -> Bool {
        lhs.id == rhs.id
    }
}

/// View lifecycle events
public protocol ViewLifecycle {
    /// Called when the view appears on screen.
    func onAppear()
    
    /// Called when the view disappears from screen.
    func onDisappear()
}

/// Extension to provide default implementations for ViewLifecycle
extension ViewLifecycle {
    public func onAppear() {}
    public func onDisappear() {}
}

/// View preferences for passing data up the view hierarchy
public protocol PreferenceKey: Sendable {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}

extension PreferenceKey {
    public static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue()
    }
}

/// View preference values storage
public struct PreferenceValues: Sendable {
    private var values: [ObjectIdentifier: Any] = [:]
    
    public subscript<Key: PreferenceKey>(_ key: Key.Type) -> Key.Value {
        get {
            values[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }
    
    public mutating func merge(_ other: PreferenceValues) {
        for (key, value) in other.values {
            values[key] = value
        }
    }
}