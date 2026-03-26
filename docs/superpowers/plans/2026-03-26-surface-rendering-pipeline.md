# Surface, Rendering Pipeline & Depth/Stencil Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add window surface support, depth/stencil state, and a working render-to-texture demo that proves the full pipeline end-to-end — from shader compilation through draw calls to reading back pixel data.

**Architecture:** Add `GPUSurface` protocol to GamaCore for presentable surfaces, `GPUDepthStencilState` for depth testing, and `MetalSurface` wrapping `CAMetalLayer`. Build a headless render-to-texture demo that compiles a shader, creates a pipeline, renders a triangle to an offscreen texture, reads back pixels, and verifies the output — all without requiring a window.

**Tech Stack:** Swift 6.0, Metal (MTLTexture, MTLLibrary, MTLRenderPipelineState), Swift Testing framework

---

## File Structure

### New files to create:
| File | Responsibility |
|------|---------------|
| `Sources/GamaCore/Surface.swift` | `GPUSurface` protocol, `GPUSurfaceDescriptor`, `PresentMode` enum |
| `Sources/GamaCore/DepthStencilState.swift` | `GPUDepthStencilState` protocol + descriptor |
| `Sources/GamaMetal/MetalSurface.swift` | `MetalSurface` wrapping `CAMetalLayer` |
| `Sources/GamaMetal/MetalDepthStencilState.swift` | `MetalDepthStencilState` wrapping `MTLDepthStencilState` |
| `Sources/GamaDemo/RenderCommand.swift` | Headless render-to-texture triangle demo |
| `Tests/GamaMetalTests/MetalRenderPipelineTests.swift` | End-to-end render pipeline tests |
| `Tests/GamaMetalTests/MetalDepthStencilTests.swift` | Depth/stencil state tests |

### Files to modify:
| File | Change |
|------|--------|
| `Sources/GamaCore/Device.swift` | Add `createDepthStencilState(descriptor:)` to `GPUDevice` |
| `Sources/GamaCore/CommandEncoder.swift` | Add `setDepthStencilState(_:)` to `GPURenderCommandEncoder` |
| `Sources/GamaMetal/MetalDevice.swift` | Implement `createDepthStencilState` |
| `Sources/GamaMetal/MetalCommandEncoder.swift` | Implement `setDepthStencilState` |
| `Sources/GamaMetal/MetalConversions.swift` | Add `CompareFunction` → `MTLCompareFunction` for depth stencil descriptor (already exists, just verify) |
| `Sources/GamaVulkan/VulkanDevice.swift` | Add `createDepthStencilState` stub |
| `Sources/GamaVulkan/VulkanCommandEncoder.swift` | Add `setDepthStencilState` stub + `VulkanDepthStencilState` stub |
| `Sources/GamaDX12/DX12Device.swift` | Add `createDepthStencilState` stub |
| `Sources/GamaDX12/DX12CommandEncoder.swift` | Add `setDepthStencilState` stub + `DX12DepthStencilState` stub |
| `Sources/GamaDemo/GamaDemo.swift` | Register new `Render` subcommand |
| `Package.swift` | Add `QuartzCore` framework link to GamaMetal |

---

## Task 1: Add GPUDepthStencilState protocol to GamaCore

**Files:**
- Create: `Sources/GamaCore/DepthStencilState.swift`
- Modify: `Sources/GamaCore/Device.swift`
- Modify: `Sources/GamaCore/CommandEncoder.swift`

- [ ] **Step 1: Create the depth/stencil state protocol and descriptor**

```swift
// Sources/GamaCore/DepthStencilState.swift

/// Describes how depth and stencil tests are performed.
public struct GPUDepthStencilDescriptor: Sendable {
    /// Whether depth testing is enabled.
    public var isDepthTestEnabled: Bool

    /// Whether depth writes are enabled.
    public var isDepthWriteEnabled: Bool

    /// The comparison function for depth testing.
    public var depthCompareFunction: CompareFunction

    /// An optional debug label.
    public var label: String?

    /// Creates a depth/stencil descriptor.
    public init(
        isDepthTestEnabled: Bool = true,
        isDepthWriteEnabled: Bool = true,
        depthCompareFunction: CompareFunction = .less,
        label: String? = nil
    ) {
        self.isDepthTestEnabled = isDepthTestEnabled
        self.isDepthWriteEnabled = isDepthWriteEnabled
        self.depthCompareFunction = depthCompareFunction
        self.label = label
    }
}

/// A compiled depth/stencil state object.
public protocol GPUDepthStencilState: AnyObject, Sendable {
    /// An optional debug label.
    var label: String? { get }
}
```

