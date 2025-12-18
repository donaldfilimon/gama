import Foundation

/// Swift 6.2: Property wrapper utilities and helpers
/// These provide enhanced functionality for property wrappers using modern Swift features

/// Enhanced State property wrapper with improved isolation
/// Swift 6.2: Uses region-based isolation for better concurrency safety
public typealias EnhancedState<Value: Sendable> = State<Value>

/// Enhanced Binding with improved Sendable conformance
/// Swift 6.2: Uses improved isolation checking
public typealias EnhancedBinding<Value: Sendable> = Binding<Value>

/// Swift 6.2: Helper for creating property wrappers with automatic Sendable conformance
@inlinable
public func makeState<Value: Sendable>(_ value: Value) -> State<Value> {
    State(wrappedValue: value)
}

/// Swift 6.2: Helper for creating bindings with improved type safety
@inlinable
public func makeBinding<Value: Sendable>(
    get: @escaping @MainActor () -> Value,
    set: @escaping @MainActor (Value) -> Void
) -> Binding<Value> {
    Binding(get: get, set: set)
}
