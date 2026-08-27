# Gama Framework

Gama is a modular declarative UI framework written in Swift 6.4. A single
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
    var content: some View { Counter() }
}
```

## Products

| Product | Responsibility |
| --- | --- |
| `Gama` | Compatibility umbrella; deprecated `hello()` |
| `GamaCore` | Views, identity, state, layout, events, and `FrameHost` |
| `GamaMacros` | Optional `@Component`, `@Reactive`, and `#rgb` sugar |
| `GamaDraw` | Cell buffer, painter, draw list, and versioned binary codec |
| `GamaTUI` | POSIX and Windows terminal backend |
| `GamaAppleUI` | `@MainActor` AppKit/UIKit host view |
| `GamaWASM` | Browser reactor using `gama_web_v1_*` exports |
| `GamaEmbed` | Context-owned `gama_embed_v1_*` C ABI |
| `GamaMLIR` | Deterministic generic-form `gama` dialect emitter |
| `gama-demo` | Interactive TUI and `--emit-mlir` showcase |

## Architecture

```text
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

Apple development uses Xcode's Swift 6.4 toolchain, never the PATH-selected
Swiftly snapshot:

```bash
unset TOOLCHAINS
./scripts/check-apple.sh
./scripts/check-boundaries.sh
```

`./scripts/check.sh` is the complete acceptance matrix. It intentionally fails
when an exact pinned prerequisite or required runtime proof is unavailable.
See `Toolchains.toml` and
[`docs/Capabilities.md`](docs/Capabilities.md) for the evidence boundary.

Run the terminal demo with:

```bash
unset TOOLCHAINS
/usr/bin/xcrun --toolchain default swift run gama-demo
```

## Compatibility

Supported Apple deployment floors are macOS 14, iOS 17, tvOS 17, and visionOS
1. `Gama.hello()` preserves the initial scaffold's exact print-and-return
behavior for one compatibility cycle but is deprecated in favor of an `App`
and explicit renderer.

The DrawList ABI is little-endian, starts with `GAMA`, and is versioned as `1`.
The C declarations and ownership rules live in
`Sources/GamaEmbedABI/include/GamaEmbed.h`.

## Evidence policy

Implementation presence is not platform proof. A backend is Current only when
its declared compile/runtime gate passes. Embedded Swift is experimental, and
`GamaMLIR` emits a textual custom dialect; it is not a Swift MLIR frontend.
