// View.swift — Core View protocol and AnyView type erasure
// Part of GamaUI

// MARK: - View Protocol

/// A type that represents part of a declarative UI hierarchy.
///
/// Conforming types declare their content via the `body` property.
/// Leaf views (e.g., `Text`, `Rectangle`) return `Never` as their `Body`.
public protocol View: Sendable {
    /// The type of view representing the body of this view.
    associatedtype Body: View

    /// The content and behavior of the view.
    @ViewBuilder
    var body: Body { get }
}

// MARK: - Never as View

extension Never: View {
    /// `Never` serves as the body type for leaf views that have no children.
    public var body: Never {
        fatalError("Never.body should never be called")
    }
}

// MARK: - AnyView

/// A type-erased view that wraps any `View` conforming type.
///
/// Use `AnyView` to hide the concrete type of a view when you need
/// heterogeneous collections or dynamic view switching.
public struct AnyView: View, @unchecked Sendable {
    public typealias Body = Never

    /// The wrapped view's layout behavior.
    internal let layoutBehavior: LayoutBehavior

    /// Closure that returns the children of the wrapped view for layout purposes.
    internal let childProvider: @Sendable () -> [AnyView]

    /// Creates a type-erased view wrapping the given view.
    public init<V: View>(_ view: V) {
        self.layoutBehavior = LayoutResolver.behavior(for: view)
        self.childProvider = { LayoutResolver.children(of: view) }
    }

    public var body: Never {
        fatalError("AnyView.body should never be called directly")
    }
}
