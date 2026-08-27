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
| Core/builders/layout/drawing | Locally proven: Apple Swift 6.5-dev (main-snapshot-2026-08-21) debug/test/release. Tests are Swift Testing only (no XCTest). Coverage includes Unicode cells, hostile allocation bounds, strict wire UTF-8, identity, host-owned subscriptions, concurrent host isolation, and `ZStack(.topLeading)` overlay vs group sentinel | Keep hosted macOS job and Linux sanitizer job green; revisit ASan `detect_leaks` now that XCTest is gone |
| Scene-first application core | Implemented on `main` and locally proven with 113 Swift Testing cases plus Embedded whole-module compile/link: explicit primary selection, builder order, exact configuration failures, typed group payloads, unavailable window actions, lifecycle ordering, shared-model invalidation, and per-host cancellation | Hosted proof is the six-platform acceptance run for the integrating merge; keep every platform green and retain the explicit-primary ABI tests |
| macOS multi-window shell | Implemented and locally proven on the Apple-shell delivery branch: graph validation before AppKit startup; launch behavior; typed payload deduplication; singleton focus; independent controllers, hosts, and draw lists; executor-confined commands; addressed close/focus lifecycle; final-window residency; Dock reopen; and once-only termination. Six offscreen AppKit tests do not enter the global event loop | A fully green hosted macOS job and complete six-job PR matrix are required before merge. The real Dock/Command-Q smoke remains supplemental and manual; packaging, restoration, close veto, UIKit scene glue, and Windows GUI are not shipped |
| Mac POSIX TUI | Locally proven: Swift Testing PTY suite for split escape/UTF-8 parse and noncopyable raw-mode restoration | Human-facing interactive terminal smoke remains supplemental, not automated acceptance |
| Mac AppKit host | Locally runtime proven: Swift Testing AppKit suite for host instantiation, layout, invalidation, and draw-list production | Keep hosted macOS job green |
| iOS/tvOS/visionOS UIKit host | Locally compile proven: generic simulator builds including touch and hardware-key branches | Keep hosted macOS compile job green |
| Macros | Locally compile/test proven: `@Component`, `@Reactive`, and `#rgb` expansions and diagnostics via Swift Testing + `SwiftSyntaxMacrosGenericTestSupport` | Keep hosted macOS job green |
| DrawList/C ABI | Locally proven: randomized/malformed codec tests and independent context lifecycle | Keep hosted Linux C consumer green |
| MLIR emitter | Locally proven: deterministic generic form parsed by `mlir-opt --allow-unregistered-dialect`; group sentinel emits `gama.group` | Keep hosted macOS MLIR job green |
| Embedded core | Locally compile/link proven: exact 2026-08-21 Swift 6.5-dev snapshot, bare-metal ARM ELF whole-module object and 569,496-byte relocatably linked artifact (re-measured 2026-08-27 with the scene-first core) | Keep hosted Ubuntu artifact job green; no physical-board claim |
| Linux/static Linux | Locally cross-compile proven: matching static Linux SDK and aarch64 musl build | Keep hosted native Linux tests and sanitizers green |
| WebAssembly/browser | Locally runtime proven: matching WASM SDK, Node event/frame smoke, and headless Chrome DOM/key/pointer/resize/rAF/accessibility smoke | Keep hosted Ubuntu browser job green |
| Android/JNI | Locally runtime proven: matching Swift SDK, arm64-v8a/x86_64 payloads, pinned NDK 30.0.15729638, and API 36 emulator input-driven `Tapped 0` to `Tapped 1` frame assertion | Keep required hosted x86_64 emulator job green (adb install flakes are infra, not product) |
| Windows console | Implemented; native console raw/VT/UTF-8/restoration executable is committed. Swift Testing translators run on the Windows job | Required native Windows Swift 6.4.x job stays required. Windows is not 6.5-dev proven |

The full `./scripts/check.sh` and pull-request matrix remain required. Local
green evidence does not substitute for blocked native Windows and hosted jobs,
and no blocked capability may be described as fully shipped.
