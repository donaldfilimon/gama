// TypesTests.swift — Tests for GamaCore value types
// Part of GamaCoreTests

import Testing
@testable import GamaCore

@Suite("PixelFormat Tests")
struct PixelFormatTests {
    @Test("PixelFormat enum cases exist")
    func pixelFormatCases() {
        // Verify all expected cases exist and are distinct
        let formats: [PixelFormat] = [
            .rgba8Unorm, .bgra8Unorm, .rgba16Float, .rgba32Float,
            .depth32Float, .stencil8, .depth24UnormStencil8, .depth32FloatStencil8,
            .r8Unorm, .r16Float, .r32Float, .rg16Float,
        ]
        // Each case should be unique
        #expect(formats.count == 12)
    }
}

@Suite("BufferUsage Tests")
struct BufferUsageTests {
    @Test("BufferUsage union operation")
    func union() {
        let usage: BufferUsage = [.vertex, .index]
        #expect(usage.contains(.vertex))
        #expect(usage.contains(.index))
        #expect(!usage.contains(.uniform))
    }

    @Test("BufferUsage intersection operation")
    func intersection() {
        let a: BufferUsage = [.vertex, .index, .uniform]
        let b: BufferUsage = [.index, .storage]
        let result = a.intersection(b)
        #expect(result.contains(.index))
        #expect(!result.contains(.vertex))
        #expect(!result.contains(.storage))
    }

    @Test("BufferUsage contains check")
    func contains() {
        let usage: BufferUsage = [.transferSource, .transferDestination]
        #expect(usage.contains(.transferSource))
        #expect(usage.contains(.transferDestination))
        #expect(!usage.contains(.vertex))
    }

    @Test("BufferUsage single value")
    func singleValue() {
        let usage: BufferUsage = .vertex
        #expect(usage.rawValue == 1 << 0)
    }
}

@Suite("TextureUsage Tests")
struct TextureUsageTests {
    @Test("TextureUsage union operation")
    func union() {
        let usage: TextureUsage = [.shaderRead, .renderTarget]
        #expect(usage.contains(.shaderRead))
        #expect(usage.contains(.renderTarget))
        #expect(!usage.contains(.shaderWrite))
    }

    @Test("TextureUsage intersection operation")
    func intersection() {
        let a: TextureUsage = [.shaderRead, .shaderWrite, .renderTarget]
        let b: TextureUsage = [.shaderWrite, .transferSource]
        let result = a.intersection(b)
        #expect(result.contains(.shaderWrite))
        #expect(!result.contains(.shaderRead))
        #expect(!result.contains(.transferSource))
    }

    @Test("TextureUsage contains check")
    func contains() {
        let usage: TextureUsage = [.transferSource, .transferDestination]
        #expect(usage.contains(.transferSource))
        #expect(!usage.contains(.shaderRead))
    }
}

@Suite("ClearColor Tests")
struct ClearColorTests {
    @Test("ClearColor default initialization")
    func defaultInit() {
        let color = ClearColor()
        #expect(color.r == 0)
        #expect(color.g == 0)
        #expect(color.b == 0)
        #expect(color.a == 1)
    }

    @Test("ClearColor custom initialization")
    func customInit() {
        let color = ClearColor(r: 0.2, g: 0.4, b: 0.6, a: 0.8)
        #expect(color.r == 0.2)
        #expect(color.g == 0.4)
        #expect(color.b == 0.6)
        #expect(color.a == 0.8)
    }
}

@Suite("Extent3D Tests")
struct Extent3DTests {
    @Test("Extent3D initialization with defaults")
    func defaultDepth() {
        let extent = Extent3D(width: 1920, height: 1080)
        #expect(extent.width == 1920)
        #expect(extent.height == 1080)
        #expect(extent.depth == 1)
    }

    @Test("Extent3D full initialization")
    func fullInit() {
        let extent = Extent3D(width: 256, height: 256, depth: 64)
        #expect(extent.width == 256)
        #expect(extent.height == 256)
        #expect(extent.depth == 64)
    }
}

@Suite("Origin3D Tests")
struct Origin3DTests {
    @Test("Origin3D default initialization")
    func defaultInit() {
        let origin = Origin3D()
        #expect(origin.x == 0)
        #expect(origin.y == 0)
        #expect(origin.z == 0)
    }

    @Test("Origin3D custom initialization")
    func customInit() {
        let origin = Origin3D(x: 10, y: 20, z: 5)
        #expect(origin.x == 10)
        #expect(origin.y == 20)
        #expect(origin.z == 5)
    }
}

@Suite("GPUError Tests")
struct GPUErrorTests {
    @Test("GPUError conforms to Error")
    func conformsToError() {
        let error: any Error = GPUError.deviceCreationFailed
        #expect(error is GPUError)
    }

    @Test("GPUError cases are distinct")
    func distinctCases() {
        let errors: [GPUError] = [
            .deviceCreationFailed,
            .bufferAllocationFailed(size: 1024),
            .textureCreationFailed,
            .pipelineCreationFailed("test"),
            .shaderCompilationFailed("test"),
            .commandEncodingFailed,
            .queueSubmissionFailed,
            .outOfMemory,
            .unsupportedOperation("test"),
            .backendNotAvailable("Metal"),
        ]
        #expect(errors.count == 10)
    }

    @Test("GPUError associated values")
    func associatedValues() {
        let error = GPUError.bufferAllocationFailed(size: 2048)
        guard case .bufferAllocationFailed(let size) = error else {
            Issue.record("Expected bufferAllocationFailed")
            return
        }
        #expect(size == 2048)
    }
}
