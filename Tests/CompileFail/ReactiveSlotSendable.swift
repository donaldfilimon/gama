// Negative compiler fixture. This file intentionally lives outside every
// SwiftPM target and must fail under scripts/check-concurrency-negative.sh.
// A `@Reactive` slot is bound to one host, exactly like the Signal it
// resolves (ADR 0009, ADR 0011).

import GamaCore

private func requireSendable<T: Sendable>(_ value: T) {}

func reactiveSlotSendabilityMustRemainUnavailable(_ slot: ReactiveSlot<Int>) {
    requireSendable(slot)
}
