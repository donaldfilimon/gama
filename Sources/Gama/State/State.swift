import Foundation

/// A property wrapper type that can read and write a value owned by a view.
///
/// SwiftUI manages the storage of any property you declare as a state.
/// When the state value changes, the view invalidates its appearance and
/// recomputes the body.
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

/// Internal storage for State values.
@MainActor
private class StateStorage<Value>: @unchecked Sendable {
    var value: Value
    
    init(value: Value) {
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