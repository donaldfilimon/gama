// NEGATIVE FIXTURE — this file MUST NOT compile.
//
// Driven by `scripts/check-boundaries.sh` alongside the copy fixture.
// Pins the one migration step a consumer actually has to make (ADR 0010,
// `docs/TerminalOwnershipMigration.md`): a struct does NOT become
// noncopyable by inference from its stored properties, so anything storing
// a `Terminal` must spell `: ~Copyable` itself.
//
// Unlike the copy fixture this one is rejected in Sema, so it fails under
// `-typecheck` too — which is precisely why it cannot stand in for the copy
// fixture. Both are required.
//
// EXPECT-DIAGNOSTIC: has non-Copyable type 'Terminal'
import GamaTUI

struct GamaNegativeTerminalBox {
    var terminal: Terminal
}
