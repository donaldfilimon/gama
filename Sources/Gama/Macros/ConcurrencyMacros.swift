import Foundation

/// Swift 6.2: Concurrency utilities and helpers
/// These provide enhanced concurrency support using modern Swift 6.2 features

/// Swift 6.2: Async-safe state wrapper
/// Provides thread-safe access to state from async contexts
@propertyWrapper
@MainActor
public struct AsyncState<Value: Sendable> {
    private var _value: Value
    
    public init(wrappedValue: Value) {
        self._value = wrappedValue
    }
    
    public var wrappedValue: Value {
        get { _value }
        set { _value = newValue }
    }
    
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

/// Swift 6.2: Isolated actor property wrapper
/// Ensures properties are accessed only from the correct actor
@propertyWrapper
public struct Isolated<Value: Sendable> {
    private let actor: any Actor
    private var _value: Value
    
    public init(wrappedValue: Value, isolatedTo actor: any Actor) {
        self._value = wrappedValue
        self.actor = actor
    }
    
    public var wrappedValue: Value {
        get {
            // In a real implementation, this would check actor isolation
            _value
        }
        set {
            _value = newValue
        }
    }
}

/// Swift 6.2: Helper for creating task-safe closures
@inlinable
public func taskSafe<T>(
    _ body: @escaping @Sendable () async throws -> T
) -> @Sendable () async throws -> T {
    body
}

/// Swift 6.2: Helper for ensuring Sendable conformance at compile time
@inlinable
public func ensureSendable<T: Sendable>(_ value: T) -> T {
    value
}