- [ ] **Step 2: Add `createDepthStencilState` to GPUDevice**

Add this method to the `GPUDevice` protocol in `Sources/GamaCore/Device.swift`, after the `createComputePipeline` method:

```swift
    /// Create a depth/stencil state from a descriptor.
    func createDepthStencilState(descriptor: GPUDepthStencilDescriptor) throws -> any GPUDepthStencilState
```

- [ ] **Step 3: Add `setDepthStencilState` to GPURenderCommandEncoder**

Add this method to the `GPURenderCommandEncoder` protocol in `Sources/GamaCore/CommandEncoder.swift`, after `setBindGroup`:

```swift
    /// Sets the depth/stencil state for subsequent draw calls.
    ///
    /// - Parameter state: The depth/stencil state to bind.
    func setDepthStencilState(_ state: any GPUDepthStencilState)
```

- [ ] **Step 4: Verify GamaCore compiles (expect errors in backends)**

Run: `swift build --target GamaCore 2>&1 | tail -5`
Expected: Build succeeded (GamaCore has no concrete types to break)

- [ ] **Step 5: Commit**

```bash
git add Sources/GamaCore/DepthStencilState.swift Sources/GamaCore/Device.swift Sources/GamaCore/CommandEncoder.swift
git commit -m "feat(core): add GPUDepthStencilState protocol and descriptor"
```

---

## Task 2: Implement MetalDepthStencilState

**Files:**
- Create: `Sources/GamaMetal/MetalDepthStencilState.swift`
- Modify: `Sources/GamaMetal/MetalDevice.swift`
- Modify: `Sources/GamaMetal/MetalCommandEncoder.swift`

- [ ] **Step 1: Create MetalDepthStencilState**

```swift
// Sources/GamaMetal/MetalDepthStencilState.swift

#if canImport(Metal)
import Metal
import GamaCore

/// A Metal depth/stencil state conforming to ``GPUDepthStencilState``.
///
/// Wraps an `MTLDepthStencilState` created from a ``GPUDepthStencilDescriptor``.
public final class MetalDepthStencilState: GPUDepthStencilState, @unchecked Sendable {
    /// The underlying Metal depth/stencil state.
    public let mtlDepthStencilState: MTLDepthStencilState

    /// An optional debug label.
    public let label: String?

    /// Creates a Metal depth/stencil state.
    /// - Parameters:
    ///   - state: The `MTLDepthStencilState` to wrap.
    ///   - label: An optional debug label.
    public init(state: MTLDepthStencilState, label: String?) {
        self.mtlDepthStencilState = state
        self.label = label
    }

    /// Creates a Metal depth/stencil state from a descriptor and device.
    /// - Parameters:
    ///   - descriptor: The cross-platform depth/stencil descriptor.
    ///   - device: The Metal device to create the state on.
    /// - Throws: ``GPUError/pipelineCreationFailed(_:)`` if creation fails.
    public static func make(
        descriptor: GPUDepthStencilDescriptor,
        device: MTLDevice
    ) throws -> MetalDepthStencilState {
        let mtlDesc = MTLDepthStencilDescriptor()
        mtlDesc.isDepthWriteEnabled = descriptor.isDepthWriteEnabled

        if descriptor.isDepthTestEnabled {
            mtlDesc.depthCompareFunction = descriptor.depthCompareFunction.mtlCompareFunction
        } else {
            mtlDesc.depthCompareFunction = .always
        }

        mtlDesc.label = descriptor.label

        guard let state = device.makeDepthStencilState(descriptor: mtlDesc) else {
            throw GPUError.pipelineCreationFailed("Failed to create depth/stencil state")
        }
        return MetalDepthStencilState(state: state, label: descriptor.label)
    }
}

#endif
```

