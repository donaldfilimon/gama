import Foundation

/// A type of object with a publisher that emits before the object has changed.
///
/// By default an `ObservableObject` synthesizes an `objectWillChange`
/// publisher that emits the changed value before any of its `@Published`
/// properties changes.
///
/// Swift 6.2: Enhanced with improved Sendable conformance
public protocol ObservableObject: AnyObject, @retroactive Sendable {
    /// The type of publisher that emits before the object has changed.
    associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher
    
    /// A publisher that emits before the object has changed.
    var objectWillChange: ObjectWillChangePublisher { get }
}

extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    /// The default publisher for ObservableObject.
    public var objectWillChange: ObservableObjectPublisher {
        ObservableObjectPublisher()
    }
}

/// A publisher that emits before the object has changed.
public final class ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    
    private var subscribers: [SubscriberRef] = []
    private let lock = NSLock()
    
    public init() {}
    
    /// Sends a value to the subscriber.
    public func send() {
        lock.lock()
        defer { lock.unlock() }
        let currentSubscribers = subscribers
        for subscriber in currentSubscribers {
            subscriber.send()
        }
    }
    
    /// Attaches the specified subscriber to this publisher.
    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let ref = SubscriberRef(subscriber: subscriber)
        lock.lock()
        subscribers.append(ref)
        lock.unlock()
    }
    
    private class SubscriberRef {
        private weak var subscriber: AnyObject?
        private let sendClosure: () -> Void
        
        init<S: Subscriber>(subscriber: S) where S.Failure == Never, S.Input == Void {
            self.subscriber = subscriber as? AnyObject
            self.sendClosure = {
                _ = subscriber.receive(())
            }
        }
        
        func send() {
            if subscriber != nil {
                sendClosure()
            }
        }
    }
}

/// A property wrapper type that subscribes to an observable object and
/// invalidates a view whenever the observable object changes.
@propertyWrapper
public struct ObservedObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    private var _wrappedValue: ObjectType
    private var _cancellable: AnyCancellable?
    
    /// Creates an observed object with an initial value.
    ///
    /// - Parameter initialValue: The initial value to store in the observed object.
    public init(wrappedValue: ObjectType) {
        self._wrappedValue = wrappedValue
    }
    
    /// The underlying value referenced by the observed object.
    public var wrappedValue: ObjectType {
        get {
            _wrappedValue
        }
        mutating set {
            _wrappedValue = newValue
        }
    }
    
    /// A projection of the observed object that creates bindings to its
    /// properties using dynamic member lookup.
    public var projectedValue: ObservedObject.Wrapper {
        ObservedObject.Wrapper(object: _wrappedValue)
    }
    
    public func update() {
        // Subscribe to changes
        _cancellable = AnyCancellable(
            _wrappedValue.objectWillChange.sink { [weak _wrappedValue] _ in
                // Trigger view update
                if let object = _wrappedValue {
                    // View update would be handled by the view system
                }
            }
        )
    }
    
    /// A wrapper of the underlying value that provides a binding.
    @propertyWrapper
    @dynamicMemberLookup
    public struct Wrapper {
        public var wrappedValue: ObjectType
        
        public init(object: ObjectType) {
            self.wrappedValue = object
        }
        
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            Binding(
                get: { self.wrappedValue[keyPath: keyPath] },
                set: { self.wrappedValue[keyPath: keyPath] = $0 }
            )
        }
    }
}

/// A property wrapper type that instantiates an observable object.
@propertyWrapper
public struct StateObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    private var _wrappedValue: ObjectType
    
    /// Creates a new state object with an initial value.
    ///
    /// - Parameter wrappedValue: An initial value for the state object.
    public init(wrappedValue: ObjectType) {
        self._wrappedValue = wrappedValue
    }
    
    /// The underlying value referenced by the state object.
    public var wrappedValue: ObjectType {
        get {
            _wrappedValue
        }
    }
    
    /// A projection of the state object that creates bindings to its
    /// properties using dynamic member lookup.
    public var projectedValue: ObservedObject<ObjectType>.Wrapper {
        ObservedObject.Wrapper(object: _wrappedValue)
    }
}

/// A property wrapper type for an observable object supplied by a parent
/// or ancestor view.
@propertyWrapper
public struct EnvironmentObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    private var _wrappedValue: ObjectType?
    
    /// Creates an environment object.
    public init() {
        self._wrappedValue = nil
    }
    
    /// The underlying value referenced by the environment object.
    public var wrappedValue: ObjectType {
        get {
            guard let value = _wrappedValue else {
                fatalError("No ObservableObject of type \(ObjectType.self) found in environment")
            }
            return value
        }
        mutating set {
            _wrappedValue = newValue
        }
    }
}