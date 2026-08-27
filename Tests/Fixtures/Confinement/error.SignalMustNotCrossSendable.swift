// NEGATIVE FIXTURE — this file MUST NOT compile.
//
// Deliberately outside every SwiftPM target. `scripts/check-boundaries.sh`
// compiles it and fails the gate if it *succeeds*, which is what pins the
// single-host confinement of `Signal` as a compiler-checked fact rather
// than a documented convention (ADR 0009).
//
// Expected diagnostic: capture of a non-Sendable `Signal` in a `@Sendable`
// closure.
import GamaCore

func gama_negative_signalEscapesIntoSendableClosure() {
    let signal = Signal(0)
    let escape: @Sendable () -> Void = {
        signal.set(1)
    }
    _ = escape
}