- [ ] **Step 2: Add `createDepthStencilState` to MetalDevice**

In `Sources/GamaMetal/MetalDevice.swift`, add this method after `createComputePipeline`:

```swift
    // MARK: - Depth/Stencil State

    /// Create a Metal depth/stencil state from a descriptor.
    public func createDepthStencilState(descriptor: GPUDepthStencilDescriptor) throws -> any GPUDepthStencilState {
        return try MetalDepthStencilState.make(descriptor: descriptor, device: mtlDevice)
    }
```

- [ ] **Step 3: Add `setDepthStencilState` to MetalRenderCommandEncoder**

In `Sources/GamaMetal/MetalCommandEncoder.swift`, add this method to `MetalRenderCommandEncoder` after `setBindGroup`:

```swift
    // MARK: Depth/Stencil State

    /// Sets the depth/stencil state for subsequent draw calls.
    public func setDepthStencilState(_ state: any GPUDepthStencilState) {
        guard let metalState = state as? MetalDepthStencilState else { return }
        mtlEncoder.setDepthStencilState(metalState.mtlDepthStencilState)
    }
```

- [ ] **Step 4: Verify GamaMetal compiles**

Run: `swift build --target GamaMetal 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 5: Commit**

```bash
git add Sources/GamaMetal/MetalDepthStencilState.swift Sources/GamaMetal/MetalDevice.swift Sources/GamaMetal/MetalCommandEncoder.swift
git commit -m "feat(metal): implement MetalDepthStencilState"
```

---

## Task 3: Update Vulkan and DX12 stubs for new protocol methods

**Files:**
- Modify: `Sources/GamaVulkan/VulkanDevice.swift`
- Modify: `Sources/GamaVulkan/VulkanCommandEncoder.swift`
- Modify: `Sources/GamaDX12/DX12Device.swift`
- Modify: `Sources/GamaDX12/DX12CommandEncoder.swift`

- [ ] **Step 1: Add VulkanDepthStencilState stub and update VulkanDevice**

In `Sources/GamaVulkan/VulkanCommandEncoder.swift`, add before the closing of the file:

```swift
/// Stub Vulkan depth/stencil state.
public final class VulkanDepthStencilState: GPUDepthStencilState, @unchecked Sendable {
    public var label: String? { fatalError("Vulkan backend not yet implemented") }
}
```

In `Sources/GamaVulkan/VulkanDevice.swift`, add to `VulkanDevice`:

```swift
    public func createDepthStencilState(descriptor: GPUDepthStencilDescriptor) throws -> any GPUDepthStencilState {
        fatalError("Vulkan backend not yet implemented")
    }
```

In `Sources/GamaVulkan/VulkanCommandEncoder.swift`, add to `VulkanRenderCommandEncoder`:

```swift
    public func setDepthStencilState(_ state: any GPUDepthStencilState) {
        fatalError("Vulkan backend not yet implemented")
    }
```

- [ ] **Step 2: Add DX12DepthStencilState stub and update DX12Device**

Same pattern in the DX12 files — `DX12DepthStencilState` class, `createDepthStencilState` on `DX12Device`, `setDepthStencilState` on `DX12RenderCommandEncoder`.

- [ ] **Step 3: Verify full build**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete!

- [ ] **Step 4: Commit**

```bash
git add Sources/GamaVulkan/ Sources/GamaDX12/
git commit -m "chore(stubs): add depth/stencil state stubs to Vulkan and DX12 backends"
```

---

## Task 4: Write depth/stencil state tests

**Files:**
- Create: `Tests/GamaMetalTests/MetalDepthStencilTests.swift`

- [ ] **Step 1: Write the test file**

```swift
// Tests/GamaMetalTests/MetalDepthStencilTests.swift

#if canImport(Metal)
import Testing
import GamaCore
import GamaMetal

@Suite("MetalDepthStencilState Tests")
struct MetalDepthStencilTests {
    let device: any GPUDevice

