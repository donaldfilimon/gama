// NEGATIVE FIXTURE — this file MUST NOT compile.
//
// Deliberately outside every SwiftPM target. `scripts/check-boundaries.sh`
// compiles it with `swiftc -c` and fails the gate if it *succeeds*.
//
// WHAT THIS PINS, AND WHY IT DID NOT EXIST UNTIL NOW:
// ADR 0006 decides that `FrameHost` and `AppRuntime` are `~Copyable`, and its
// Consequences promise "accidental sharing is a compile error". Nothing
// enforced it. Audited 2026-09-06: `check-boundaries.sh` pinned `~Sendable`
// for `Signal`, `PluginRuntime`, `ReactiveSlot`, and `HostStateStore`, and the
// `Tests/Fixtures/Ownership` fixtures pinned `Terminal` (ADR 0010), but no
// fixture and no grep covered the two host types. Deleting `: ~Copyable` from
// `Sources/GamaCore/FrameHost.swift:38` would have passed every one of the
// fifteen gates while making `AGENTS.md` a false statement about the shipped
// type — and it would have silently reintroduced the exact defect ADR 0006
// records from 2026-08-27, when dropped annotations left `main` "claiming
// value semantics the implementation does not have".
//
// A `FrameHost` uniquely owns focus, actions, `@Reactive` state, subscriptions,
// dirty state, and frames. Two owners means two divergent copies of all of it.
//
// WHY THERE IS NO MATCHING `AppRuntime` FIXTURE:
// ADR 0006 covers both types, but only this one is reachable. `AppRuntime`
// stores a `HostPump`, which is itself `~Copyable`, and a `Copyable` struct
// cannot store a non-`Copyable` one — measured on the pinned snapshot:
// "stored property 'inner' of 'Copyable'-conforming struct 'Outer' has
// non-Copyable type 'Inner'". So deleting `: ~Copyable` from `AppRuntime`
// fails to compile on the spot; it is self-enforcing. `FrameHost`'s stored
// properties are all `Copyable`, which is exactly why it needed a fixture and
// `AppRuntime` does not.
//
// WHY THE GATE USES `-c` AND NOT `-typecheck`:
// Move-only enforcement runs in SIL, after type checking, so `swiftc
// -typecheck` exits 0 on this exact file and would prove nothing. This is the
// same measured trap the sibling `error.TerminalMustNotBeCopied.swift` records
// in detail; do not weaken the gate to `-typecheck`.
//
// EXPECT-DIAGNOSTIC: 'host' consumed more than once
import GamaCore

private struct ProbeApp: App {
    var scenes: some Scene {
        Window("Probe", id: "probe", role: .primary) { EmptyView() }
    }
}

func gama_negative_frameHostIsCopied() throws {
    let host = try FrameHost(app: ProbeApp())
    // Two owners of one host. Each would carry its own focus, its own dirty
    // flag, and its own `@Reactive` store, and the two would diverge on the
    // very first event delivered to either.
    let first = host
    let second = host
    _ = first
    _ = second
}
