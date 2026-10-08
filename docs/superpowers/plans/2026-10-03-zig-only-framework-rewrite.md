# Gama Zig-Only Framework Rewrite Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Execute one implementation task at a time, followed by a fresh reviewer checking specification compliance and code quality. Track progress with checkboxes and a durable ledger.

**Goal:** Replace the Swift framework with a Zig framework built from an exact Zig master revision, remove Studio and Qt, and use only first-party code and Zig's standard library.
**Architecture:** Keep one portable scene, state, layout, and drawing engine. Terminal, plain-output, embedding, and freestanding adapters consume that engine. Applications use ordinary Zig structs and compile-time composition.
**Tech Stack:** Zig 0.17.0-dev.2338+b46a7f3a2, revision b46a7f3a25a61c68bbc25759087a01095dc8446e; std only, with platform linkage required by std.
**Spec:** ../specs/2026-10-03-zig-only-framework-design.md
**Status:** Completed on 2026-10-03; verification and proof limits are recorded separately.

## Global Constraints

- Work in the canonical checkout on main. Do not create a branch or worktree, commit, push, or open a PR.
- Use main at b8ce774285c79d83a4bf3ffff7b11975d4716af2 as the behavioral baseline. Preserve separate native UI branches without incorporating them.
- Preserve the uncommitted MLIR cleanup, Package.resolved, and working data before removing surrounding implementation.
- Remove Studio, Qt, Swift implementation and macros, Apple hosts, Android/JNI applications, browser hosts, and obsolete packaging.
- No package dependencies, vendored libraries, production C helpers, handwritten OS bindings, or Apple frameworks. Owned Unicode data/generated tables are permitted.
- Retain portable components, state/identity, layout, drawing, static plugins, terminal/plain output, C embedding, freestanding WASM exports, textual MLIR, and embedded compilation.
- Interactive terminal on macOS/Linux. Windows retains plain/headless operation; interactive console is excluded.
- Update root guidance, docs, gates, and CI together. Retire Pages. Preserve runner registration/credentials.
- Distinguish native runtime proof, cross-compilation, artifact inspection, and unverified execution.
- Initial macOS compiler archive SHA256: 6823e45e4f4b9b7eab5230baa06d9e59ea9e1f19e88d3eb29946d02111bfedd4. Pin this snapshot, never silently follow rolling master.
- Each task: failing regression, implementation, verification, fresh review. No commits: freeze task diffs and file hashes; preserve all reports/ledger.

## Review Focus

- Grapheme clusters remain intact during cursor movement, deletion, wrapping.
- Removed state/plugins invalidate cached handles.
- OOM preserves last presented frame and safe teardown.
- Hostile dimensions/encoded data remain bounded.
- Interrupted blocked terminal output restores settings without blocking in signal handlers.

## Interfaces

The design document defines binding interfaces and ownership. Host(App).create(allocator, app: *App) Error!*Self; destroy/handle/invalidate. Application outlives hosts. Components render(*const Self,*BuildContext) Error!Node. prepare(size) Error!?PreparedFrame then commit/abort: paint/serialize before publish. context.state(T,slot,initial) Error!StateRef(T), keyed by NodeID/slot; reads borrow, writes clone owned values. Managed types have clone/destruction hooks. Typed actions reject temporary pointer/slice captures; signals are app-owned and explicitly subscribed. Handles cannot outlive hosts; generation checks reject stale handles while host lives. DrawList wire v1/C embed v1 signatures retained with new -4 OOM. Browser gama_web v1/v2 retired. New import-free gama_wasm_v1 init/shutdown/key/pointer/resize/needs_frame/frame/frame_ptr/frame_len. frame: 1 published, 0 clean, -1 uninitialized, -2 invalid key, -3 too large, -4 OOM; failed init preserves installed host.

### Task 1: Preserve the baseline and capture behavioral fixtures
**Ownership:** Migration preservation and parity fixtures.
- [x] Record HEAD, dirty/staged changes, untracked data, active checkout owners. Preserve MLIR patch and working data durably before deletion.
- [x] Capture portable geometry, identity, state lifetime, focus/actions, editing, cells, ANSI/plain, DrawList, HTML, plugins, MLIR behavior.
- [x] Run relevant existing Swift tests with separate external scratch; record actual commands/counts, fixture hashes, attributable failures.
- [x] Classify every existing surface retained/retired; freeze inventory.
**Deliverable:** Reproducible parity corpus independent of Swift source deletion.

### Task 2: Establish the Zig package and verification runner
**Ownership:** build.zig, build.zig.zon, toolchain manifest, src/root.zig, verification tools.
- [x] Failing checks: wrong compiler, dependencies, forbidden sources/imports, zero-test suites.
- [x] Create package and executed tests using addRunArtifact, not compile-only.
- [x] Add test, compile-fail, check, check-portable, demo, bench steps.
- [x] Exact pin/format checks; portable module consumable on macOS; separate libc-free artifacts.

