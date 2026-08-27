# Gama umbrella — identity-keyed view state — DRAFT

Date: 2026-08-27. Status: **draft for review** (nothing here is approved;
everything not labeled "exists today" is Proposed). Raised by the
`gama-demo` keyboard-activation investigation of 2026-08-27, which found no
framework activation bug and one real API sharp edge.

## Problem

`@Reactive` expands to a `GamaCore.Signal` stored in the component instance
(`Sources/GamaMacrosImpl/Plugin.swift`, `ReactiveMacro`). Scene content is a
closure the host evaluates on **every frame** — `Window._collectScenes`
returns `{ context in content().render(in: context) }`
(`Sources/GamaCore/Scene.swift:213`), and `WindowGroup` does the same with a
payload. A component constructed inside that closure is therefore a fresh
value on every frame, with fresh signals.

Exists today: activation works on both input paths. A press invokes the
registered action, the action mutates the *current* instance's signal, the
host marks itself dirty, and the next `pump` builds a **new** instance
initialized to its declared defaults. The mutation is silently discarded and
the frame paints the initial value. This is not keyboard-specific: pointer
presses lose state identically. Measured 2026-08-27 — an inline-constructed
`@Reactive` counter reports the action ran while the painted frame still
reads `count 0`.

The sharp edge is that nothing reports it. There is no diagnostic, no
warning, and no test failure — only a control that appears inert. The
`@Reactive` documentation showed a component with no instruction about where
the instance must live, which is exactly the shape that fails.

Landed already (not this spec's scope): `gama-demo` stores its panel on the
app, `MacroUsageTests` pins activation-plus-persistence on both input paths,
and the `@Reactive` doc comment states the lifetime rule.

## Options

1. **Documentation only** (status quo after the 2026-08-27 fix). State the
   rule, keep per-frame closure evaluation. Cost: zero. Risk: the next
   author hits the same silent failure, because the compiler still accepts
   the broken shape.

2. **Memoize scene content per surface.** Evaluate `content()` once per
   `SceneSurface` and reuse the value. Small change, but it only fixes the
   *root* view: any nested `@Component` constructed inside a parent's `body`
   is still rebuilt per evaluation, so the general guarantee is not
   delivered. It also freezes plain values captured by the closure, which
   silently changes what `invalidate()` + `pump` observes. Rejected as a
   partial fix with a semantic cost.

3. **Identity-keyed host state (proposed).** `FrameHost` owns a state store
   keyed by the `NodeID` already threaded through `BuildContext`;
   `@Reactive` resolves its `Signal` from that store on first build for an
   identity and reuses it afterward. State then survives rebuilds wherever
   the component sits, which is the `@State` guarantee the macro's
   documentation advertises.

   It also settles a second axis the workaround cannot. Every surface built
   from one scene declaration captures the same content closure
   (`makeRender` in `Sources/GamaCore/Scene.swift`), so a component instance
   stored on the app — or an app-level `Signal` — is *one* instance behind
   every open window of a `WindowGroup`. That is correct for deliberately
   shared model state (`SceneTests.swift` pins that case) and wrong for
   state each window should own. A store owned by `FrameHost` is per-surface
   by construction, so per-window state falls out of the same design rather
   than needing a second mechanism.

## Open questions for option 3

- Identity stability: `BuildContext.id` is structural (`child(n)` paths).
  Conditional branches and `ForEach` reorder nodes, so the store needs the
  same identity rules that focus reconciliation already depends on, plus a
  decision on explicit `.id(_:)` overrides.
- Eviction: state for identities absent from a completed build pass must be
  released, or a long-running app leaks one signal per vanished node.
- Embedded-Swift budget: the store is per-host allocation in GamaCore, which
  is stdlib-only. Cost must be measured against the Embedded gate, not
  assumed.
- Macro shape: `@Reactive` currently initializes storage via
  `@storageRestrictions(initializes:)`. Resolving from a host store means
  the declared default becomes a *first-build* default; the expansion and
  its diagnostics change.
- Diagnostic path: even without option 3, a build-time or debug-build
  diagnostic for "component with `@Reactive` state constructed inside a
  scene closure" would convert a silent failure into a loud one. Worth
  costing separately; it may be the cheapest real improvement.

## Evidence policy

Nothing here is implemented. `docs/Capabilities.md` gains no row until a
design is approved and its gate passes.
