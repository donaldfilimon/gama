# AGENTS.md

This is the canonical guide for agents working in this repository. `CLAUDE.md` defers to it.

## What this is

Gama Studio is a document-centric 3D authoring app. It is not the gama UI framework (`donaldfilimon/gama`, checked out at `~/Desktop/Gama`) and not `~/dev/active/gama-qt`.
- The product vision is `docs/spec/2026-09-23-unified-usd-realitykit-spec.md`. It is **Vision**, not a capability claim: most of it is not built.
- What exists today is Phases 0 and 1:
  - `GamaAuthoring`: a tested authoring core with no renderer and no UI.
  - `GamaReality`: an Apple-only RealityKit projection of it. There is no viewport or UI yet.
- The repo is local-only with no remote. Commit on `main`.

## Gate

```bash
./tools/check.sh > check.log 2>&1; echo "EXIT:$?"
```

It is green only when the log ends with `check.sh: PASSED`. It runs, in order:
1. A toolchain assertion (6.5-dev).
2. The standard-library-only import ban on `Sources/GamaAuthoring`, which fails closed.
3. `swift build` with warnings as errors.
4. `swift test`, with a test-count floor (`MIN_TESTS`) applied to the sum over all test targets. Every target's run must pass.

When you add tests, raise the floor. Never lower it to make the gate pass.

## Toolchain

- `.swift-version` pins `main-snapshot-2026-08-21`, the same pin as gama. Run `unset TOOLCHAINS`, then `swiftly run swift <build|test>`.
- The manifest stays `swift-tools-version: 6.4` to match gama.
- The platform floor is macOS 15 / iOS 18 / tvOS 26 / visionOS 1, set by RealityKit's cone and cylinder meshes (ADR 0002).
- Only macOS is built and tested. Other platforms are unmeasured.
- The repo sits outside iCloud, so `swift test` runs in place.
- Single suite: `swiftly run swift test --filter CommandRoundTripTests`. The filter matches the struct name, not the `@Suite` title. A filter that matches nothing exits 0, so check the count.

## Invariants (spec §64, as built here)

1. **The document is the source of truth.** No renderer, UI, or AI owns scene state.
2. **Every mutation is a `DocumentCommand` executed through `EditorSession`.** `SceneDocument` has no public mutators. UI, console, graphs, and AI must produce commands, never edit the document.
3. **A command returns its exact inverse.** Every new command needs a case in `CommandRoundTripTests.cases`. The test executes it, undoes it, redoes it, and undoes it again, comparing content each time.
4. **A refused edit changes nothing:** not the document, history, revision, selection, or `pendingChanges`. Commands validate their inputs and may throw midway, because the session applies them to a copy.
5. **`GamaAuthoring` imports nothing.** The gate enforces this. Platform code goes in a separate target that depends on it.
6. **Identifiers are deterministic and never reused.** Don't introduce `UUID` into the core.
7. **The change feed names what changed.** A projection reads current values from the document.
8. **The RealityKit bridge is read-only and incremental** (ADR 0002).
   - It never writes the document.
   - It skips changes naming entities a later change removed.
   - It re-sequences only the containers it touched, because RealityKit does not keep sibling order on removal.
   - Any change to the bridge must keep `BridgeConvergenceTests` green: incremental projection must equal a fresh rebuild after every drain.

Decisions and their reasons are in `docs/adr/` (0001: the value document and commands; 0002: the RealityKit bridge).

## Layout

- `Sources/GamaAuthoring/`
  - `SceneDocument` (value document plus `validate()`)
  - `Commands` (create, delete, restore, duplicate, rename, set/remove component, reparent)
  - `EditorSession` (command bus, undo/redo, transactions, change feed, selection)
  - `Components` and `Math` (transform, mesh primitive, material, visibility)
  - `Selection`, `SceneChange`, `AuthoringError`
- `Sources/GamaReality/`: `RealityBridge` (entity maps, `apply`, `rebuild`, picking via `id(for:)`), `PrimitiveMeshes` (unit-size mesh cache), and `MaterialProjection` (`PhysicallyBasedMaterial`). Every file sits inside `#if canImport(RealityKit)`.
- `Tests/GamaAuthoringTests/`: Swift Testing only. `SampleScene` in `Fixtures.swift` is the shared fixture.
- `Tests/GamaRealityTests/`: `@MainActor` suites.
  - `Support.swift` holds the tree snapshot, a copy of `SampleScene`, and a seeded command generator. Test targets can't share files.
  - Convergence, incrementality, and mapping tests.

## Not built (next phases, in order)

1. **An editor UI of Gama views with a native RealityKit viewport in the Apple shell.** Embedding a native view is a gama design question, raised there first.
2. **Camera and light components in the document**, then their projection in the bridge. Selection highlighting comes after that.
3. **A USD stage abstraction plus save/load**, implemented against the real SDK APIs, never invented signatures.
4. **A command console** that parses into the same commands.
5. **A typed graph framework.**

None of these may be described as existing until it has a target and passing tests.
