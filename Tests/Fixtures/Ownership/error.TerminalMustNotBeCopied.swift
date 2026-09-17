// NEGATIVE FIXTURE — this file MUST NOT compile.
//
// Deliberately outside every SwiftPM target. `scripts/check-boundaries.sh`
// compiles it with `swiftc -c` and fails the gate if it *succeeds*, which is
// what pins the unique ownership of `Terminal` as a compiler-checked fact
// rather than a documented convention (ADR 0010).
//
// This is the copy-failure fixture Wave 4C of the modernization plan
// requires before a public noncopyability change may land.
//
// WHY THE GATE USES `-c` AND NOT `-typecheck`:
// MEASURED 2026-08-28 on the pinned 6.5-dev snapshot (org.swift.65202608211a)
// and on Xcode's Swift 6.4, across 27 ownership probes: move-only enforcement
// runs in SIL, *after* type checking, so `swiftc -typecheck` exits 0 on this
// exact file. A `-typecheck`-driven gate would pass while proving nothing.
// Re-measured on this committed file: `-typecheck` -> EXIT 0 (no output),
// `-c` -> EXIT 1 with "'terminal' consumed more than once".
// The gate is self-protecting against that regression: weakening `-c` back to
// `-typecheck` makes this fixture compile, which trips the gate's
// "compiled but must not" branch.
//
// EXPECT-DIAGNOSTIC: 'terminal' consumed more than once
import GamaTUI

func gama_negative_terminalIsCopied() {
    let terminal = Terminal()
    // Two owners of one controlling tty — each with its own `isRaw` and its
    // own snapshot of "the original termios". This is the exact hazard
    // ADR 0010 exists to make impossible.
    let first = terminal
    let second = terminal
    _ = first
    _ = second
}
