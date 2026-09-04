# Gama Framework

Gama is a modular declarative UI framework written in Swift. A single
retained render tree drives terminal, CoreGraphics, WebAssembly, C/Android,
MLIR, and Embedded Swift integrations.

```swift
import GamaCore
import GamaMacros
import GamaTUI

@Component
struct Counter {
    @Reactive var count: Int = 0

    var body: some View {
        VStack {
            Text("count: \(count)").bold().foregroundColor(#rgb("F80"))
            Button("Increment") { count += 1 }
        }
        .padding()
        .border(.rounded, title: "counter")
    }
}

struct CounterApp: App {
    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) { Counter() }
    }
}
```

Every app declares exactly one explicit primary scene. Auxiliary windows and
typed payload-addressed groups can appear in any declaration order; TUI, WASM,
Embed, Android, MLIR, and custom Apple hosts render only the primary scene.
See [`docs/SceneMigration.md`](docs/SceneMigration.md) for the intentional
pre-release migration from `App.content` and typed `WindowGroup` examples.

## Products

| Product | Responsibility |
| --- | --- |
| `Gama` | Compatibility umbrella (`@_exported import GamaCore`) |
| `GamaCore` | Scenes, views, identity, state, layout, events, and `FrameHost` |
| `GamaPlugin` | Stdlib-only Tier-1 static plugin and capability model |
| `GamaPlatformServices` | Foundation-backed `HostServices` implementations; applications, demos, examples, and tests only |
| `GamaMacros` | Optional `@Component`, `@Reactive`, and `#rgb` sugar |
| `GamaDraw` | Cell buffer, painter, draw list, and versioned binary codec |
| `GamaTUI` | POSIX and Windows terminal backend |
| `GamaAppleUI` | `@MainActor` AppKit/UIKit host view |
| `GamaAppleShell` | macOS AppKit application and multi-window ownership |
| `GamaWASM` | Browser reactor using `gama_web_v1_*` exports |
| `GamaEmbed` | Context-owned `gama_embed_v1_*` C ABI |
| `GamaMLIR` | Deterministic generic-form `gama` dialect emitter |
| `GamaEmbedABI` | The C header (`GamaEmbed.h`): opaque context type, status codes, `gama_embed_v1_abi_version` |
| `GamaAndroidDemo` | Sample dynamic library bootstrapping an app for the JNI example |
| `gama-demo` | Interactive TUI and `--emit-mlir` showcase |
| `gama-web-demo` | Browser reactor demo served from `WebHost/` |
| `gama-apple-demo` | macOS scene/window lifecycle showcase |
| `gama-windows-console-smoke` | Windows console acceptance binary |
| `gama-leak-check` | Harness-free lifecycle probe so Linux LeakSanitizer observes Gama without the XCTest harness |
| `gama-bench` | Deterministic frame-path measurement harness; reports numbers, asserts no threshold, and is not a gate |

## Architecture

```text
App → @SceneBuilder → explicit primary/auxiliary surfaces
App state → @ViewBuilder / macros → RenderNode
          → LayoutEngine → LaidOutNode
          → CellPainter → CellBuffer → DrawList
          → TUI | Apple | WASM | C/Android | MLIR

platform event → InputEvent → FrameHost → host-owned action → rebuild
```

`GamaCore` imports no Foundation, platform UI, POSIX, WinSDK, or
Synchronization module. Each `FrameHost` owns actions, focus, dirty state, and explicit subscriptions;
there is no process-global action or invalidation registry. Changes made
outside a Gama input event connect through the host's `SubscriptionContext` or
are scheduled explicitly with the host/backend's `invalidate()` API.

## Build and verify

Apple development uses the pinned Swift 6.5-dev main snapshot
(`.swift-version`: `main-snapshot-2026-08-21`). Everyday invocation is
`swiftly run` (it reads `.swift-version`). Check scripts additionally pin
`xcrun --toolchain org.swift.65202608211a`. Only the xcodebuild
iOS/tvOS/visionOS gates use Xcode's default 6.4 toolchain. Tests are Swift
Testing only.

```bash
unset TOOLCHAINS
swiftly run swift --version
./scripts/check-apple.sh
./scripts/check-boundaries.sh
```

`./scripts/check.sh` is the complete acceptance matrix. It intentionally fails
when an exact pinned prerequisite or required runtime proof is unavailable.
See [`docs/README.md`](docs/README.md) for the full documentation index —
per-backend guides under `docs/backends/`, the `gama` dialect reference,
decision records under `docs/adr/`, and
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the gate reference. Key entries:
[`docs/Toolchain.md`](docs/Toolchain.md), [`docs/Testing.md`](docs/Testing.md),
`Toolchains.toml`, and [`docs/Capabilities.md`](docs/Capabilities.md).
Runnable samples live in `Examples/` (C, Android/JNI, AppleHost, Embedded)
and `WebHost/` (browser).

For a guided first build and application, start with
[`docs/GettingStarted.md`](docs/GettingStarted.md). The broader reader paths
are indexed in [`docs/README.md`](docs/README.md): architecture, state and
identity, runnable examples, Apple integration, verification boundaries, and
troubleshooting.

Run the terminal demo with:

```bash
unset TOOLCHAINS
swiftly run swift run gama-demo
```

For an automated real-TTY focus-and-activation smoke with external scratch
paths:

```bash
.agents/skills/run-gama/driver.sh smoke
```

Run the macOS multi-window demo with:

```bash
unset TOOLCHAINS
swiftly run swift run gama-apple-demo
```

The primary typed group opens at launch. Its controls reopen the same payload
(focusing the existing window), open a distinct payload with its own host, and
open the auxiliary singleton. See
[`docs/backends/AppleShell.md`](docs/backends/AppleShell.md) for lifecycle and
manual-smoke details.

## Compatibility

Supported Apple deployment floors are macOS 14, iOS 17, tvOS 17, and visionOS
1. Import `Gama` or `GamaCore` and build an `App` with an explicit renderer.

The DrawList ABI is little-endian, starts with `GAMA`, and is versioned as `1`.
The C declarations and ownership rules live in
`Sources/GamaEmbedABI/include/GamaEmbed.h`.

## Evidence policy

Implementation presence is not platform proof. A backend is Current only when
its declared compile/runtime gate passes. Embedded Swift is experimental, and
`GamaMLIR` emits a textual custom dialect; it is not a Swift MLIR frontend.
Local, hosted, artifact, deployment, and manual proof are separate layers;
[`docs/Verification.md`](docs/Verification.md) defines the exact boundary.
