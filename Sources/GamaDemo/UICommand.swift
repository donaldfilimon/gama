// UICommand.swift — Interactive GPU window subcommand for GamaDemo
// Part of GamaDemo

import ArgumentParser
import GamaCore
#if canImport(Metal) && canImport(AppKit)
import Metal
import AppKit
import QuartzCore
import GamaMetal
#endif

struct UI: @preconcurrency ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a window and render a colored triangle using the full Gama pipeline"
    )

    @MainActor
    func run() throws {
        print("Gama GPU Graphics API — Interactive UI Demo")
        print("============================================")

        #if canImport(Metal) && canImport(AppKit)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let delegate = GamaDemoAppDelegate()
        app.delegate = delegate
        app.run()
        #else
        print()
        print("UI demo requires Metal and AppKit (macOS only).")
        #endif
    }
}

// MARK: - macOS Application

#if canImport(Metal) && canImport(AppKit)

@MainActor
private class GamaDemoAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var metalView: NSView!
    nonisolated(unsafe) private var metalLayer: CAMetalLayer!
    private var renderer: GamaTriangleRenderer!
    private var renderTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gama — Triangle Demo"
        window.center()

        // Set up a layer-backed view with a CAMetalLayer
        metalView = NSView(frame: contentRect)
        metalView.wantsLayer = true

        metalLayer = CAMetalLayer()
        guard let mtlDevice = MTLCreateSystemDefaultDevice() else {
            print("Error: Metal is not available on this system.")
            NSApp.terminate(nil)
            return
        }
        metalLayer.device = mtlDevice
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = metalView.bounds
        metalLayer.contentsScale = window.backingScaleFactor
        metalView.layer = metalLayer

        window.contentView = metalView

        do {
            renderer = try GamaTriangleRenderer(metalLayer: metalLayer)
        } catch {
            print("Error: Failed to initialize renderer: \(error)")
            NSApp.terminate(nil)
            return
        }

        // Render loop at ~60 fps
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Update layer size if window was resized
                let bounds = self.metalView.bounds
                if self.metalLayer.frame != bounds {
                    self.metalLayer.frame = bounds
                    self.metalLayer.drawableSize = CGSize(
                        width: bounds.width * self.window.backingScaleFactor,
                        height: bounds.height * self.window.backingScaleFactor
                    )
                }
                self.renderer.render()
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("Window opened. Close the window to exit.")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        renderTimer?.invalidate()
    }
}

// MARK: - Renderer

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(uint vid [[vertex_id]],
                             constant packed_float2 *positions [[buffer(0)]],
                             constant packed_float4 *colors    [[buffer(1)]]) {
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.color = colors[vid];
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
"""

// Workaround for Swift 6.4 region-based isolation checker bug with MTLCommandBuffer.present
private func presentDrawable(_ commandBuffer: MTLCommandBuffer, _ drawable: CAMetalDrawable) {
    commandBuffer.present(drawable)
}

@MainActor
private class GamaTriangleRenderer {
    let device: any GPUDevice
    let queue: any GPUQueue
    let pipeline: any GPURenderPipeline
    let positionBuffer: any GPUBuffer
    let colorBuffer: any GPUBuffer
    let metalLayer: CAMetalLayer

    init(metalLayer: CAMetalLayer) throws {
        self.metalLayer = metalLayer

        // 1. Adapter → Device → Queue (all via Gama API)
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        device = try adapter.requestDevice()
        queue = try device.createQueue()

        print("Device: \(adapter.info.name)")

        // 2. Compile shaders via Gama API
        let shaderModule = try device.createShaderModule(source: shaderSource)

        let vertexFunction = GPUShaderFunction(
            module: shaderModule,
            entryPoint: "vertex_main",
            stage: .vertex
        )
        let fragmentFunction = GPUShaderFunction(
            module: shaderModule,
            entryPoint: "fragment_main",
            stage: .fragment
        )

        // 3. Create render pipeline via Gama API
        let pipelineDescriptor = GPURenderPipelineDescriptor(
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            colorTargets: [
                GPUColorTargetState(format: .bgra8Unorm)
            ],
            label: "Triangle Pipeline"
        )
        pipeline = try device.createRenderPipeline(descriptor: pipelineDescriptor)

        // 4. Create vertex data buffers via Gama API
        //    Triangle: top (red), bottom-left (green), bottom-right (blue)
        let positions: [Float] = [
             0.0,  0.5,    // top center
            -0.5, -0.5,    // bottom left
             0.5, -0.5,    // bottom right
        ]
        let colors: [Float] = [
            1.0, 0.0, 0.0, 1.0,  // red
            0.0, 1.0, 0.0, 1.0,  // green
            0.0, 0.0, 1.0, 1.0,  // blue
        ]

        let posSize = positions.count * MemoryLayout<Float>.stride
        let colSize = colors.count * MemoryLayout<Float>.stride

        positionBuffer = try device.createBuffer(size: posSize, usage: .vertex)
        colorBuffer = try device.createBuffer(size: colSize, usage: .vertex)

        positions.withUnsafeBufferPointer { ptr in
            positionBuffer.contents().copyMemory(from: ptr.baseAddress!, byteCount: posSize)
        }
        positionBuffer.didModifyRange(0..<posSize)

        colors.withUnsafeBufferPointer { ptr in
            colorBuffer.contents().copyMemory(from: ptr.baseAddress!, byteCount: colSize)
        }
        colorBuffer.didModifyRange(0..<colSize)

        print("Render pipeline and vertex buffers created.")
    }

    func render() {
        guard let drawable = metalLayer.nextDrawable() else { return }

        // Wrap the drawable's texture in a Gama MetalTexture
        let drawableDescriptor = GPUTextureDescriptor(
            width: UInt32(drawable.texture.width),
            height: UInt32(drawable.texture.height),
            format: .bgra8Unorm,
            usage: .renderTarget
        )
        let drawableTexture = MetalTexture(
            texture: drawable.texture,
            descriptor: drawableDescriptor
        )

        // Build render pass via Gama API
        let renderPassDesc = GPURenderPassDescriptor(
            colorAttachments: [
                GPUColorAttachment(
                    texture: drawableTexture,
                    loadAction: .clear,
                    storeAction: .store,
                    clearColor: ClearColor(r: 0.08, g: 0.08, b: 0.12, a: 1.0)
                )
            ],
            label: "Triangle Pass"
        )

        do {
            let commandBuffer = try queue.createCommandBuffer()
            let encoder = try commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)

            encoder.setRenderPipeline(pipeline)
            encoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
            encoder.draw(vertexCount: 3)
            encoder.endEncoding()

            // Present the drawable (requires direct Metal access)
            guard let metalCB = commandBuffer as? MetalCommandBuffer else { return }
            presentDrawable(metalCB.mtlCommandBuffer, drawable)

            commandBuffer.commit()
        } catch {
            print("Render error: \(error)")
        }
    }
}

#endif
