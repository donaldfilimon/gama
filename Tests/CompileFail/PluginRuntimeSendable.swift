// Negative compiler fixture. This file intentionally lives outside every
// SwiftPM target and must fail under scripts/check-concurrency-negative.sh.

import GamaPlugin

private func requireSendable<T: Sendable>(_ value: T) {}

func pluginRuntimeSendabilityMustRemainUnavailable(_ runtime: PluginRuntime) {
    requireSendable(runtime)
}
