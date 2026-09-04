# Examples and runnable surfaces

Status: Current map of maintained examples. A source example shows the
integration shape; only the named gate or live workflow establishes runtime
proof. See [Capabilities.md](Capabilities.md) for the latest evidence status.

Gama exercises the same application semantics through several hosting
models. Start with the terminal demo, then choose the example closest to the
host you are integrating.

## Quick map

| Surface | Source | Best command | Evidence produced |
| --- | --- | --- | --- |
| Terminal demo | `Sources/GamaDemo/main.swift` | `.agents/skills/run-gama/driver.sh smoke` | Real TTY launch, frame capture, focus input, cleanup |
| MLIR demo | same executable with `--emit-mlir` | `.agents/skills/run-gama/driver.sh mlir` | Structural and laid-out dialect text |
| macOS shell | `Sources/GamaAppleDemo/` | `.agents/skills/run-gama/driver.sh apple` | Real AppKit launch; manual quit required |
| Minimal AppKit host | `Examples/AppleHost/main.swift` | Apple host tests | Host-view construction pattern, not a standalone app bundle |
| Browser reactor | `Sources/GamaWebDemo/`, `WebHost/` | `./scripts/check-wasm.sh` | WASM build, Node reactor, headless browser interaction |
| Pure C host | `Examples/CEmbed/main.c` | `./scripts/check-c-abi.sh` | Header compile/link/run and frame magic validation |
| Android/JNI | `Examples/Android/` | `./scripts/check-android.sh` and emulator gate | Runtime packaging plus input-driven decoded-frame change |
| Embedded Swift | `Examples/Embedded/main.swift` | `./scripts/check-embedded.sh` | Whole-module compile and relocatable link |
| Performance harness | `Sources/GamaBench/` | documented profile scripts | Measurements only; never a threshold gate |

## Terminal demo

The demo contains a counter, variable step, text field, toggle, progress view,
list, disabled control, static plugin slot, and shared retained layout.

Run the maintained smoke:

```bash
.agents/skills/run-gama/driver.sh smoke
```

Artifacts:

```text
/private/tmp/gama-run-artifacts/before.txt
/private/tmp/gama-run-artifacts/after.txt
```

For interactive inspection:

```bash
.agents/skills/run-gama/driver.sh build
.agents/skills/run-gama/driver.sh launch
.agents/skills/run-gama/driver.sh text
.agents/skills/run-gama/driver.sh focus
.agents/skills/run-gama/driver.sh keys Tab
.agents/skills/run-gama/driver.sh focus
.agents/skills/run-gama/driver.sh quit
```

The driver uses a real tmux TTY because raw terminal mode, escape decoding,
focus attributes, and restoration cannot be proven through a plain pipe.
Plain `capture-pane -p` drops ANSI attributes, so use the driver's `focus`
command when checking the highlighted control.

## MLIR emission

The no-TTY path exercises scene compilation, view rendering, layout, and both
structural and frame-annotated lowering:

```bash
.agents/skills/run-gama/driver.sh mlir
```

The repository's MLIR gate additionally pipes deterministic fixture output to
`mlir-opt --allow-unregistered-dialect`. Successful text emission alone is not
the parser proof.

## Native Apple surfaces

The maintained application shell is:

```bash
.agents/skills/run-gama/driver.sh apple
```

It demonstrates an initial typed group, payload-addressed reopen/focus,
distinct payload windows, and an auxiliary singleton. It blocks until
Command-Q.

`Examples/AppleHost/main.swift` is intentionally smaller: it shows how to put
`GamaHostView` in an `NSWindow`. It does not create a complete
`NSApplication` lifecycle and is not a distributable `.app`. Use
`gama-apple-demo` for shell behavior and the packaging scripts for bundle
evidence.

Programmatic AppKit shell proof:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-apple-shell-tests \
  --filter AppleShellTests
```

Confirm the final line reports six tests; a zero exit with “No matching test
cases” is not a pass.

## Browser/WASM

`GamaWASM` exposes versioned `gama_web_v1_*` functions around one installed
host. `WebHost/` supplies the dependency-free JavaScript reactor and DOM
presentation.

```bash
./scripts/check-wasm.sh
```

The gate builds with the pinned WASM SDK, runs the Node event/frame smoke,
launches the assembled site in headless Chrome, and checks key, pointer,
resize, requestAnimationFrame, and accessibility behavior. The host implements
only the WASI imports required by this reactor; it is not a general filesystem
runtime.

## Pure C embedding

`Examples/CEmbed/main.c` shows the complete version-1 lifecycle:

1. Check `gama_embed_v1_abi_version()`.
2. Create an opaque context.
3. Query and consume a frame.
4. Send validated input and resize operations.
5. Consume the dirty frame.
6. Destroy the context exactly once.

```bash
./scripts/check-c-abi.sh
```

The gate compiles the consumer with warnings as errors, links the static
library, and runs it. Each context is single-render-thread and owns its frame
bytes; returned bytes remain valid only until that context's next frame or
destruction.

## Android/JNI

`Examples/Android/` contains the Kotlin UI, JNI shim, CMake build, Gradle app,
and Swift bootstrap. The cross-build gate packages the transitive Swift
runtime closure and `libc++_shared.so` for the pinned NDK:

```bash
ANDROID_NDK_HOME=/path/to/pinned/ndk ./scripts/check-android.sh
```

The separate emulator gate boots the required API 36 device, installs the APK,
sends input, and requires the decoded Gama frame to change from `Tapped 0` to
`Tapped 1`. Cross-compilation by itself does not prove that round trip. The
tap counter is built inline on a `ReactiveSlot`, so the same assertion is the
Android proof of per-surface `@Reactive` state (ADR 0011).

## Embedded Swift

`Examples/Embedded/main.swift` demonstrates portable composition. Board code
must supply the renderer, event source, clock, memory policy, and device
integration.

```bash
./scripts/check-embedded.sh
```

The gate proves that the unchanged portable core whole-module compiles and
relocatably links under the exact snapshot. It is not physical-board, timing,
power, interrupt, allocator, or safety certification.

## Performance harness

`gama-bench` reports deterministic frame-path measurements and digests. It
does not fail on a timing threshold. Regressions and optimization decisions
must follow the workload, warmup, run-count, toolchain, OS, and evidence rules
in [Performance.md](Performance.md).

## Choose the next guide

- Application author: [GettingStarted.md](GettingStarted.md), then
  [StateAndIdentity.md](StateAndIdentity.md).
- Backend author: [Architecture.md](Architecture.md), then the matching guide
  under `backends/`.
- Apple app author: [AppleIntegration.md](AppleIntegration.md).
- Release or CI work: [Verification.md](Verification.md) and
  [Packaging.md](Packaging.md).