### Task 3: Port geometry, identity, Unicode, and text editing
**Ownership:** Portable geometry/text, Unicode generator/fixtures.
- [x] Failing tests for saturating geometry, exact NodeID mixing, wrapping, cursor/selection, width.
- [x] Owned extended-grapheme implementation/tables from Unicode 17.0; separate current terminal-width policy.
- [x] Malformed UTF-8, combining, flags, ZWJ emoji, VS16, Unicode control-key classification.
- [x] Official Unicode 17.0 GraphemeBreakTest corpus, parity fixtures, allocation failures.

### Task 4: Port scene and component authoring
**Ownership:** Scenes, Node IR, composition, compile-fail fixtures.
- [x] Missing/multiple primary, duplicate IDs, collection identity, branches, malformed signatures.
- [x] All portable primitives/modifiers: stacks, fields, toggles, progress, lists, virtualized lists, styles, geometry, state scopes.
- [x] Compile-time rgb; native-region portable fallbacks.
- [x] Authored examples produce baseline IR/identity traces.

### Task 5: Implement host-owned state, actions, and subscriptions
**Ownership:** Stores, bindings, captures, signals, completion, lifecycle.
- [x] Rerender retention, host isolation, positional/identified collections, replacement/removal/stale handles/cancellation.
- [x] clone/deinit ownership, typed captures/generations, first-result-wins completion.
- [x] Reject reentrancy; native thread confinement without hosted facilities in core.
- [x] OOM construction/update/teardown; zero leaks.

### Task 6: Port layout and the shared frame pump
**Ownership:** Measurement/layout/focus/frame transactions.
- [x] Per-axis flexibility, clipping/overlays, eager resize, dirty gating, reconciliation/follow-up.
- [x] Baseline integer two-pass layout/shared pump.
- [x] Stage registrations/resources; commit only after paint/serialization.
- [x] Failure preserves presentation and dirty retry; accepted model changes survive failed render.

### Task 7: Port drawing and serializers
**Ownership:** Cell buffers/painter/DrawList/ANSI/plain/HTML.
- [x] Exact wire/styled runs/wide cells/escaping/plane ownership.
- [x] maximum_cell_count = 16 * 1024 * 1024; baseline oversized-grid normalization.
- [x] Bounded strict decode: magic/version/counts/truncation/UTF-8/trailing.
- [x] Goldens, deterministic malformed-input fuzz, allocation/resize failure.

### Task 8: Port static plugins and std-backed services
**Ownership:** Runtime/capabilities/contributions/services.
- [x] Exact grants, absent required services, failed activation, stable IDs/order/revocation.
- [x] Cooperative Tier 1 only; no dynamic/process plugins.
- [x] Optional injected std.Io log/monotonic clock/filesystem; lexical containment.
- [x] Host isolation/uninstall cancellation; explicit unavailable freestanding services.

### Task 9: Implement terminal and adaptive plain output
**Ownership:** POSIX lease/input/rescue/loop.
- [x] Zig PTY tests: keyboard/mouse/fragments/Unicode/resize/EOF/write failure/restoration.
- [x] std raw-mode and allocation-free signal handlers; displaced dispositions preserved.
- [x] Adaptive stdout/flag precedence/plain 80x24/quiescence/explicit completion.
- [x] Native macOS/Linux where available; normal/error/managed-signal cleanup; external exit/uncatchable termination documented.

### Task 10: Implement C embedding and import-free WASM
**Ownership:** ABI adapters/header/export verification.
- [x] C signatures/diagnostic app/clamping/status precedence/clean frames/borrowed bytes.
- [x] Context lifecycle and explicit OOM.
- [x] Specified import-free pull WASM with std.heap.wasm_allocator.
- [x] Native linked consumer runs; Zig artifact inspection of signatures/memory/imports/exports; separate WASM execution proof.

### Task 11: Port MLIR emission and freestanding builds
**Ownership:** Text lowering/embedded artifacts.
- [x] Operation order/escaping/i64 attrs/determinism.
- [x] Emitter without inherited unused builder counter.
- [x] Cortex-M4 portable core+pump compile/link, bounded caller storage, no hosted deps.
- [x] New measured Zig size baseline; goldens, no parser claim without parser run.

### Task 12: Complete examples, benchmarks, and repository cutover
**Ownership:** Examples/docs/guidance/CI/retired surfaces.
- [x] Counter, form/editing, plugins, plain, embedding, freestanding examples.
- [x] Deterministic benchmark, measurements without unmeasured speed claim.
- [x] After retained parity green: remove tracked Swift/Studio/Qt/old hosts/SDK helpers/packaging; preserve working data/other worktrees.
- [x] Update AGENTS/docs/Capabilities/CI; retire Pages/Swift gates; preserve Package.resolved.
- [x] Fresh whole-change review, fixes, gates.

## Acceptance

zig build check plus existing check-script entrypoint:
- Pin/format/empty dependencies/source boundaries/docs/evidence.
- Executed debug/safe/fast native tests, compile-fail, OOM/teardown.
- Portable parity and native TUI/plain/embed runtime.
- macOS, Linux x86_64/aarch64, Windows headless, wasm32-freestanding, Cortex-M4 cross builds.
- Symbols/imports/wire/freestanding boundaries.
Completion requires retained scope gates green, working examples, approved removal inventory, preserved inherited work, independent review. Cross builds do not qualify unavailable foreign runtime hosts/WASM engines/hardware. No Git publication.
