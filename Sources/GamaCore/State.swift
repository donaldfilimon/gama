//  State.swift — GamaCore
//  Reactivity without Combine, without weak references (Embedded Swift
//  has no weak/unowned-safe). Subscriptions are explicit tokens the
//  runtime cancels between build passes — no retain cycles possible
//  because Signal never captures its observers' owners.

public struct SubscriptionToken: Hashable, Sendable {
    let id: UInt64
}

/// Host-owned subscription lifetime and invalidation context.
///
/// A backend explicitly connects model signals to its `FrameHost` through
/// this object. The context owns cancellation, so destroying or resetting one
/// host cannot leave observers that invalidate a different host. Like
/// `FrameHost` and `Signal`, it is confined to the backend's owning executor;
/// no global registry or platform lock is involved.
public final class SubscriptionContext: @unchecked Sendable {
    private let invalidateHost: @Sendable () -> Void
    private var observedSignals: Set<ObjectIdentifier> = []
    private var cancellations: [() -> Void] = []

    public init(invalidate: @escaping @Sendable () -> Void) {
        self.invalidateHost = invalidate
    }

    public func observe<Value>(_ signal: Signal<Value>) {
        let identity = ObjectIdentifier(signal)
        guard observedSignals.insert(identity).inserted else { return }
        let token = signal.observe { [invalidateHost] in invalidateHost() }
        cancellations.append { [signal] in signal.cancel(token) }
    }

    public func invalidate() { invalidateHost() }

    public func cancelAll() {
        let pending = cancellations
        cancellations.removeAll(keepingCapacity: false)
        observedSignals.removeAll(keepingCapacity: false)
        for cancel in pending { cancel() }
    }

    deinit {
        for cancel in cancellations { cancel() }
    }
}

/// A single mutable cell that notifies observers on change.
///
/// Reentrancy-safe: the observer list is snapshotted before firing, so
/// observers may subscribe/cancel/set during notification without
/// mutating the list mid-iteration; observers added during a pass are
/// not called until the next change.
public final class Signal<Value: Sendable>: @unchecked Sendable {
    private var value: Value
    private var observers: [(UInt64, @Sendable () -> Void)] = []
    private var nextID: UInt64 = 0
    private var notifying = false

    public init(_ initial: Value) {
        self.value = initial
    }

    public var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            notify()
        }
    }

    public func get() -> Value { value }

    public func set(_ newValue: Value) { wrappedValue = newValue }

    public func update(_ transform: (inout Value) -> Void) {
        var v = value
        transform(&v)
        wrappedValue = v
    }

    private func notify() {
        // Re-entrant set() inside an observer: the outer pass already
        // delivers the freshest value on its remaining callbacks.
        guard !notifying else { return }
        notifying = true
        let snapshot = observers
        for (_, fn) in snapshot { fn() }
        notifying = false
    }

    @discardableResult
    public func observe(_ fn: @escaping @Sendable () -> Void) -> SubscriptionToken {
        nextID += 1
        observers.append((nextID, fn))
        return SubscriptionToken(id: nextID)
    }

    public func cancel(_ token: SubscriptionToken) {
        observers.removeAll { $0.0 == token.id }
    }

    /// Connect this signal to a host-owned lifetime/invalidation context.
    public func subscribe(in context: SubscriptionContext) {
        context.observe(self)
    }

    /// A read/write projection of this signal.
    public func binding() -> Binding<Value> {
        Binding(get: { [self] in get() }, set: { [self] in set($0) })
    }

    /// A binding whose reads/writes are associated with a host context.
    public func binding(in context: SubscriptionContext) -> Binding<Value> {
        subscribe(in: context)
        return binding()
    }
}

extension Signal where Value: Equatable {
    /// Set without notifying when the value is unchanged — cuts redundant
    /// rebuild passes for high-frequency sources (pointer, ticks).
    public func setIfChanged(_ newValue: Value) {
        guard newValue != wrappedValue else { return }
        set(newValue)
    }
}

/// A get/set pair decoupled from Signal — pass mutable access into child
/// components without exposing the storage. Mirrors SwiftUI's Binding.
public struct Binding<Value: Sendable>: Sendable {
    private let getter: @Sendable () -> Value
    private let setter: @Sendable (Value) -> Void

    public init(
        get: @escaping @Sendable () -> Value,
        set: @escaping @Sendable (Value) -> Void
    ) {
        self.getter = get
        self.setter = set
    }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }

    /// Derive a binding to a part of this value.
    public func map<T: Sendable>(
        get: @escaping @Sendable (Value) -> T,
        set: @escaping @Sendable (inout Value, T) -> Void
    ) -> Binding<T> {
        Binding<T>(
            get: { [self] in get(wrappedValue) },
            set: { [self] newPart in
                var v = wrappedValue
                set(&v, newPart)
                wrappedValue = v
            }
        )
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
}

/// Property wrapper bridging Signal into view structs.
///
///     struct Counter: View {
///         @State var count = 0
///         var body: some View { Text("\(count)") }
///     }
///
/// The projected value exposes the Signal for binding-style pass-down.
@propertyWrapper
public struct State<Value: Sendable>: Sendable {
    private let signal: Signal<Value>

    public init(wrappedValue: Value) {
        self.signal = Signal(wrappedValue)
    }

    public var wrappedValue: Value {
        get { signal.get() }
        nonmutating set { signal.set(newValue) }
    }

    public var projectedValue: Signal<Value> { signal }

    /// A Binding view of this state, for child components.
    public var binding: Binding<Value> { signal.binding() }
}
