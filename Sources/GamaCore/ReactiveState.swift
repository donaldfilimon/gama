//  ReactiveState.swift — GamaCore
//  Host-owned storage for `@Reactive` state, keyed by structural identity.
//  A component value is rebuilt every frame; its state is not. The slot a
//  `@Reactive` property owns resolves the host's signal for its node at
//  render time, so a fresh instance binds to the same cell the previous
//  frame mutated. Stdlib-only and Embedded-safe: `AnyObject` erasure with a
//  type-id check, no weak references, no process-global registry.

/// Identity of one `@Reactive` slot: the node a component renders under plus
/// the slot's declaration index inside that component.
package struct ReactiveStateKey: Hashable, Sendable {
    package let node: NodeID
    package let slot: Int

    package init(node: NodeID, slot: Int) {
        self.node = node
        self.slot = slot
    }
}

/// Per-host store of `@Reactive` signals keyed by ``ReactiveStateKey``.
///
/// Owned by exactly one `FrameHost`, like `HostActionStore`. Each build pass
/// marks the keys it resolves; the host sweeps once after the frame's final
/// build so a subtree that stopped rendering releases its state. Every
/// signal created here observes the host's invalidation, which is what
/// makes an out-of-band `@Reactive` write request a frame.
/// **Not `Sendable`.** The store holds host-confined signals and closes
/// over the host's dirty flag; it joins the ADR 0009 confinement table.
package final class HostStateStore: ~Sendable {
    private struct Entry {
        let typeID: ObjectIdentifier
        let object: AnyObject
        let cancel: () -> Void
        let rebind: () -> Void
        var marked: Bool
    }

    private var entries: [ReactiveStateKey: Entry] = [:]
    private var previousIdentities: [ReactiveStateKey: ObjectIdentifier] = [:]
    private var currentIdentities: [ReactiveStateKey: ObjectIdentifier] = [:]
    private var transient: [NodeID] = []
    private let invalidate: () -> Void

    /// Creates an empty store whose signals invalidate through `invalidate`
    /// — the owning host's dirty-flag setter, never the store itself.
    package init(invalidate: @escaping () -> Void) {
        self.invalidate = invalidate
    }

    /// Number of live signals. Tests use it as the leak-proof baseline.
    package var count: Int { entries.count }

    /// Nodes whose reactive storage changed identity since the previous
    /// frame — state that was reconstructed instead of preserved.
    package var transientIDs: [NodeID] { transient }

    /// Clears marks so the coming build can report which keys are live.
    package func beginBuildPass() {
        for key in entries.keys { entries[key]?.marked = false }
        transient.removeAll(keepingCapacity: true)
        currentIdentities.removeAll(keepingCapacity: true)
    }

    /// Returns the host's signal for `key`, creating it from `initial` on
    /// first resolution (or when the stored value has a different type).
    /// `attach` receives the signal now and again on every ``activate()``,
    /// so a slot shared by several hosts always writes to the host whose
    /// action is running.
    package func resolve<Value: Sendable>(
        _ key: ReactiveStateKey,
        initial: Value,
        attach: @escaping (Signal<Value>) -> Void
    ) -> Signal<Value> {
        let typeID = ObjectIdentifier(Signal<Value>.self)
        if let entry = entries[key], entry.typeID == typeID {
            // Sound: `entry.typeID` was recorded as `ObjectIdentifier(Signal<Value>.self)`
            // when the object was stored, so the dynamic type matches exactly.
            let signal = unsafe unsafeDowncast(entry.object, to: Signal<Value>.self)
            entries[key] = Entry(
                typeID: typeID, object: signal, cancel: entry.cancel,
                rebind: { attach(signal) }, marked: true)
            attach(signal)
            note(key, signal)
            return signal
        }
        if let stale = entries[key] { stale.cancel() }
        let signal = Signal(initial)
        let token = signal.observe { [invalidate] in invalidate() }
        entries[key] = Entry(
            typeID: typeID, object: signal,
            cancel: { signal.cancel(token) },
            rebind: { attach(signal) }, marked: true)
        attach(signal)
        note(key, signal)
        return signal
    }

    private func note(_ key: ReactiveStateKey, _ object: AnyObject) {
        let identity = ObjectIdentifier(object)
        if let previous = previousIdentities[key], previous != identity {
            transient.append(key.node)
        }
        currentIdentities[key] = identity
    }

    /// Re-attaches every slot resolved in the last build to this host's
    /// signals. The host calls it before invoking an action so a component
    /// instance rendered by more than one host writes to the right one.
    package func activate() {
        for entry in entries.values where entry.marked { entry.rebind() }
    }

    /// Evicts every key the last build did not resolve, cancelling its
    /// invalidation observer, and rolls the identity map forward for the
    /// next frame's transient check. Call once per frame, after the final
    /// build — a focus-reconciliation rebuild must not sweep the first
    /// build's marks.
    package func sweep() {
        var evicted: [ReactiveStateKey] = []
        for (key, entry) in entries where !entry.marked {
            entry.cancel()
            evicted.append(key)
        }
        for key in evicted { entries.removeValue(forKey: key) }
        previousIdentities = currentIdentities
    }
}

