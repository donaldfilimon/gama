//  State.swift — GamaCore
//  Reactivity without Combine, without weak references (Embedded Swift
//  has no weak/unowned-safe). Subscriptions are explicit tokens the
//  runtime cancels between build passes — no retain cycles possible
//  because Signal never captures its observers' owners.

/// Opaque handle for one observer registration on a `Signal`; hand it
/// back to `Signal.cancel(_:)` to detach that observer. Tokens are the
/// whole lifetime story — there are no weak references to expire.
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

    /// Creates a context that funnels every observed signal's change
    /// into the one callback — typically the owning host's dirty-flag
    /// setter.
    public init(invalidate: @escaping @Sendable () -> Void) {
        self.invalidateHost = invalidate
    }

    /// Starts invalidating the host whenever `signal` changes.
    /// Idempotent per signal instance — repeat calls for a signal
    /// already observed are no-ops, so build passes that run every
    /// frame can call this unconditionally.
    public func observe<Value>(_ signal: Signal<Value>) {
        let identity = ObjectIdentifier(signal)
        guard observedSignals.insert(identity).inserted else { return }
        let token = signal.observe { [invalidateHost] in invalidateHost() }
        cancellations.append { [signal] in signal.cancel(token) }
    }

    /// Fires the host invalidation directly — the out-of-band path for
    /// changes that no observed signal carries.
    public func invalidate() { invalidateHost() }

    /// Detaches every observation and forgets which signals were seen,
    /// so they may be observed afresh. The invalidation callback stays,
    /// making the context reusable across host resets.
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

    /// Creates a cell holding `initial`, with no observers attached.
    public init(_ initial: Value) {
        self.value = initial
    }

    /// The current value. Every set notifies — there is no equality
    /// gate; use `setIfChanged(_:)` when redundant rebuild passes
    /// matter.
    public var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            notify()
        }
    }

    /// Reads the current value without touching observers.
    public func get() -> Value { value }

    /// Writes and notifies — identical to assigning `wrappedValue`.
    public func set(_ newValue: Value) { wrappedValue = newValue }

    /// In-place mutation: copies the value out, applies `transform`,
    /// writes back, and notifies exactly once.
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

    /// Registers `fn` to run after every change; the returned token is
    /// the only way to detach it. An observer added mid-notification is
    /// not called until the next change.
    @discardableResult
    public func observe(_ fn: @escaping @Sendable () -> Void) -> SubscriptionToken {
        nextID += 1
        observers.append((nextID, fn))
        return SubscriptionToken(id: nextID)
    }

    /// Detaches the observer registered under `token`; a token that was
    /// already cancelled (or never issued here) is silently ignored.
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

    /// Creates a binding from arbitrary accessors; both must be
    /// `@Sendable` because bindings travel into child components.
    public init(
        get: @escaping @Sendable () -> Value,
        set: @escaping @Sendable (Value) -> Void
    ) {
        self.getter = get
        self.setter = set
    }

    /// Reads and writes through the captured accessors. The setter is
    /// `nonmutating`, so a binding held in a `let` (or inside a view
    /// value) can still write.
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

    /// A binding frozen at `value`: reads always return it, writes are
    /// discarded — for components that require a binding where the
    /// caller has nothing mutable to offer.
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

    /// Allocates the backing `Signal`. The wrapper stores only that
    /// reference, so copies of the enclosing view value share one cell
    /// and state survives rebuilds of the view struct.
    public init(wrappedValue: Value) {
        self.signal = Signal(wrappedValue)
    }

    /// Reads and writes the backing signal; every write notifies its
    /// observers (typically a host's `SubscriptionContext`).
    public var wrappedValue: Value {
        get { signal.get() }
        nonmutating set { signal.set(newValue) }
    }

    /// `$property` — the backing `Signal`, for `subscribe(in:)` and for
    /// deriving bindings.
    public var projectedValue: Signal<Value> { signal }

    /// A Binding view of this state, for child components.
    public var binding: Binding<Value> { signal.binding() }
}
