# Gama

A modular **GPU graphics API** for Swift 6+, inspired by WebGPU. Provides a protocol-based abstraction layer with pluggable backends for cross-platform GPU rendering.

## Architecture

```
GamaCore          Protocol layer (GPUDevice, GPUBuffer, GPUTexture, GPURenderPipeline, ...)
  |
  +-- GamaMetal   Metal backend (macOS/iOS) — fully implemented
  +-- GamaVulkan  Vulkan backend — stubs for future implementation
  +-- GamaDX12    DirectX 12 backend — stubs for future implementation
  |
GamaMath          simd-based 3D math (Vec2/3/4, Mat4, Quaternion, Transform, Camera, Ray, AABB)
GamaScene         Scene graph (Node, Mesh, Material, SceneCamera, Primitives)
GamaUI            SwiftUI-inspired declarative UI (View, VStack/HStack/ZStack, layout engine)
GamaMacros        Swift macros (@GPUBufferLayout, @ShaderBinding, @RenderPass)
GamaDemo          CLI demo with GPU info, triangle, headless render, and interactive window
```

## Requirements

- Swift 6.2+ (swift-tools-version: 6.2)
- macOS 15+ or iOS 18+ (for Metal backend)
- Xcode 16+

## Build & Test

```bash
swift build                          # Debug build
swift build -c release               # Release build
swift test                           # Run all tests
swift test --filter GamaCoreTests    # Run a specific test target
```

## Demo Commands

```bash
swift run GamaDemo info              # Print GPU adapter info
swift run GamaDemo triangle          # Create triangle vertex buffer
swift run GamaDemo render            # Headless render-to-texture
swift run GamaDemo ui                # Interactive window with animated triangle
```

The `ui` command opens a Metal-backed window with an animated rotating triangle. Controls: arrow keys to rotate, mouse drag to orbit, ESC to quit.

## Modules

| Module | Description | Dependencies |
|--------|-------------|--------------|
| **GamaCore** | GPU abstraction protocols and descriptor types | None |
| **GamaMetal** | Metal backend implementing all GamaCore protocols | GamaCore |
| **GamaVulkan** | Vulkan backend (stub) | GamaCore |
| **GamaDX12** | DirectX 12 backend (stub) | GamaCore |
| **GamaMath** | simd-based 3D math types | None |
| **GamaScene** | Scene graph with mesh/material/camera | GamaCore |
| **GamaUI** | Declarative UI framework with layout engine | None |
| **GamaMacros** | Swift compiler macros for GPU resources | swift-syntax |

## GPU Pipeline Example

```swift
import GamaCore
import GamaMetal

let adapter = try MetalBackend.shared.requestDefaultAdapter()
let device = try adapter.requestDevice()
let queue = try device.createQueue()

let shader = try device.createShaderModule(source: mslSource)
let pipeline = try device.createRenderPipeline(descriptor: pipelineDesc)

let cmdBuffer = try queue.createCommandBuffer()
let encoder = try cmdBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)
encoder.setRenderPipeline(pipeline)
encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
encoder.draw(vertexCount: 3)
encoder.endEncoding()
cmdBuffer.commit()
```

## Adding a Backend

1. Create a new module (e.g., `Sources/GamaVulkan/`)
2. Implement all `GamaCore` protocols (`GPUDevice`, `GPUBuffer`, `GPUTexture`, etc.)
3. Add a backend factory (like `MetalBackend.shared`)
4. Add enum conversions (like `MetalConversions.swift`)
5. Gate files with `#if canImport(...)` guards

## License

See [LICENSE.md](LICENSE.md) for details.
