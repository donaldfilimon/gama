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
hosted run `33919361432` at merge commit `77812d99` on 2026-09-04. Linux
native/static SDK, macOS plus iOS/tvOS/visionOS compilation, Windows console,
Android cross-build/emulator, WebAssembly runtime/packaging, and Embedded all
passed. Manual UI, assistive-technology, credentialed release,
physical-device, and physical-board proof remain separate. Later source or
docs changes require their own verification; this snapshot does not silently
transfer to an untested working tree.

| Capability | Current evidence | Remaining proposed/required proof |
| --- | --- | --- |
| Core/builders/layout/drawing | Hosted proven on the pinned Apple/Linux jobs. Tests use Swift Testing only; Linux ASan/TSan and the harness-free LeakSanitizer executable with a required failing negative control cover the sanitizer boundary | Keep every required job green. The generated SwiftPM test process is not the LeakSanitizer proof because it retains XCTest harness metadata |
| Scene-first application core | Hosted proven at merge commit `77812d99`: explicit primary selection, builder order, typed group payloads, unavailable window actions, lifecycle ordering, shared-model invalidation, per-host cancellation, and per-surface view state are in the required matrix | Preserve the explicit-primary ABI and per-surface state tests |
| macOS multi-window shell | Hosted proven by the macOS job and locally covered by offscreen AppKit tests for graph validation, payload deduplication, focus, independent hosts/draw lists, lifecycle, Dock-reopen routing, and termination | Real Dock/Command-Q and multi-window interaction remains supplemental manual acceptance; close veto, UIKit scene ownership, restoration, and Windows GUI are not shipped |
| Plugin runtime + capability model (Tier 1) | Hosted proven after both the original integration and the lifecycle/identity/command/observation/path hardening passed exact-head six-job matrices. Slots, scenes, revocable commands, deny-by-default grants, service failure, ownership isolation, and filesystem containment are covered | Tier 2 (dynamic loading) and Tier 3 (out of process) are Proposed only; `.network` is reserved; no sandbox claim exists for in-process tiers; live contributed-window teardown on uninstall is deferred |
| Mac POSIX TUI | Locally proven: Swift Testing PTY suite for split escape/UTF-8 parse and noncopyable raw-mode restoration | Human-facing interactive terminal smoke remains supplemental, not automated acceptance |
| Mac AppKit host | Locally runtime proven: Swift Testing AppKit suite for host instantiation, layout, invalidation, and draw-list production | Keep hosted macOS job green |
| VoiceOver / assistive text | Implemented and locally proven in two layers: 17 platform-free Swift Testing cases pin the `DrawList` -> reading-order derivation (`AccessibilitySnapshot`: overpaint precedence, gaps as spaces, style changes not splitting a row, double-width tails, zero-width mark attachment, fill-rect exclusion, blank-row skipping, off-grid clipping), and 8 AppKit cases pin the bridge (container role, one static-text child per row, reading order, cell-scaled frames, element caching across frames, no derivation before a client queries). The adapter exposes text only — it adds no actions and no parallel semantics | UIKit is compile proven only (the simulator builds in `check-apple-platforms.sh`); no hosted runtime execution. A real VoiceOver / Rotor / screen-reader acceptance pass on macOS and iOS is manual and has NOT been performed, so no screen-reader-verified claim exists |
| iOS/tvOS/visionOS UIKit host | Locally compile proven: generic simulator builds including touch and hardware-key branches | Keep hosted macOS compile job green |
| Macros | Locally compile/test proven: `@Component`, `@Reactive`, and `#rgb` expansions and diagnostics via Swift Testing + `SwiftSyntaxMacrosGenericTestSupport`. `@Reactive` expands to a `ReactiveSlot` peer; `@Component` synthesizes the `render(in:)` that binds each slot to the host; `reactive.requires-component` and `component.render-collision` are pinned as errors | Keep hosted macOS job green |
| Per-surface `@Reactive` state | Hosted proven 2026-09-04 at merge commit `77812d99` (ADR 0011): `ViewStateIdentityTests` (8 cases) pin inline persistence with an empty `transientStateIDs`, independent `WindowGroup` surfaces, per-surface writes from a hoisted instance, branch-flip eviction back to a zero baseline, out-of-band invalidation without `observe()`, the transient diagnostic naming its node, `.stateScope` surviving insertion, and host-less rendering staying local; `ReactiveStateLifetimeTests` and `SceneTests.sharedModelIndependentHosts` pass unchanged; 266 tests in 49 suites are green; boundaries require the `~Sendable` store and slot, concurrency negatives reject a `Sendable` slot, Embedded accepts the erasure, and emitted MLIR is unchanged. The macro-authored WASM backend is hosted proven by exact `0` to `1` Node output and a `state=0->0->1` browser marker. The macro-authored Android backend is hosted proven on both ABIs and API 36 by an acceptance-only exact decoded `Tapped 0` to `Tapped 1` transition; ordinary launch is separately required to stay outside acceptance mode | Keep Apple, WASM, and Android jobs green. Manual GUI and assistive-technology acceptance remain separate |
| Strict memory safety + explicit imports | Hosted proven 2026-09-04 at merge commit `77812d99` (ADR 0012): every shipped library and macro target builds under `-strict-memory-safety` with the `StrictMemorySafety` group promoted to an error, and every Swift target builds under `InternalImportsByDefault`, with no diagnostics. The matrix covers Apple debug/test/release, Embedded compile/link, C ABI consumer, static Linux (`GamaCore` + `GamaTUI`, including the Glibc branch), WASM SDK build plus Node/browser smokes, iOS/tvOS/visionOS compile, boundaries, concurrency negatives, docs, and doc coverage | Keep the six-job matrix green. Windows remains on the required Swift 6.4.x exception. Executables and `GamaTests` are deliberately outside strict-memory scope; ADR 0012 records their measured counts, and extending the scope is a separate decision |
| DrawList/C ABI | Locally proven: randomized/malformed codec tests and independent context lifecycle | Keep hosted Linux C consumer green |
| MLIR emitter | Locally proven: deterministic generic form parsed by `mlir-opt --allow-unregistered-dialect`; group sentinel emits `gama.group` | Keep hosted macOS MLIR job green |
| Embedded core | Locally compile/link proven: exact 2026-08-21 Swift 6.5-dev snapshot, bare-metal ARM ELF whole-module object and 631,960-byte relocatably linked artifact (re-measured 2026-09-04 with the per-host `@Reactive` state store: +47,276 bytes, +8.1%, over the same-day `origin/main` baseline of 584,684 bytes — the identity store is the cost) | Keep hosted Ubuntu artifact job green; no physical-board claim |
| Linux/static Linux | Locally cross-compile proven: matching static Linux SDK and aarch64 musl build. The `gama-leak-check` lifecycle can be built and run locally, but Darwin cannot prove LeakSanitizer leak detection | Keep hosted native tests, ASan/TSan, and the suppression-free harness-free LSan clean path plus deliberate-Gama-leak negative control green |
| WebAssembly/browser | Hosted runtime proven at merge commit `77812d99`: the matching WASM SDK, exact Node event/frame transition, and headless Chrome DOM/key/pointer/resize/rAF/accessibility smoke all pass | Keep the hosted Ubuntu browser job green |
| Android/JNI | Hosted proven at merge commit `77812d99`: the matching Swift SDK, arm64-v8a/x86_64 payloads, pinned NDK 30.0.15729638, and required API 36 emulator acceptance launch produce the exact decoded `Tapped 0` to `Tapped 1` transition. A separate ordinary launch must contain no acceptance marker | Keep the x86_64 emulator job green. Install/package-manager failures remain product-gate failures unless the readiness policy emits a specific external-transport diagnosis; KVM and readiness defaults are mechanically checked |
| Windows console | Implemented; native console raw/VT/UTF-8/restoration executable is committed. Swift Testing translators run on the Windows job | Required native Windows Swift 6.4.x job stays required. Windows is not 6.5-dev proven |
| Packaged wasm site | Hosted proven 2026-09-04 at merge commit `77812d99`: `scripts/bundle-web.sh` assembled and browser-smoked the site in both the acceptance matrix and Pages run `33919361438`; Pages deployed successfully, and a separate live fetch returned `<title>Gama</title>` plus an HTTP 200 `application/wasm` payload of 9,297,539 bytes | Keep both hosted paths green. A successful workflow plus a live asset fetch proves deployment and delivery, not every interactive browser behavior on the public URL |
| macOS `.app` bundle (ad-hoc) | Locally proven (2026-08-27): `scripts/bundle-macos.sh` end to end on the exact pinned toolchain: canonical outside-repo staging, plist-aware manifest branding, `plutil -lint`, ad-hoc codesign with deep-strict verify, and the `--smoke` offscreen launch gate (non-empty DrawList, exit 0). A `ditto` transport archive preserves payload modes and its extracted signature verifies. Ad-hoc output runs on the building machine only; no Gatekeeper claim | Keep the hosted macOS job's archive + `macos-app` upload green. Developer ID + notarization are credential-gated: `scripts/release-macos.sh` is implemented, rebuilds the downloadable ZIP after stapling, and its fail-closed gating is locally proven, but no credentialed run has occurred; the notarized artifact is not claimed until one passes |

The full `./scripts/check.sh` and pull-request matrix remain required. Local
green evidence does not substitute for hosted jobs, and a green Windows 6.4.x
job does not prove Windows 6.5-dev. No blocked capability may be described as
fully shipped.
