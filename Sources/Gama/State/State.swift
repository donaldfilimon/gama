import Foundation

/// A property wrapper type that can read and write a value owned by a view.
///
/// SwiftUI manages the storage of any property you declare as a state.
/// When the state value changes, the view invalidates its appearance and
/// recomputes the body.
///
/// Swift 6.2: Enhanced with improved Sendable conformance and isolation
@propertyWrapper
public struct State<Value>: DynamicProperty {
    @MainActor
    private var _storage: StateStorage<Value>
    
    /// Creates the state with an initial wrapped value.
    ///
    /// - Parameter wrappedValue: The initial value for the state variable.
    @MainActor
    public init(wrappedValue value: Value) where Value: Sendable {
        self._storage = StateStorage(value: value)
    }
    
    /// Creates the state with an initial value.
    ///
    /// - Parameter initialValue: The initial value for the state variable.
    @MainActor
    public init(initialValue: Value) where Value: Sendable {
        self._storage = StateStorage(value: initialValue)
    }
    
    /// The underlying value referenced by the state variable.
    @MainActor
    public var wrappedValue: Value {
        get {
            _storage.value
        }
        nonmutating set {
            _storage.value = newValue
        }
    }
    
    /// A binding to the state value.
    @MainActor
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

// Swift 6.2: Extension for non-Sendable values with explicit isolation
extension State where Value: ~Copyable {
    @MainActor
    public init(wrappedValue: consuming Value) {
        self._storage = StateStorage(value: wrappedValue)
    }
}

/// Internal storage for State values.
/// Swift 6.2: Enhanced with region-based isolation
@MainActor
private final class StateStorage<Value>: @unchecked Sendable {
    var value: Value
    
    init(value: Value) {
        self.value = value
    }
    
    // Swift 6.2: Noncopyable value support
    init(value: consuming Value) where Value: ~Copyable {
        self.value = value
    }
}

/// A protocol that allows types to participate in the view's update cycle.
@MainActor
public protocol DynamicProperty {
    /// Updates the underlying value of the stored value.
    func update()
}

extension DynamicProperty {
    public func update() {
        // Default implementation does nothing
    }
}