    init() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        self.device = try adapter.requestDevice()
    }

    @Test("Create depth/stencil state with defaults")
    func createDefault() throws {
        let descriptor = GPUDepthStencilDescriptor()
        let state = try device.createDepthStencilState(descriptor: descriptor)
        #expect(state != nil)
    }

    @Test("Create depth/stencil state with depth test disabled")
    func createDisabled() throws {
        let descriptor = GPUDepthStencilDescriptor(
            isDepthTestEnabled: false,
            isDepthWriteEnabled: false
        )
        let state = try device.createDepthStencilState(descriptor: descriptor)
        #expect(state != nil)
    }

    @Test("Create depth/stencil state with custom compare function")
    func createCustomCompare() throws {
        let descriptor = GPUDepthStencilDescriptor(
            depthCompareFunction: .lessEqual,
            label: "custom-depth"
        )
        let state = try device.createDepthStencilState(descriptor: descriptor)
        #expect(state.label == "custom-depth")
    }
}
#endif
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter MetalDepthStencilTests 2>&1 | tail -10`
Expected: All 3 tests pass

- [ ] **Step 3: Commit**

```bash
git add Tests/GamaMetalTests/MetalDepthStencilTests.swift
git commit -m "test(metal): add depth/stencil state tests"
```

---



## Task 5: Add GPUSurface protocol to GamaCore

**Files:**
- Create: `Sources/GamaCore/Surface.swift`

- [ ] **Step 1: Create the surface protocol**

```swift
// Sources/GamaCore/Surface.swift

/// Presentation mode for a surface.
public enum PresentMode: Sendable {
    /// Vertical sync — wait for display refresh.
    case vsync
    /// Immediate — present as soon as possible, may tear.
    case immediate
    /// Mailbox — like vsync but drops old frames.
    case mailbox
}

/// Describes a surface's configuration.
public struct GPUSurfaceConfiguration: Sendable {
    /// The pixel format for the surface.
    public var format: PixelFormat
    /// The width of the surface in pixels.
    public var width: UInt32
    /// The height of the surface in pixels.
    public var height: UInt32
    /// The presentation mode.
    public var presentMode: PresentMode
    /// The texture usage for surface textures.
    public var usage: TextureUsage

    /// Creates a surface configuration.
    public init(
        format: PixelFormat = .bgra8Unorm,
        width: UInt32,
        height: UInt32,
        presentMode: PresentMode = .vsync,
        usage: TextureUsage = .renderTarget
    ) {
        self.format = format
        self.width = width
        self.height = height
        self.presentMode = presentMode
        self.usage = usage
    }
}

/// A presentable surface that provides drawable textures for rendering.
///
/// Surfaces represent the connection between the GPU and a display target
/// (e.g., a window, layer, or view). Each frame, call ``nextTexture()`` to
/// get the current drawable texture, render into it, then call ``present()``
/// to display it.
public protocol GPUSurface: AnyObject, Sendable {
    /// Configure the surface for rendering.
    func configure(device: any GPUDevice, configuration: GPUSurfaceConfiguration) throws

    /// Get the next drawable texture for rendering.
    ///
    /// This blocks until a drawable is available.
    /// - Returns: A texture to render into for the current frame.
    func nextTexture() throws -> any GPUTexture

    /// Present the current drawable to the display.
    func present() throws

    /// Resize the surface.
    func resize(width: UInt32, height: UInt32)
}
```

- [ ] **Step 2: Verify GamaCore compiles**

Run: `swift build --target GamaCore 2>&1 | tail -5`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/GamaCore/Surface.swift
git commit -m "feat(core): add GPUSurface protocol for presentable surfaces"
```

---

## Task 6: Implement MetalSurface

**Files:**
- Create: `Sources/GamaMetal/MetalSurface.swift`
- Modify: `Package.swift` (add QuartzCore framework)

- [ ] **Step 1: Add QuartzCore framework to GamaMetal linker settings**

In `Package.swift`, modify the GamaMetal target's `linkerSettings` to add QuartzCore:

```swift
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("MetalKit", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.macOS, .iOS])),
            ]
```

- [ ] **Step 2: Create MetalSurface**

