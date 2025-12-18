import Foundation

/// A two-way connection between a property that stores data, and a view that
/// displays and changes the data.
///
/// A binding connects a property to a source of truth stored elsewhere,
/// instead of storing data directly.
///
/// Swift 6.2: Enhanced with improved isolation and Sendable conformance
@MainActor
public struct Binding<Value>: @unchecked Sendable {
    private let _get: () -> Value
    private let _set: (Value) -> Void
    
    /// Creates a binding with closures to read and write the value.
    ///
    /// - Parameters:
    ///   - get: A closure to retrieve the value.
    ///   - set: A closure to set the value.
    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self._get = get
        self._set = set
    }
    
    /// Creates a binding from another binding.
    public init(_ source: Binding<Value>) {
        self = source
    }
    
    /// The value referenced by the binding.
    public var wrappedValue: Value {
        get {
            _get()
        }
        nonmutating set {
            _set(newValue)
        }
    }
    
    /// Creates a binding that projects a value from another binding.
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { self.wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

extension Binding {
    /// Creates a binding with a constant value.
    ///
    /// - Parameter value: The value to use for the binding.
    /// - Returns: A binding that always returns the given value.
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(
            get: { value },
            set: { _ in }
        )
    }
    
    /// Creates a binding from a value and a closure to set it.
    ///
    /// - Parameters:
    ///   - value: The current value.
    ///   - set: A closure to update the value.
    /// - Returns: A binding that reads from the value and writes using the closure.
    public static func variable(_ value: Value, set: @escaping @MainActor (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { value },
            set: set
        )
    }
}

/// A protocol that provides a binding to a value.
public protocol Bindable {
    associatedtype Value
    var binding: Binding<Value> { get }
}