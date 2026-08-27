# Capability evidence

Status is evidence-based, not inferred from source presence.

| Capability | Current evidence | Remaining proposed/required proof |
| --- | --- | --- |
| Core/builders/layout/drawing | Locally proven: Apple Swift 6.4 debug build and 73 tests, including Unicode cells, hostile allocation bounds, strict wire UTF-8, identity, host-owned subscriptions, and concurrent host isolation | Hosted macOS/Linux sanitizer jobs |
| Mac POSIX TUI | Locally proven: split escape/UTF-8 parser tests and noncopyable raw-mode restoration on a real PTY | Human-facing interactive terminal smoke remains supplemental, not automated acceptance |
| Mac AppKit host | Locally runtime proven: host instantiation, layout, invalidation, and draw-list production | Hosted macOS job |
| iOS/tvOS/visionOS UIKit host | Locally compile proven: generic simulator builds including touch and hardware-key branches | Hosted macOS compile job |
| Macros | Locally compile/test proven: `@Component`, `@Reactive`, and `#rgb` expansions and diagnostics | Hosted macOS job |
| DrawList/C ABI | Locally proven: randomized/malformed codec tests and independent context lifecycle | Hosted Linux C consumer |
| MLIR emitter | Locally proven: deterministic generic form parsed by `mlir-opt --allow-unregistered-dialect` | Hosted macOS MLIR job |
| Embedded core | Locally compile/link proven: exact 2026-08-14 Swift 6.4 snapshot, bare-metal ARM ELF whole-module object and 465,656-byte relocatably linked artifact | Hosted Ubuntu artifact job; no physical-board claim |
| Linux/static Linux | Locally cross-compile proven: matching static Linux SDK and aarch64 musl build | Hosted native Linux tests and sanitizers |
| WebAssembly/browser | Locally runtime proven: matching WASM SDK, Node event/frame smoke, and headless Chrome DOM/key/pointer/resize/rAF/accessibility smoke | Hosted Ubuntu browser job |
| Android/JNI | Locally runtime proven: matching Swift SDK, arm64-v8a/x86_64 payloads, pinned NDK 30.0.15729638, and API 36 emulator input-driven `Tapped 0` to `Tapped 1` frame assertion | Required hosted x86_64 emulator job |
| Windows console | Implemented but blocked on hosted proof: record translators plus a native console raw/VT/UTF-8/restoration executable are committed | Required native Windows Swift 6.4 job |

The full `./scripts/check.sh` and pull-request matrix remain required. Local
green evidence does not substitute for blocked native Windows and hosted jobs,
and no blocked capability may be described as fully shipped.
