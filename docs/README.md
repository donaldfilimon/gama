# Gama documentation

Status: Current navigation for the implemented repository. Capability claims
use the vocabulary in [Capabilities.md](Capabilities.md#status-vocabulary);
dated plans and specs are design history, not proof that a feature shipped.

Gama is a Swift 6.5-dev retained-IR UI framework with one portable application
model and terminal, Apple, WebAssembly, C/Android, Embedded, and MLIR edges.
Use the learning path for your role, then confirm platform status in the
evidence ledger.

## Start here

1. [Getting started](GettingStarted.md) — pinned toolchain, external scratch,
   first application, demos, state lifetime, and verification.
2. [Architecture and ownership](Architecture.md) — scene compilation,
   noncopyable hosts, frame flow, module boundaries, drawing, and services.
3. [State, identity, and lifetime](StateAndIdentity.md) — signals, bindings,
   hoisted state, collection identity, multi-window ownership, and current
   limitations.
4. [Examples and runnable surfaces](Examples.md) — terminal, MLIR, AppKit,
   WASM, C, Android, Embedded, and performance routes.
5. [Verification and evidence boundaries](Verification.md) — the 13 local
   gates, hosted-job map, deployment, packaging, performance, and manual proof.
6. [Troubleshooting](Troubleshooting.md) — toolchain, FileProvider, filters,
   demos, platform prerequisites, docs, and branch safety.

## Choose a path

### Application authors

- [Getting started](GettingStarted.md)
- [State, identity, and lifetime](StateAndIdentity.md)
- [Scene-first migration](SceneMigration.md)
- [Plugins and capability model](Plugins.md)
- [Examples and runnable surfaces](Examples.md)

### Apple application authors

- [Apple application integration](AppleIntegration.md) — AppKit/UIKit scope,
  SwiftUI composition, SwiftData persistence, Foundation Models services,
  accessibility, and evidence boundaries.
- [Apple UI backend](backends/AppleUI.md)
- [macOS application shell](backends/AppleShell.md)
- [Packaging and distribution](Packaging.md)
- [Swift 6.5-dev and SDK 27 audit](Swift65SDK27.md)

### Backend and embedding authors

- [Architecture and ownership](Architecture.md)
- [Terminal backend](backends/TUI.md)
- [Browser/WASM backend](backends/WASM.md)
- [C embedding backend](backends/CEmbed.md)
- [Android/JNI backend](backends/Android.md)
- [Draw-list wire format](adr/0005-drawlist-wire-format.md)
- [MLIR dialect](MLIRDialect.md)

### Contributors and release engineers

- [Contributing](../CONTRIBUTING.md)
- [Toolchain](Toolchain.md)
- [Testing](Testing.md)
- [Verification and evidence boundaries](Verification.md)
- [Capability evidence ledger](Capabilities.md)
- [Packaging and distribution](Packaging.md)
- [Frame-path performance](Performance.md)

## Reference

| Guide | Purpose |
| --- | --- |
| [Capabilities.md](Capabilities.md) | Status vocabulary and current proof per capability |
| [Toolchain.md](Toolchain.md) | Compiler/SDK pin authority and platform exceptions |
| [Testing.md](Testing.md) | Swift Testing suites, filters, sanitizers, and scratch rules |
| [Swift65SDK27.md](Swift65SDK27.md) | Implemented-language probes and bounded modernization decisions |
| [MLIRDialect.md](MLIRDialect.md) | `gama` dialect operations and parser evidence |
| [Plugins.md](Plugins.md) | Static plugin tiers, capability grants, handles, and limitations |
| [Packaging.md](Packaging.md) | WASM site, macOS app, archives, signing, and credential boundary |
| [Performance.md](Performance.md) | Measurement policy, harness, baselines, and profiler evidence |
| [TerminalOwnershipMigration.md](TerminalOwnershipMigration.md) | Noncopyable terminal migration |
| [SceneMigration.md](SceneMigration.md) | Migration from `App.content` to explicit scenes |

Symbol-level API documentation lives beside its module in
`Sources/<Module>/<Module>.docc` and in `///` comments on public declarations.
`scripts/check-docs.sh` validates relative links and builds all discovered
DocC catalogs with warnings as errors. `scripts/check-doc-coverage.sh`
separately requires documentation for every public declaration, except a
small justified allowlist.

## Architecture decisions

[adr/0000-index.md](adr/0000-index.md) is the ordered ADR index. ADRs record
why a settled boundary exists; they do not replace the current guides or
capability ledger.

Current decisions include:

- Own the renderer.
- Pin complete toolchain families.
- Use Swift Testing only.
- Keep signals and subscriptions host-confined.
- Version the DrawList wire format independently of Swift layouts.
- Make terminal/runtime ownership noncopyable.
- Use one shared frame-pump policy with eager resize.

## Designs and historical plans

`superpowers/specs/` contains accepted or implemented design records.
`superpowers/specs/drafts/` contains unresolved proposals. `superpowers/plans/`
contains dated execution plans and may mention work that has since shipped,
changed, or been deferred.

Each record must carry an honest status header. Proposed APIs in a roadmap are
not public API. Current implementation work is summarized once in
[`tasks/todo.md`](../tasks/todo.md); completed delivery history belongs in Git,
merged pull requests, and the dated records.

## Documentation ownership

- Put current how-to and conceptual material in `docs/`.
- Put backend-specific contracts under `docs/backends/`.
- Put symbol navigation and API concepts in the owning `.docc` catalog.
- Put irreversible architecture choices in `docs/adr/`.
- Put proposed designs under `docs/superpowers/specs/`, with drafts clearly
  separated.
- Put capability truth only in `docs/Capabilities.md`.
- Put current implementation tasks only in `tasks/todo.md`.

When a claim changes, update the authoritative current guide instead of adding
a second correction narrative. Preserve dated measurements in
`Performance.md` and dated design decisions in their existing records.

## Documentation gates

```bash
python3 scripts/check-doc-links.py --self-test .
./scripts/check-docs.sh
./scripts/check-doc-coverage.sh
```

The link checker scans the root guides, `docs/`, `Examples/`, and DocC
articles. External URLs are outside that local existence check. DocC resolves
symbol and article links inside each catalog. Public-declaration coverage is a
third, independent proof.
