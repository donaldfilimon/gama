# Gama Agent Guide

Gama is a Zig/std-only portable component and rendering framework. The authoritative graph is `build.zig`; `src/root.zig` is the facade. Work in the canonical checkout on main, preserve concurrent changes, and do not commit, push, create branches/worktrees, or publish unless requested.

## Commands and boundaries

Use the exact `.zig-version` compiler, pinned by `ZigToolchain.zon`. Run `zig build check` and `scripts/check.sh` before calling a change complete. `GAMA_ZIG` selects the wrapper compiler; `GAMA_RUN_ZIG` selects the terminal driver compiler. Missing tools fail closed. Prerequisites are the pinned Zig compiler, Python 3, Node, tmux, and an existing mlir-opt; no gate installs tools. Override the parser with `zig build check -Dmlir-opt=/path/to/mlir-opt` or `GAMA_MLIR_OPT` for the script.

Run `zig build`, `zig build demo -- --gama-plain`, `zig build plugins`, or `.agents/skills/run-gama/driver.sh smoke`. Interactive use requires a real terminal. The mirrored skill/driver under `.claude/skills/run-gama` must remain equivalent. Never take over existing tmux sessions.

Portable code is in `src/core`, `src/draw`, `src/plugins`, and `src/mlir`; hosted adapters are in `src/tui`, `src/services`, and `src/abi`. Keep all allocation explicit. No package dependencies, vendored libraries, production C helpers, handwritten OS bindings, or Apple frameworks. Standard-library required libc on macOS is allowed. C under `tests` is a linked-consumer fixture, not production. The exact generated Unicode table is private and reproducible.

## Ownership and proof

Hosts own state, registrations, dirty state and transactional frames. Keep owner addresses stable; do not copy owning values after initialization. Application storage outlives its hosts. Handles validate generations during owner lifetime; no borrowed pointer, handle or output may outlive its owner. Native use is executor-confined; freestanding callers supply one executor and storage.

Every prepared frame must commit, abort, or finish once. Failed rendering/output preserves the last internal publication and dirty retry. Partial external writes cannot be rolled back. Grapheme editing, layout, painting and wire semantics are shared across retained adapters. Plugins are cooperative code, not a sandbox.

Use `///` for public declarations and container members, including owner machinery. The API gate uses a documented syntactic superset, not a semantic reachability claim. `tools/api_docs.zig` uses the pinned AST. `tools/check_docs.py` validates current docs, references, mirrored tools and API negative controls. Historical Swift documentation is explicitly under `docs/history/swift`; current accepted Zig design remains checked.

`docs/Capabilities.md` is the sole current qualification ledger. Bounded logs and source-hash receipts under `docs/migration/zig/evidence` qualify deliberately uncommitted sources. Never confuse native tests, foreign cross-links, structural inspection, engine execution, hardware, or hosted CI. Refresh receipts only after executing the claimed commands; a hash is consistency evidence, not proof a command ran.

## Preservation

Keep `Package.resolved` byte-exact as an archival lockfile and `GEMINI.md` empty. Preserve `.remember`, `.swiftpm`, `.claude` operator state and sibling worktrees, `.superpowers` review/preservation records, external runner registrations and credentials. Retired Studio/Qt ignored caches remain private data; the source policy excludes only their exact cache scopes. Never recurse-delete those parents or caches by inference. The inherited MLIR cleanup and authored JNI artifacts have private preservation receipts; never publish private archives.

Read [architecture](docs/Architecture.md), [ownership](docs/StateAndIdentity.md), [plugins](docs/Plugins.md), and the applicable backend contract before changing them. The final independent whole-change review is separate from implementation self-review.
