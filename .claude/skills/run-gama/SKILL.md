---
name: run-gama
description: Build and drive the Zig Gama terminal counter and editing form through owned tmux sessions.
---

# Run Gama

From the repository root, run `.claude/skills/run-gama/driver.sh smoke`.
The driver uses the exact `.zig-version` compiler and builds `examples/demo.zig`.
It requires an existing tmux executable. No installation or server replacement is performed.

The smoke requires count 0 with focus -1, Tab to +1, Enter to count 1,
Space to count 2, then Tab into the name field. It types ab, moves left,
inserts X, backspaces, and verifies ab survives focus away/back. Captured frames
and the selected binary/compiler receipt go into a private temporary directory.
See [Capabilities](../../../docs/Capabilities.md) for actual proof and limitations.

Commands: build, launch, text, keys (tmux arguments), quit, smoke.
Step-by-step launch rejects occupied names. A private receipt and tmux owner token
bind later commands to the exact created session ID. Cleanup never kills the server
or a session whose owner token differs. Smoke uses a unique session suffix.

`GAMA_RUN_ZIG` selects the compiler; its version must match the pin on build.
`GAMA_RUN_BINARY` selects an existing executable; such an override is caller-supplied
and does not itself prove source provenance. `GAMA_RUN_SESSION`, `GAMA_RUN_STATE`,
and `GAMA_RUN_ARTIFACTS` select session name and private receipt/capture locations.
The build graph supplies the emitted demo directly to `smoke [built-binary]`.

For plain output use `zig build demo -- --gama-plain`; the adaptive runtime also
selects plain output when stdout is not a terminal. Ctrl-C quits interactive use.
The demo reports focus explicitly because default color depth is unknown.
On Darwin, unknown custom managed signal dispositions require caller-owned exact
installation records; acquisition otherwise fails before mutation. Do not install
untracked custom handlers around the convenience demo.

Run `zig build check` or `scripts/check.sh` for the complete retained acceptance gate.