```swift
// Sources/GamaMetal/MetalSurface.swift

#if canImport(Metal)
import Metal
import QuartzCore
import GamaCore

/// A Metal surface conforming to ``GPUSurface``.
///
/// Wraps a `CAMetalLayer` to provide drawable textures for rendering to screen.
/// Create a `CAMetalLayer`, pass it to ``init(layer:)``, then configure and
/// render each frame.
public final class MetalSurface: GPUSurface, @unchecked Sendable {
    /// The underlying Core Animation Metal layer.
    public let metalLayer: CAMetalLayer

    /// The current drawable, valid between ``nextTexture()`` and ``present()`` calls.
    private var currentDrawable: CAMetalDrawable?

    /// Creates a Metal surface wrapping the given layer.
    /// - Parameter layer: The `CAMetalLayer` to wrap.
    public init(layer: CAMetalLayer) {
        self.metalLayer = layer
    }

    /// Configure the surface for rendering.
    public func configure(device: any GPUDevice, configuration: GPUSurfaceConfiguration) throws {
        guard let metalDevice = device as? MetalDevice else {
            throw GPUError.unsupportedOperation("MetalSurface requires a MetalDevice")
        }
        metalLayer.device = metalDevice.mtlDevice
        metalLayer.pixelFormat = configuration.format.mtlPixelFormat
        metalLayer.drawableSize = CGSize(
            width: CGFloat(configuration.width),
            height: CGFloat(configuration.height)
        )
        metalLayer.displaySyncEnabled = configuration.presentMode == .vsync
    }

    /// Get the next drawable texture for this frame.
    public func nextTexture() throws -> any GPUTexture {
        guard let drawable = metalLayer.nextDrawable() else {
            throw GPUError.textureCreationFailed
        }
        currentDrawable = drawable

        let desc = GPUTextureDescriptor(
            width: UInt32(drawable.texture.width),
            height: UInt32(drawable.texture.height),
            format: .bgra8Unorm,
            usage: .renderTarget
        )
        return MetalDrawableTexture(texture: drawable.texture, descriptor: desc)
    }

    /// Present the current drawable to the display.
    public func present() throws {
        guard let drawable = currentDrawable else {
            throw GPUError.unsupportedOperation("No drawable to present — call nextTexture() first")
        }
        drawable.present()
        currentDrawable = nil
    }

    /// Resize the surface.
    public func resize(width: UInt32, height: UInt32) {
        metalLayer.drawableSize = CGSize(
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

/// A thin wrapper around a drawable's `MTLTexture` that conforms to ``GPUTexture``.
///
/// Unlike ``MetalTexture``, this does not own the texture — the drawable does.
/// The texture is only valid for the current frame.
final class MetalDrawableTexture: GPUTexture, @unchecked Sendable {
    let mtlTexture: MTLTexture
    public let descriptor: GPUTextureDescriptor

    public var width: UInt32 { UInt32(mtlTexture.width) }
    public var height: UInt32 { UInt32(mtlTexture.height) }
    public var format: PixelFormat { descriptor.format }

    init(texture: MTLTexture, descriptor: GPUTextureDescriptor) {
        self.mtlTexture = texture
        self.descriptor = descriptor
    }

    public func replaceRegion(
        origin: Origin3D, size: Extent3D, mipLevel: UInt32,
        data: UnsafeRawPointer, bytesPerRow: Int
    ) {
        let region = MTLRegion(
            origin: MTLOrigin(x: Int(origin.x), y: Int(origin.y), z: Int(origin.z)),
            size: MTLSize(width: Int(size.width), height: Int(size.height), depth: Int(size.depth))
        )
        mtlTexture.replace(
            region: region,
            mipmapLevel: Int(mipLevel),
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
    }
}

#endif
```

- [ ] **Step 3: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete!

- [ ] **Step 4: Commit**

```bash
git add Sources/GamaMetal/MetalSurface.swift Package.swift
git commit -m "feat(metal): implement MetalSurface wrapping CAMetalLayer"
```

---

## Task 7: End-to-end render-to-texture test

**Files:**
- Create: `Tests/GamaMetalTests/MetalRenderPipelineTests.swift`

This is the critical test — it proves the entire rendering pipeline works: shader compile → pipeline create → command buffer → render encoder → draw → read back pixels.

- [ ] **Step 1: Write the render-to-texture test**

