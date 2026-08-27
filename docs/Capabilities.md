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
  it is still open (see tasks/todo.md Slice C and the spec drafts).
- **Blocked** — proof is impossible right now for a stated external reason
  (e.g. no Windows 6.5-dev snapshot); never described as shipped.

| Capability | Current evidence | Remaining proposed/required proof |
| --- | --- | --- |
| Core/builders/layout/drawing | Locally proven: Apple Swift 6.5-dev (main-snapshot-2026-08-21) debug/test/release. Tests are Swift Testing only (no XCTest). Coverage includes Unicode cells, hostile allocation bounds, strict wire UTF-8, identity, host-owned subscriptions, concurrent host isolation, and `ZStack(.topLeading)` overlay vs group sentinel | Keep hosted macOS and Linux sanitizer jobs green; Linux leak proof is the harness-free executable plus its required failing negative control, not the XCTest-hosted test process |
| Scene-first application core | Implemented on `main` and locally proven with 113 Swift Testing cases plus Embedded whole-module compile/link: explicit primary selection, builder order, exact configuration failures, typed group payloads, unavailable window actions, lifecycle ordering, shared-model invalidation, and per-host cancellation | Hosted proof is the six-platform acceptance run for the integrating merge; keep every platform green and retain the explicit-primary ABI tests |
| macOS multi-window shell | Implemented and locally proven on the Apple-shell delivery branch: graph validation before AppKit startup; launch behavior; typed payload deduplication; singleton focus; independent controllers, hosts, and draw lists; executor-confined commands; addressed close/focus lifecycle; final-window residency; Dock reopen; and once-only termination. Six offscreen AppKit tests do not enter the global event loop | A fully green hosted macOS job and complete six-job PR matrix are required before merge. The real Dock/Command-Q smoke remains supplemental and manual; packaging, restoration, close veto, UIKit scene glue, and Windows GUI are not shipped |
| Plugin runtime + capability model (Tier 1) | Implemented; original PR #33 head passed all six hosted acceptance jobs and merged. The post-merge hardening is locally proven by 39 focused Swift Testing cases across runtime (deny-by-default, all-or-nothing, exact-match, ABI, service fail-closed, ownership isolation, plugin-scoped observation cleanup, lifecycle invalidation, deinit deactivation), slots (IR, actions, stable survivor identity, reactive path), namespaced scene contributions with primary-role rejection and offscreen AppKit shell open/focus, deterministic revocable commands, and hostile-path filesystem containment; demo slot wired through HostServices.standard | The hardening follow-up still requires its own exact-head six-job acceptance matrix; the merged PR #33 matrix proves only the original head. Tier 2 (dylib) and Tier 3 (out-of-process) are Proposed only; `.network` is reserved; no sandbox claim exists for in-process tiers; shell teardown of contributed windows on uninstall is deferred |
| Mac POSIX TUI | Locally proven: Swift Testing PTY suite for split escape/UTF-8 parse and noncopyable raw-mode restoration | Human-facing interactive terminal smoke remains supplemental, not automated acceptance |
| Mac AppKit host | Locally runtime proven: Swift Testing AppKit suite for host instantiation, layout, invalidation, and draw-list production | Keep hosted macOS job green |
| iOS/tvOS/visionOS UIKit host | Locally compile proven: generic simulator builds including touch and hardware-key branches | Keep hosted macOS compile job green |
| Macros | Locally compile/test proven: `@Component`, `@Reactive`, and `#rgb` expansions and diagnostics via Swift Testing + `SwiftSyntaxMacrosGenericTestSupport` | Keep hosted macOS job green |
| DrawList/C ABI | Locally proven: randomized/malformed codec tests and independent context lifecycle | Keep hosted Linux C consumer green |
| MLIR emitter | Locally proven: deterministic generic form parsed by `mlir-opt --allow-unregistered-dialect`; group sentinel emits `gama.group` | Keep hosted macOS MLIR job green |
| Embedded core | Locally compile/link proven: exact 2026-08-21 Swift 6.5-dev snapshot, bare-metal ARM ELF whole-module object and 569,496-byte relocatably linked artifact (re-measured 2026-08-27 with the scene-first core) | Keep hosted Ubuntu artifact job green; no physical-board claim |
| Linux/static Linux | Locally cross-compile proven: matching static Linux SDK and aarch64 musl build. The `gama-leak-check` lifecycle can be built and run locally, but Darwin cannot prove LeakSanitizer leak detection | Keep hosted native tests, ASan/TSan, and the suppression-free harness-free LSan clean path plus deliberate-Gama-leak negative control green |
| WebAssembly/browser | Locally runtime proven: matching WASM SDK, Node event/frame smoke, and headless Chrome DOM/key/pointer/resize/rAF/accessibility smoke | Keep hosted Ubuntu browser job green |
| Android/JNI | Locally runtime proven: matching Swift SDK, arm64-v8a/x86_64 payloads, pinned NDK 30.0.15729638, and API 36 emulator input-driven `Tapped 0` to `Tapped 1` frame assertion | Keep required hosted x86_64 emulator job green (adb install flakes are infra, not product) |
| Windows console | Implemented; native console raw/VT/UTF-8/restoration executable is committed. Swift Testing translators run on the Windows job | Required native Windows Swift 6.4.x job stays required. Windows is not 6.5-dev proven |
| Packaged wasm site | Locally proven (2026-08-27): `scripts/bundle-web.sh` assembles `index.html` + `gama.js` + `gama-web-demo.wasm` into `$GAMA_DIST_ROOT/web` with the exact pinned Swift revision/SDK; the headless-Chrome browser smoke passes against the assembled directory and asserts the manifest-configured title | Keep the hosted wasm job's bundle step and `wasm-site` upload green |
| macOS `.app` bundle (ad-hoc) | Locally proven (2026-08-27): `scripts/bundle-macos.sh` end to end on the exact pinned toolchain: canonical outside-repo staging, plist-aware manifest branding, `plutil -lint`, ad-hoc codesign with deep-strict verify, and the `--smoke` offscreen launch gate (non-empty DrawList, exit 0). A `ditto` transport archive preserves payload modes and its extracted signature verifies. Ad-hoc output runs on the building machine only; no Gatekeeper claim | Keep the hosted macOS job's archive + `macos-app` upload green. Developer ID + notarization are credential-gated: `scripts/release-macos.sh` is implemented, rebuilds the downloadable ZIP after stapling, and its fail-closed gating is locally proven, but no credentialed run has occurred; the notarized artifact is not claimed until one passes |

The full `./scripts/check.sh` and pull-request matrix remain required. Local
green evidence does not substitute for blocked native Windows and hosted jobs,
and no blocked capability may be described as fully shipped.
