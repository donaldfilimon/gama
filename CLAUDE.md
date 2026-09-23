# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` first. It is the canonical guide: the gate, the toolchain, the invariants, and what isn't built yet. This file only adds the architecture in one picture.

```text
UI / console / graph / AI  ──►  DocumentCommand  ──►  EditorSession
                                                        │  apply to a copy of SceneDocument
                                                        │  validate() the copy
                                                        │  commit, or discard on any error
                                                        ├─► undo/redo stacks (exact inverses)
                                                        ├─► selection (pruned, not history)
                                                        └─► pendingChanges ──► drainChanges() ──► runtime projection (not built)
```

Commands:

```bash
unset TOOLCHAINS
./tools/check.sh > check.log 2>&1; echo "EXIT:$?"          # the gate
swiftly run swift test --filter TransactionTests           # one suite
```

- Adding a command means three things:
  1. Implement `apply(to:changes:)` so it returns the exact inverse.
  2. Add a case to `CommandRoundTripTests.cases`.
  3. Raise `MIN_TESTS` in `tools/check.sh`.
- Agent shells may set `noclobber`: truncate with `>|`, and verify file edits by grepping for a marker rather than trusting an exit code.
