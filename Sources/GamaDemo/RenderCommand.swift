// RenderCommand.swift — Headless render-to-texture triangle demo
// Part of GamaDemo

import ArgumentParser
import GamaCore
#if canImport(Metal)
import GamaMetal
import Metal
#endif

/// Renders a green triangle to an offscreen texture and reads back the center pixel.
///
/// This command demonstrates the full Gama rendering pipeline without requiring
/// a window: shader compilation, pipeline creation, command encoding, draw call,
/// and pixel readback.
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
            vertexFunction: GPUShaderFunction(
                module: shaderModule, entryPoint: "vertex_main", stage: .vertex
            ),
            fragmentFunction: GPUShaderFunction(
                module: shaderModule, entryPoint: "fragment_main", stage: .fragment
            ),
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
        encoder.setViewport(
            x: 0, y: 0, width: 128, height: 128, minDepth: 0, maxDepth: 1
        )
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
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: 128, height: 128, depth: 1)
        )
        pixels.withUnsafeMutableBytes { ptr in
            metalTexture.mtlTexture.getBytes(
                ptr.baseAddress!,
                bytesPerRow: 128 * 4,
                from: region,
                mipmapLevel: 0
            )
        }

        let centerIndex = (64 * 128 + 64) * 4
        print("Center pixel: R=\(pixels[centerIndex]) G=\(pixels[centerIndex + 1]) B=\(pixels[centerIndex + 2]) A=\(pixels[centerIndex + 3])")
        print()
        print("Render complete!")
        #else
        print("Metal is not available on this platform.")
        #endif
    }
}
