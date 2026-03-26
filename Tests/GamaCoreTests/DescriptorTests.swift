// DescriptorTests.swift — Tests for GamaCore descriptor types
// Part of GamaCoreTests

import Testing
@testable import GamaCore

@Suite("GPUTextureDescriptor Tests")
struct TextureDescriptorTests {
    @Test("Full texture descriptor creation")
    func fullCreation() {
        let desc = GPUTextureDescriptor(
            width: 512,
            height: 512,
            depth: 1,
            format: .rgba8Unorm,
            usage: [.shaderRead, .renderTarget],
            dimension: .d2,
            mipLevelCount: 4,
            sampleCount: 1,
            label: "Test Texture"
        )
        #expect(desc.width == 512)
        #expect(desc.height == 512)
        #expect(desc.depth == 1)
        #expect(desc.format == .rgba8Unorm)
        #expect(desc.usage.contains(.shaderRead))
        #expect(desc.usage.contains(.renderTarget))
        #expect(desc.dimension == .d2)
        #expect(desc.mipLevelCount == 4)
        #expect(desc.sampleCount == 1)
        #expect(desc.label == "Test Texture")
    }

    @Test("2D convenience initializer")
    func convenience2D() {
        let desc = GPUTextureDescriptor(
            width: 256,
            height: 256,
            format: .rgba8Unorm,
            usage: .shaderRead
        )
        #expect(desc.width == 256)
        #expect(desc.height == 256)
        #expect(desc.depth == 1)
        #expect(desc.dimension == .d2)
        #expect(desc.mipLevelCount == 1)
        #expect(desc.sampleCount == 1)
        #expect(desc.label == nil)
    }

    @Test("3D texture descriptor")
    func texture3D() {
        let desc = GPUTextureDescriptor(
            width: 64,
            height: 64,
            depth: 64,
            format: .rgba16Float,
            usage: [.shaderRead, .shaderWrite],
            dimension: .d3
        )
        #expect(desc.depth == 64)
        #expect(desc.dimension == .d3)
    }
}

@Suite("GPUSamplerDescriptor Tests")
struct SamplerDescriptorTests {
    @Test("Default sampler values")
    func defaultValues() {
        let desc = GPUSamplerDescriptor()
        #expect(desc.minFilter == .nearest)
        #expect(desc.magFilter == .nearest)
        #expect(desc.mipFilter == .notMipmapped)
        #expect(desc.addressModeU == .clampToEdge)
        #expect(desc.addressModeV == .clampToEdge)
        #expect(desc.addressModeW == .clampToEdge)
        #expect(desc.maxAnisotropy == 1)
        #expect(desc.compareFunction == nil)
        #expect(desc.label == nil)
    }

    @Test("Custom sampler values")
    func customValues() {
        let desc = GPUSamplerDescriptor(
            minFilter: .linear,
            magFilter: .linear,
            mipFilter: .linear,
            addressModeU: .repeat,
            addressModeV: .repeat,
            addressModeW: .clampToZero,
            maxAnisotropy: 16,
            compareFunction: .less,
            label: "Trilinear Sampler"
        )
        #expect(desc.minFilter == .linear)
        #expect(desc.magFilter == .linear)
        #expect(desc.mipFilter == .linear)
        #expect(desc.addressModeU == .repeat)
        #expect(desc.maxAnisotropy == 16)
        #expect(desc.compareFunction == .less)
        #expect(desc.label == "Trilinear Sampler")
    }
}

@Suite("GPURenderPipelineDescriptor Tests")
struct RenderPipelineDescriptorTests {
    @Test("Render pipeline descriptor construction")
    func construction() {
        // We can test the structural types without needing a real shader module
        let layout = GPUVertexBufferLayout(
            stride: 16,
            stepFunction: .perVertex,
            attributes: [
                GPUVertexAttribute(format: .float2, offset: 0, shaderLocation: 0),
                GPUVertexAttribute(format: .float2, offset: 8, shaderLocation: 1),
            ]
        )
        #expect(layout.stride == 16)
        #expect(layout.stepFunction == .perVertex)
        #expect(layout.attributes.count == 2)
        #expect(layout.attributes[0].format == .float2)
        #expect(layout.attributes[0].offset == 0)
        #expect(layout.attributes[1].shaderLocation == 1)
    }

    @Test("Color target state construction")
    func colorTargetState() {
        let target = GPUColorTargetState(format: .bgra8Unorm)
        #expect(target.format == .bgra8Unorm)
        #expect(target.blendEnabled == false)
        #expect(target.sourceRGBBlendFactor == .one)
        #expect(target.destinationRGBBlendFactor == .zero)
        #expect(target.rgbBlendOperation == .add)
    }

    @Test("Color target state with blending")
    func colorTargetWithBlending() {
        let target = GPUColorTargetState(
            format: .rgba8Unorm,
            blendEnabled: true,
            sourceRGBBlendFactor: .sourceAlpha,
            destinationRGBBlendFactor: .oneMinusSourceAlpha,
            rgbBlendOperation: .add,
            sourceAlphaBlendFactor: .one,
            destinationAlphaBlendFactor: .zero,
            alphaBlendOperation: .add
        )
        #expect(target.blendEnabled == true)
        #expect(target.sourceRGBBlendFactor == .sourceAlpha)
        #expect(target.destinationRGBBlendFactor == .oneMinusSourceAlpha)
    }
}

@Suite("GPURenderPassDescriptor Tests")
struct RenderPassDescriptorTests {
    @Test("Empty render pass descriptor")
    func emptyDescriptor() {
        let desc = GPURenderPassDescriptor(colorAttachments: [])
        #expect(desc.colorAttachments.isEmpty)
        #expect(desc.depthStencilAttachment == nil)
        #expect(desc.label == nil)
    }

    @Test("Render pass descriptor with label")
    func withLabel() {
        let desc = GPURenderPassDescriptor(
            colorAttachments: [],
            label: "Main Pass"
        )
        #expect(desc.label == "Main Pass")
    }
}
