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
interactive identities from the latest frame. Focus is stored as a ``NodeID``
rather than a collection index, so unrelated insertions do not silently move
focus.

## State and bindings

``Signal`` owns a value and explicit subscriptions. Notifications snapshot the
observer list, avoid recursive observer entry, allow cancellation, and can
skip equal values through `setIfChanged(_:)`. ``Binding`` exposes a focused
read/write projection without exposing storage. ``State`` is the property
wrapper form.

State sources outside a Gama event callback connect explicitly through the
host-owned ``SubscriptionContext`` using ``FrameHost/observe(_:)``,
``Signal/subscribe(in:)``, or ``Signal/binding(in:)``. Backends may also call
``FrameHost/invalidate()`` for non-signal sources. Duplicate observation is
coalesced; ``FrameHost/cancelSubscriptions()`` cancels only that host's model
connections. This keeps invalidation and cancellation ownership visible and
avoids a hidden global singleton.
