# Capability evidence

Status is evidence-based, not inferred from source presence.

## Status vocabulary

- **Implemented** — the code exists and compiles in at least one local
  configuration; no runtime proof is claimed.
- **Locally proven** — a check script or test suite passes on the pinned
  toolchain on this machine; not yet (or not currently) backed by CI.
- **Hosted proven** — the claim is enforced by a required job in the hosted
  "Gama acceptance" matrix.
- **Provisional** — behavior exists but a design decision that could change
  it is still open (see the current work in `tasks/todo.md` and the relevant
  accepted or draft specification).
- **Blocked** — proof is impossible right now for a stated external reason
  (for example, no Windows 6.5-dev snapshot); never described as shipped.

## Evidence snapshot

The latest completed acceptance evidence used for this table is the six-job
hosted run at `8157a68` on 2026-09-02. Linux native/static SDK, macOS plus
iOS/tvOS/visionOS compilation, Windows console, Android cross-build/emulator,
WebAssembly runtime/packaging, and Embedded all passed. Later source or docs
changes require their own local and hosted verification; this snapshot does
not silently transfer to an untested working tree.

| Capability | Current evidence | Remaining proposed/required proof |
| --- | --- | --- |
| Core/builders/layout/drawing | Hosted proven on the pinned Apple/Linux jobs. Tests use Swift Testing only; Linux ASan/TSan and the harness-free LeakSanitizer executable with a required failing negative control cover the sanitizer boundary | Keep every required job green. The generated SwiftPM test process is not the LeakSanitizer proof because it retains XCTest harness metadata |
| Scene-first application core | Hosted proven: explicit primary selection, builder order, typed group payloads, unavailable window actions, lifecycle ordering, shared-model invalidation, and per-host cancellation are in the required matrix | Preserve the explicit-primary ABI tests. The per-surface view-state design is implemented and locally proven (see the `Per-surface @Reactive state` row); its hosted proof is pending |
| macOS multi-window shell | Hosted proven by the macOS job and locally covered by offscreen AppKit tests for graph validation, payload deduplication, focus, independent hosts/draw lists, lifecycle, Dock-reopen routing, and termination | Real Dock/Command-Q and multi-window interaction remains supplemental manual acceptance; close veto, UIKit scene ownership, restoration, and Windows GUI are not shipped |
| Plugin runtime + capability model (Tier 1) | Hosted proven after both the original integration and the lifecycle/identity/command/observation/path hardening passed exact-head six-job matrices. Slots, scenes, revocable commands, deny-by-default grants, service failure, ownership isolation, and filesystem containment are covered | Tier 2 (dynamic loading) and Tier 3 (out of process) are Proposed only; `.network` is reserved; no sandbox claim exists for in-process tiers; live contributed-window teardown on uninstall is deferred |
| Mac POSIX TUI | Locally proven: Swift Testing PTY suite for split escape/UTF-8 parse and noncopyable raw-mode restoration | Human-facing interactive terminal smoke remains supplemental, not automated acceptance |
| Mac AppKit host | Locally runtime proven: Swift Testing AppKit suite for host instantiation, layout, invalidation, and draw-list production | Keep hosted macOS job green |
| VoiceOver / assistive text | Implemented and locally proven in two layers: 17 platform-free Swift Testing cases pin the `DrawList` -> reading-order derivation (`AccessibilitySnapshot`: overpaint precedence, gaps as spaces, style changes not splitting a row, double-width tails, zero-width mark attachment, fill-rect exclusion, blank-row skipping, off-grid clipping), and 8 AppKit cases pin the bridge (container role, one static-text child per row, reading order, cell-scaled frames, element caching across frames, no derivation before a client queries). The adapter exposes text only — it adds no actions and no parallel semantics | UIKit is compile proven only (the simulator builds in `check-apple-platforms.sh`); no hosted runtime execution. A real VoiceOver / Rotor / screen-reader acceptance pass on macOS and iOS is manual and has NOT been performed, so no screen-reader-verified claim exists |
| iOS/tvOS/visionOS UIKit host | Locally compile proven: generic simulator builds including touch and hardware-key branches | Keep hosted macOS compile job green |
| Macros | Locally compile/test proven: `@Component`, `@Reactive`, and `#rgb` expansions and diagnostics via Swift Testing + `SwiftSyntaxMacrosGenericTestSupport`. `@Reactive` expands to a `ReactiveSlot` peer; `@Component` synthesizes the `render(in:)` that binds each slot to the host; `reactive.requires-component` and `component.render-collision` are pinned as errors | Keep hosted macOS job green |
| Per-surface `@Reactive` state | Locally proven 2026-09-04 (ADR 0011): `ViewStateIdentityTests` (8 cases) pin inline persistence with an empty `transientStateIDs`, independent `WindowGroup` surfaces, per-surface writes from a hoisted instance, branch-flip eviction back to a zero baseline, out-of-band invalidation without `observe()`, the transient diagnostic naming its node, `.stateScope` surviving insertion, and host-less rendering staying local; `ReactiveStateLifetimeTests` and `SceneTests.sharedModelIndependentHosts` pass unchanged; 266 tests in 49 suites green; `check-boundaries.sh` requires the `~Sendable` store and slot, `check-concurrency-negative.sh` rejects a `Sendable` slot (3 fixtures), `check-embedded.sh` accepts the erasure, and `gama-demo --emit-mlir` is byte-identical to `origin/main` | Hosted matrix on the merged commit. The WASM and Android behavioral proof on a second and third backend that the spec asks for is not yet added; until it is, the per-surface claim rests on the core test suite only |
| DrawList/C ABI | Locally proven: randomized/malformed codec tests and independent context lifecycle | Keep hosted Linux C consumer green |
| MLIR emitter | Locally proven: deterministic generic form parsed by `mlir-opt --allow-unregistered-dialect`; group sentinel emits `gama.group` | Keep hosted macOS MLIR job green |
| Embedded core | Locally compile/link proven: exact 2026-08-21 Swift 6.5-dev snapshot, bare-metal ARM ELF whole-module object and 631,960-byte relocatably linked artifact (re-measured 2026-09-04 with the per-host `@Reactive` state store: +47,276 bytes, +8.1%, over the same-day `origin/main` baseline of 584,684 bytes — the identity store is the cost) | Keep hosted Ubuntu artifact job green; no physical-board claim |
| Linux/static Linux | Locally cross-compile proven: matching static Linux SDK and aarch64 musl build. The `gama-leak-check` lifecycle can be built and run locally, but Darwin cannot prove LeakSanitizer leak detection | Keep hosted native tests, ASan/TSan, and the suppression-free harness-free LSan clean path plus deliberate-Gama-leak negative control green |
| WebAssembly/browser | Locally runtime proven: matching WASM SDK, Node event/frame smoke, and headless Chrome DOM/key/pointer/resize/rAF/accessibility smoke | Keep hosted Ubuntu browser job green |
| Android/JNI | Hosted proven: matching Swift SDK, arm64-v8a/x86_64 payloads, pinned NDK 30.0.15729638, and required API 36 emulator input-driven `Tapped 0` to `Tapped 1` frame assertion | Keep the x86_64 emulator job green. Install/package-manager failures remain product-gate failures unless the readiness policy emits a specific external-transport diagnosis; KVM and readiness defaults are mechanically checked |
| Windows console | Implemented; native console raw/VT/UTF-8/restoration executable is committed. Swift Testing translators run on the Windows job | Required native Windows Swift 6.4.x job stays required. Windows is not 6.5-dev proven |
| Packaged wasm site | Hosted proven 2026-09-02 at `8157a68`: `scripts/bundle-web.sh` assembled and browser-smoked the site in both acceptance and Pages workflows; Pages deployed successfully, and a separate live fetch returned the titled HTML plus the 9,183,871-byte `application/wasm` payload | Keep both hosted paths green. A successful workflow plus a live asset fetch proves deployment and delivery, not every interactive browser behavior on the public URL |
| macOS `.app` bundle (ad-hoc) | Locally proven (2026-08-27): `scripts/bundle-macos.sh` end to end on the exact pinned toolchain: canonical outside-repo staging, plist-aware manifest branding, `plutil -lint`, ad-hoc codesign with deep-strict verify, and the `--smoke` offscreen launch gate (non-empty DrawList, exit 0). A `ditto` transport archive preserves payload modes and its extracted signature verifies. Ad-hoc output runs on the building machine only; no Gatekeeper claim | Keep the hosted macOS job's archive + `macos-app` upload green. Developer ID + notarization are credential-gated: `scripts/release-macos.sh` is implemented, rebuilds the downloadable ZIP after stapling, and its fail-closed gating is locally proven, but no credentialed run has occurred; the notarized artifact is not claimed until one passes |

The full `./scripts/check.sh` and pull-request matrix remain required. Local
green evidence does not substitute for hosted jobs, and a green Windows 6.4.x
job does not prove Windows 6.5-dev. No blocked capability may be described as
fully shipped.
