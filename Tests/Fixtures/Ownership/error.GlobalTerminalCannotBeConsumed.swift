// NEGATIVE FIXTURE — this file MUST NOT compile.
//
// Driven by `scripts/check-boundaries.sh`. Pins the half of ADR 0010's
// global-variable probe that predicts `Sources/GamaWindowsConsoleSmoke/
// main.swift` needs no edit: a global `~Copyable` var may be *mutated* in
// place but never *consumed*, because nothing can reinitialize the global
// afterwards.
//
// Ownership enforcement again runs in SIL: this file also type-checks
// clean and only fails under `-c`.
//
// EXPECT-DIAGNOSTIC: missing reinitialization of inout parameter 'gama_negative_globalTerminal' after consume
import GamaTUI

@MainActor var gama_negative_globalTerminal = Terminal()

@MainActor func gama_negative_consumesGlobalTerminal() {
    let taken = consume gama_negative_globalTerminal
    _ = taken
}
