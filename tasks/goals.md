# Goals

## Current objective

Keep Gama a portable, retained Swift UI framework whose documentation and
evidence match the exact source, toolchain, and acceptance matrix.

The accepted foundation designs are implemented. Current maintenance keeps
state ownership, diagnostics, and documentation aligned with that foundation;
[`todo.md`](todo.md) records the delivery requirements, manual and
credential-gated acceptance, and deferred product scope. New product scope
needs a new accepted design. Extending strict memory safety to executables
and the test target remains a separate decision documented in ADR 0012.

## Delivered foundation

The current `main` line includes the Swift 6.5-dev umbrella, scene-first core,
shared frame pump, non-Sendable host state, noncopyable hosts and terminal
ownership, per-surface identity-keyed `@Reactive` state, strict memory safety
on every shipped library and macro target, explicit import access levels on
every Swift target, Tier-1 plugins, Apple shell, TUI, Wasm, C/Android
embedding, MLIR, packaging,
accessibility derivation, deterministic performance evidence, and full public
DocC coverage.

The source of truth for what is proven is
[`docs/Capabilities.md`](../docs/Capabilities.md). The full local driver has 13
fail-closed gates in `scripts/check.sh`; hosted proof is the six-job "Gama
acceptance" workflow for the exact pushed commit. Manual UI, accessibility,
credentialed release, physical-device, and physical-board acceptance remain
separate evidence layers.

## Ledger rules

- Keep only current work here and in `todo.md`; Git and dated design records
  retain completed history.
- Do not copy volatile test counts, artifact sizes, run IDs, or branch names
  into this ledger unless they are required to explain an unresolved blocker.
- When a claim changes, update the capability guide or owning design record
  once and link to it instead of duplicating the prose.
- Never promote local, hosted, generated-artifact, or manual evidence into a
  stronger layer.