```swift
// Tests/GamaMetalTests/MetalRenderPipelineTests.swift

#if canImport(Metal)
import Testing
import GamaCore
import GamaMetal

@Suite("Metal Render Pipeline End-to-End Tests")
struct MetalRenderPipelineTests {
    let device: any GPUDevice
    let queue: any GPUQueue

    init() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        self.device = try adapter.requestDevice()
        self.queue = try device.createQueue()
    }

    @Test("Compile MSL shader module")
    func compileShader() throws {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VertexOut vertex_main(
            uint vid [[vertex_id]]
        ) {
            float2 positions[3] = {
                float2( 0.0,  0.5),
                float2(-0.5, -0.5),
                float2( 0.5, -0.5)
            };
            VertexOut out;
            out.position = float4(positions[vid], 0.0, 1.0);
            out.color = float4(1.0, 0.0, 0.0, 1.0);
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """
        let shaderModule = try device.createShaderModule(source: source)
        #expect(shaderModule != nil)
    }

    @Test("Render red triangle to offscreen texture and verify pixels")
    func renderTriangle() throws {
        // 1. Compile shader
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut {
            float4 position [[position]];
        };
        vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
            float2 positions[3] = {
                float2( 0.0,  1.0),
                float2(-1.0, -1.0),
                float2( 1.0, -1.0)
            };
            VertexOut out;
            out.position = float4(positions[vid], 0.0, 1.0);
            return out;
        }
        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return float4(1.0, 0.0, 0.0, 1.0);
        }
        """
        let shaderModule = try device.createShaderModule(source: source)

        // 2. Create offscreen render target (64x64)
        let texDesc = GPUTextureDescriptor(
            width: 64, height: 64,
            format: .rgba8Unorm,
            usage: [.renderTarget, .shaderRead]
        )
        let renderTarget = try device.createTexture(descriptor: texDesc)

        // 3. Create render pipeline
        let vertexFunction = GPUShaderFunction(
            module: shaderModule, entryPoint: "vertex_main", stage: .vertex
        )
        let fragmentFunction = GPUShaderFunction(
            module: shaderModule, entryPoint: "fragment_main", stage: .fragment
        )
        let colorTarget = GPUColorTargetState(format: .rgba8Unorm)
        let pipelineDesc = GPURenderPipelineDescriptor(
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            vertexBufferLayouts: [],
            colorTargets: [colorTarget]
        )
        let pipeline = try device.createRenderPipeline(descriptor: pipelineDesc)

        // 4. Encode and submit render commands
        let cmdBuffer = try queue.createCommandBuffer()
        let rpDesc = GPURenderPassDescriptor(
            colorAttachments: [
                GPUColorAttachment(
                    texture: renderTarget,
                    loadAction: .clear,
                    storeAction: .store,
                    clearColor: ClearColor(r: 0, g: 0, b: 0, a: 1)
                )
            ]
        )
        let encoder = try cmdBuffer.makeRenderCommandEncoder(descriptor: rpDesc)
        encoder.setRenderPipeline(pipeline)
        encoder.setViewport(x: 0, y: 0, width: 64, height: 64, minDepth: 0, maxDepth: 1)
        encoder.draw(vertexCount: 3)
        encoder.endEncoding()
        cmdBuffer.commit()

        try await cmdBuffer.waitUntilCompleted()

        // 5. Read back center pixel — should be red (the triangle covers the center)
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBytes { ptr in
            renderTarget.replaceRegion(
                origin: Origin3D(),
                size: Extent3D(width: 64, height: 64),
                mipLevel: 0,
                data: ptr.baseAddress!,
                bytesPerRow: 64 * 4
            )
        }

        // Note: replaceRegion writes TO texture, we need to read FROM it.
        // Use the Metal texture directly for readback.
        guard let metalTexture = renderTarget as? GamaMetal.MetalTexture else {
            Issue.record("Expected MetalTexture")
            return
        }
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: 64, height: 64, depth: 1))
        pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBytes { ptr in
            metalTexture.mtlTexture.getBytes(
                ptr.baseAddress!,
                bytesPerRow: 64 * 4,
                from: region,
                mipmapLevel: 0
            )
        }

        // Center pixel (32, 32) — index = (32 * 64 + 32) * 4
        let centerIndex = (32 * 64 + 32) * 4
        let r = pixels[centerIndex]
        let g = pixels[centerIndex + 1]
        let b = pixels[centerIndex + 2]
        let a = pixels[centerIndex + 3]

        #expect(r == 255, "Red channel should be 255, got \(r)")
        #expect(g == 0, "Green channel should be 0, got \(g)")
        #expect(b == 0, "Blue channel should be 0, got \(b)")
        #expect(a == 255, "Alpha channel should be 255, got \(a)")
    }

    @Test("Create render pipeline with vertex buffer layout")
    func createPipelineWithLayout() throws {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexIn {
            float2 position [[attribute(0)]];
        };
        struct VertexOut {
            float4 position [[position]];
        };
        vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
            VertexOut out;
            out.position = float4(in.position, 0.0, 1.0);
            return out;
        }
        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return float4(1.0, 1.0, 1.0, 1.0);
        }
        """
        let shaderModule = try device.createShaderModule(source: source)
        let vertexLayout = GPUVertexBufferLayout(
            stride: MemoryLayout<Float>.stride * 2,
            stepFunction: .perVertex,
            attributes: [
                GPUVertexAttribute(format: .float2, offset: 0, shaderLocation: 0)
            ]
        )
        let pipelineDesc = GPURenderPipelineDescriptor(
            vertexFunction: GPUShaderFunction(module: shaderModule, entryPoint: "vertex_main", stage: .vertex),
            fragmentFunction: GPUShaderFunction(module: shaderModule, entryPoint: "fragment_main", stage: .fragment),
            vertexBufferLayouts: [vertexLayout],
            colorTargets: [GPUColorTargetState(format: .rgba8Unorm)]
        )
        let pipeline = try device.createRenderPipeline(descriptor: pipelineDesc)
        #expect(pipeline != nil)
    }
}

#endif
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter MetalRenderPipelineTests 2>&1 | tail -15`
Expected: All 3 tests pass. If the pixel readback test fails, debug by checking that `storageModeShared` textures support `getBytes` (they do on macOS).