/// The store is host-confined for the same reason ``Signal`` is; see
/// ADR 0009. The unavailable conformance keeps the named diagnostic.
@available(*, unavailable)
extension HostStateStore: @unchecked Sendable {}

/// Storage owned by a `@Reactive` property.
///
/// Before a component renders under a host, reads and writes use the slot's
/// own local signal, so `let c = Counter(); c.count = 5` before the first
/// frame is preserved. When a `@Component`-synthesized `render(in:)` binds
/// the slot to a host, that host's signal takes over: every copy of the
/// component value shares this slot, so an action closure captured during a
/// build writes to host-owned storage that outlives the instance.
///
/// `@Reactive` state is therefore **per surface**: two windows of one
/// `WindowGroup` resolve independent signals for the same slot. Share state
/// across surfaces with a ``Signal`` on the `App` instead.
///
/// **Not `Sendable`, and unavailably so**, exactly like ``Signal``: a slot
/// belongs to the host that bound it. See ADR 0009 and ADR 0011.
public final class ReactiveSlot<Value: Sendable>: ~Sendable {
    private let local: Signal<Value>
    private var bound: Signal<Value>? = nil

    /// Creates an unbound slot holding `initial`.
    public init(_ initial: Value) {
        self.local = Signal(initial)
    }

    /// The signal currently backing this slot — the host's once bound, the
    /// local cell before that. Pass it to `TextField`/`Toggle` bindings or
    /// `subscribe(in:)`.
    public var signal: Signal<Value> { bound ?? local }

    /// Reads the current value.
    public func get() -> Value { signal.get() }

    /// Writes and notifies through the backing signal.
    public func set(_ newValue: Value) { signal.set(newValue) }

    /// A read/write projection that follows the slot's binding, so a
    /// control created in one frame keeps writing to host storage.
    public func binding() -> Binding<Value> {
        Binding(get: { [self] in signal.get() }, set: { [self] in signal.set($0) })
    }

    /// Binds this slot to the host that owns `context`, or leaves it on
    /// local storage when there is no host (host-less rendering such as
    /// `gama-demo --emit-mlir`). Called by the `render(in:)` that
    /// `@Component` synthesizes; `slot` is the property's declaration
    /// index, which together with `context.id` forms the storage key.
    public func _bind(in context: BuildContext, slot: Int) {
        guard let store = context.stateStore else { return }
        _ = store.resolve(
            ReactiveStateKey(node: context.id, slot: slot),
            initial: local.get(),
            attach: { [self] signal in bound = signal }
        )
    }
}

/// Slots explicitly opt out of implicit `Sendable` inference because they
/// are host-bound by construction; see ``ReactiveSlot``.
@available(*, unavailable)
extension ReactiveSlot: @unchecked Sendable {}
