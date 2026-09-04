# Composition, identity, and state

Build interfaces with the stable result builder or optional macros without
creating two runtime models.

## Composition

``ViewBuilder`` accepts expressions, conditionals, optional branches, arrays,
and limited-arity tuples. Primitive views and modifiers all render into the
same ``RenderNode`` cases. Tuples and ``ForEach`` emit the dedicated
``RenderNode/group(children:)`` flatten sentinel, which containers unpack
into their own child list; only `group` unpacks — a `ZStack`'s
``RenderNode/overlay(alignment:children:)`` always layers. The `@Component`,
`@Reactive`, and `#rgb` macros in the optional `GamaMacros` product expand
into these public GamaCore types.

Use ``ForEach`` with stable application identifiers when collections can be
inserted, reordered, or removed. ``FrameHost/duplicateIDs`` reports duplicate
interactive identities from the latest frame. Focus and `@Reactive` state are
stored under a ``NodeID`` rather than a collection index, so unrelated
insertions do not silently move focus or drop state. ``View/stateScope(_:)``
(``StateScopedView``) renders a subtree under an explicit identity in place
of its structural position, as ``IdentifiedForEach`` does per element.

## State and bindings

``Signal`` owns a value and explicit subscriptions. Notifications snapshot the
observer list, avoid recursive observer entry, allow cancellation, and can
skip equal values through `setIfChanged(_:)`. ``Binding`` exposes a focused
read/write projection without exposing storage. ``State`` is the property
wrapper form and is instance-local.

`@Reactive` expands to a ``ReactiveSlot`` peer. The `render(in:)` that
`@Component` synthesizes binds each slot, in declaration order, to the
``FrameHost`` that owns the build: the host keeps a per-host store of signals
keyed by the node's ``NodeID`` and the slot's index, so a component value
rebuilt on the next frame resolves the same storage. State is therefore per
surface — two windows of one `WindowGroup` hold independent values for the
same declaration — while a ``Signal`` the `App` owns is shared. Before a host
binds it, or with no host at all, a slot reads and writes its own local
signal; ``ReactiveSlot/binding()`` follows whichever is current, and
``ReactiveSlot/signal`` exposes it. After a frame's final build the host
evicts every key that build did not resolve, so a subtree that stops
rendering releases its state; a branch flip or positional reorder drops it,
and ``FrameHost/transientStateIDs`` names the nodes whose storage was
reconstructed, alongside ``FrameHost/duplicateIDs``.

Every host-owned signal observes the host, so an out-of-band write to bound
`@Reactive` state requests a frame by itself. Other state sources outside a
Gama event callback connect explicitly through the host-owned
``SubscriptionContext`` using ``FrameHost/observe(_:)``,
``Signal/subscribe(in:)``, or ``Signal/binding(in:)``. Backends may also call
``FrameHost/invalidate()`` for non-signal sources. Duplicate observation is
coalesced; ``FrameHost/cancelSubscriptions()`` cancels only that host's model
connections. This keeps invalidation and cancellation ownership visible and
avoids a hidden global singleton.
