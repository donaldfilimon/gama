# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gama is a cross-platform GPU graphics API written in Swift 6+, inspired by WebGPU. It provides a protocol-based GPU abstraction layer with pluggable backends:
- **Metal** on Apple platforms (macOS, iOS) — fully implemented
- **Vulkan** on Linux, Android, Windows (fallback) — stubs only
- **DirectX 12** on Windows (primary) — stubs only

Additionally includes a 3D math library (GamaMath), scene graph (GamaScene), and declarative UI framework (GamaUI).

swift-tools-version 6.2. Minimum platforms: macOS 15, iOS 18.

## Build Commands

```bash
swift build                          # Debug build
swift build -c release               # Release build
swift test                           # Run all tests (167 tests)
swift test --filter GamaCoreTests    # Run core tests only
swift test --filter GamaMetalTests   # Run Metal backend tests only
swift test --filter GamaMathTests    # Run math tests only
swift test --filter GamaSceneTests   # Run scene tests only
swift test --filter GamaUITests      # Run UI tests only
swift test --filter TypesTests       # Run a single test suite by name
swift run GamaDemo info              # Print GPU device info
swift run GamaDemo triangle          # Test triangle vertex buffer creation
swift run GamaDemo render            # Headless render-to-texture demo
swift run GamaDemo ui                # Interactive window with animated triangle
```

## Architecture

### GPU Abstraction (GamaCore + Backends)

**Protocol-based abstraction**: `GamaCore` defines protocols (`GPUDevice`, `GPUBuffer`, `GPUTexture`, `GPUQueue`, `GPURenderPipeline`, `GPUComputePipeline`, `GPUCommandBuffer`, `GPURenderCommandEncoder`, `GPUComputeCommandEncoder`, `GPUBindGroup`, `GPUSampler`, `GPUShaderModule`, `GPUSurface`, `GPUDepthStencilStateObject`) that each backend implements. All protocols inherit `AnyObject & Sendable`.

**Backend factory chain**: `MetalBackend.shared.requestDefaultAdapter()` -> `MetalAdapter` -> `adapter.requestDevice()` -> `MetalDevice` -> create resources via device methods.

**Metal backend pattern**: Each Metal type is a `final class` wrapping the corresponding `MTL*` object, marked `@unchecked Sendable`. All enum conversions between GamaCore types and Metal types are centralized in `MetalConversions.swift`.

### Module Structure

- **GamaCore** — GPU abstraction protocols and descriptor types (no platform dependencies)
- **GamaMetal** — Metal backend implementing all GamaCore protocols (Apple-only)
- **GamaVulkan** / **GamaDX12** — Stub backends (fatalError / throw)
- **GamaMath** — simd-based 3D math: Vec2/3/4, Mat4, Quaternion, Transform, Camera, Ray, AABB
- **GamaScene** — Scene graph: Node hierarchy, Mesh, Material, SceneCamera, Primitives (cube/sphere/plane/cylinder)
- **GamaUI** — SwiftUI-inspired declarative UI: View protocol, ViewBuilder, VStack/HStack/ZStack, Text/Button/Rectangle/Circle, layout engine
- **GamaMacros** — Compiler plugin for `@GPUBufferLayout`, `@ShaderBinding`, `@RenderPass`
- **GamaMacroDeclarations** — Public macro declarations (separate from plugin per Swift macro rules)
- **GamaDemo** — CLI with subcommands: info, triangle, render, ui

### Adding a New Backend

1. Replace stubs in `Sources/GamaVulkan/` or `Sources/GamaDX12/` — each file mirrors a GamaCore protocol
2. Every GamaCore protocol must have a conforming type
3. Add a backend factory (like `MetalBackend.shared`) that returns an adapter
4. Add an enum conversion file (like `MetalConversions.swift`) for GamaCore <-> native type mapping
5. Gate all files with appropriate `#if` guards

## Key Conventions

- Swift 6 language mode with `ApproachableConcurrency` — all public types must be `Sendable`-correct
- Metal files always wrapped in `#if canImport(Metal) ... #endif`
- GPU resource protocols require `AnyObject` (reference semantics); descriptors are value-type structs
- Backend stubs: factory methods throw `GPUError.backendNotAvailable`, everything else `fatalError`
- Tests use **Swift Testing** framework (`@Suite`, `@Test`, `#expect`), not XCTest
- Metal tests gated with `#if canImport(Metal)` — they only run on Apple platforms
- File headers: `// FileName.swift — Description` + `// Part of TargetName`
- Conventional commits (feat/fix/test/chore/docs)

## Dependencies

- `swift-argument-parser` (1.2.0+) — CLI interface for GamaDemo
- `swift-syntax` (600.0.1+) — Swift macro compiler plugin support

## Known Workarounds

- `MTLRenderPipelineDescriptor.label` must not be nil — defaults to `"GamaPipeline"` when not set
- Swift 6.4 region-based isolation checker bug with `MTLCommandBuffer.present(drawable:)` — use a free function wrapper to avoid the error
- `@preconcurrency ParsableCommand` needed for `@MainActor` isolated `run()` methods in ArgumentParser commands
