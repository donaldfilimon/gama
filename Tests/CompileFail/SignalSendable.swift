// Negative compiler fixture. This file intentionally lives outside every
// SwiftPM target and must fail under scripts/check-concurrency-negative.sh.

import GamaCore

private func requireSendable<T: Sendable>(_ value: T) {}

func signalSendabilityMustRemainUnavailable(_ signal: Signal<Int>) {
    requireSendable(signal)
}
