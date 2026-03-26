// MetalRenderPipelineTests.swift — End-to-end render pipeline tests
// Part of GamaMetalTests

#if canImport(Metal)
import Metal
import Testing
import GamaCore
@testable import GamaMetal

@Suite("Metal Render Pipeline End-to-End Tests")
struct MetalRenderPipelineTests {
    let device: any GPUDevice
    let queue: any GPUQueue

    init() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        self.device = try adapter.requestDevice()
        self.queue = try device.createQueue()
    }

    // MARK: - Shader Compilation

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
        let metalModule = shaderModule as? MetalShaderModule
        #expect(metalModule != nil)
        #expect(metalModule?.functionNames.contains("vertex_main") == true)
        #expect(metalModule?.functionNames.contains("fragment_main") == true)
    }

    // MARK: - Render to Texture

    @Test("Render red triangle to offscreen texture and verify pixels")
    func renderTriangle() async throws {
        // 1. Compile shader — full-screen triangle outputting red
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

        // 5. Read back pixels using MTLTexture.getBytes (replaceRegion writes TO texture)
        guard let metalTexture = renderTarget as? MetalTexture else {
            Issue.record("Expected MetalTexture")
            return
        }
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: 64, height: 64, depth: 1)
        )
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
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

    // MARK: - Pipeline with Vertex Buffer Layout

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
        let metalPipeline = pipeline as? MetalRenderPipeline
        #expect(metalPipeline != nil)
    }
}

#endif