- [ ] **Step 3: Commit**

```bash
git add Tests/GamaMetalTests/MetalRenderPipelineTests.swift
git commit -m "test(metal): add end-to-end render pipeline tests with pixel readback"
```

---

## Task 8: Add headless render demo subcommand

**Files:**
- Create: `Sources/GamaDemo/RenderCommand.swift`
- Modify: `Sources/GamaDemo/GamaDemo.swift`

- [ ] **Step 1: Create the render subcommand**

```swift
// Sources/GamaDemo/RenderCommand.swift

import ArgumentParser
import GamaCore
#if canImport(Metal)
import GamaMetal
import Metal
#endif

struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a triangle to an offscreen texture (headless)"
    )

    func run() async throws {
        print("Gama GPU Graphics API — Headless Render")
        print("========================================")

        #if canImport(Metal)
        // 1. Setup
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let queue = try device.createQueue()
        print("Device: \(adapter.info.name)")

        // 2. Compile shader
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut {
            float4 position [[position]];
        };
        vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
            float2 positions[3] = {
                float2( 0.0,  1.0),
                float2(-1.0, -1.0),
                float2( 1.0, -1.0)
            };
            VertexOut out;
            out.position = float4(positions[vid], 0.0, 1.0);
            return out;
        }
        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return float4(0.0, 1.0, 0.0, 1.0);
        }
        """
        let shaderModule = try device.createShaderModule(source: shaderSource)
        print("Shader compiled.")

        // 3. Create 128x128 offscreen render target
        let texDesc = GPUTextureDescriptor(
            width: 128, height: 128,
            format: .rgba8Unorm,
            usage: [.renderTarget, .shaderRead]
        )
        let renderTarget = try device.createTexture(descriptor: texDesc)
        print("Render target: 128x128 RGBA8")

        // 4. Create pipeline
        let pipelineDesc = GPURenderPipelineDescriptor(
            vertexFunction: GPUShaderFunction(module: shaderModule, entryPoint: "vertex_main", stage: .vertex),
            fragmentFunction: GPUShaderFunction(module: shaderModule, entryPoint: "fragment_main", stage: .fragment),
            vertexBufferLayouts: [],
            colorTargets: [GPUColorTargetState(format: .rgba8Unorm)]
        )
        let pipeline = try device.createRenderPipeline(descriptor: pipelineDesc)
        print("Render pipeline created.")

        // 5. Render
        let cmdBuffer = try queue.createCommandBuffer()
        let rpDesc = GPURenderPassDescriptor(
            colorAttachments: [
                GPUColorAttachment(
                    texture: renderTarget,
                    loadAction: .clear,
                    storeAction: .store,
                    clearColor: ClearColor(r: 0.1, g: 0.1, b: 0.2, a: 1.0)
                )
            ]
        )
        let encoder = try cmdBuffer.makeRenderCommandEncoder(descriptor: rpDesc)
        encoder.setRenderPipeline(pipeline)
        encoder.setViewport(x: 0, y: 0, width: 128, height: 128, minDepth: 0, maxDepth: 1)
        encoder.draw(vertexCount: 3)
        encoder.endEncoding()
        cmdBuffer.commit()
        try await cmdBuffer.waitUntilCompleted()
        print("Triangle rendered!")

        // 6. Read back center pixel
        guard let metalTexture = renderTarget as? GamaMetal.MetalTexture else {
            print("Error: unexpected texture type")
            return
        }
        var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: 128, height: 128, depth: 1))
        pixels.withUnsafeMutableBytes { ptr in
            metalTexture.mtlTexture.getBytes(ptr.baseAddress!, bytesPerRow: 128 * 4, from: region, mipmapLevel: 0)
        }

        let cx = (64 * 128 + 64) * 4
        print("Center pixel: R=\(pixels[cx]) G=\(pixels[cx+1]) B=\(pixels[cx+2]) A=\(pixels[cx+3])")
        print()
        print("Render complete!")
        #else
        print("Metal is not available on this platform.")
        #endif
    }
}
```

