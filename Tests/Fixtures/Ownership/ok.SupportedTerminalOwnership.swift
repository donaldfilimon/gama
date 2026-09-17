// POSITIVE FIXTURE — this file MUST compile.
//
// Driven by `scripts/check-boundaries.sh`. Two jobs:
//
//  1. It is the harness check. The `error.*` fixtures in this directory are
//     only meaningful if a *legal* file compiles under the same `-sdk`,
//     `-I`, and module-map flags. Without this fixture a broken include path
//     would make every negative "fail to compile" for the wrong reason and
//     the gate would pass vacuously.
//  2. It is the executable form of `docs/TerminalOwnershipMigration.md`:
//     everything below is API that ADR 0010 left working unchanged.
import GamaCore
import GamaTUI

// A `Terminal` may be consumed into the session that owns raw mode.
func gama_positive_consumingHandoff() throws(TerminalError) -> RawModeSession {
    let terminal = Terminal()
    return try RawModeSession(terminal: terminal)
}

// A noncopyable `Terminal` may be passed `inout` through a function type.
func gama_positive_inoutEscapeHatch(_ session: inout RawModeSession) -> Size {
    session.withTerminal { terminal in terminal.size() }
}

// Borrowing reads and the mutating write/poll/close family are unchanged.
func gama_positive_sessionSurface(
    _ session: inout RawModeSession
) throws(TerminalError) -> (Size, InputEvent?) {
    let size = session.size()
    try session.write("")
    let event = try session.nextEvent(timeoutMillis: 0)
    try session.close()
    return (size, event)
}

// Aggregates may hold a `Terminal` once they declare `~Copyable` themselves.
struct GamaPositiveTerminalBox: ~Copyable {
    var terminal: Terminal
}