- [ ] **Step 2: Register the subcommand**

In `Sources/GamaDemo/GamaDemo.swift`, add `Render.self` to the subcommands array:

```swift
    static let configuration = CommandConfiguration(
        abstract: "Gama GPU Graphics API Demo",
        subcommands: [Info.self, Triangle.self, Render.self],
        defaultSubcommand: Info.self
    )
```

- [ ] **Step 3: Build and run**

Run: `swift build 2>&1 | tail -5`
Expected: Build complete!

Run: `swift run GamaDemo render 2>&1`
Expected: Shows "Triangle rendered!" and center pixel with G=255 (green triangle on dark blue background)

- [ ] **Step 4: Commit**

```bash
git add Sources/GamaDemo/RenderCommand.swift Sources/GamaDemo/GamaDemo.swift
git commit -m "feat(demo): add headless render-to-texture triangle demo"
```

---

## Task 9: Update CLAUDE.md and run full verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Add the new files to the package structure section:

In the GamaCore section, add:
```
│   ├── Surface.swift       # GPUSurface protocol for presentable surfaces
│   ├── DepthStencilState.swift # GPUDepthStencilState protocol + descriptor
```

In the GamaMetal section, add:
```
│   ├── MetalSurface.swift         # MetalSurface (wraps CAMetalLayer)
│   ├── MetalDepthStencilState.swift # MetalDepthStencilState
```

Update the demo commands section:
```bash
swift run GamaDemo render           # Headless render-to-texture triangle
```

Update test counts to reflect new tests.

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: All tests pass (previous 36 + new depth/stencil + render pipeline tests)

- [ ] **Step 3: Run all demo commands**

Run: `swift run GamaDemo info 2>&1 && swift run GamaDemo triangle 2>&1 && swift run GamaDemo render 2>&1`
Expected: All three produce correct output

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with surface and depth/stencil additions"
```

---

## Verification Summary

| Command | Expected |
|---------|----------|
| `swift build` | Clean build, 0 errors |
| `swift test` | All tests pass (36 existing + ~6 new) |
| `swift run GamaDemo info` | GPU device info |
| `swift run GamaDemo triangle` | Buffer creation |
| `swift run GamaDemo render` | Headless triangle render with pixel readback |
