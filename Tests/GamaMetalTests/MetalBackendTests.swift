// MetalBackendTests.swift — Metal-specific integration tests
// Part of GamaMetalTests

#if canImport(Metal)

import Testing
import GamaCore
@testable import GamaMetal

@Suite("MetalBackend Tests")
struct MetalBackendTests {
    @Test("Request default adapter succeeds")
    func requestDefaultAdapter() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        #expect(adapter.info.name.isEmpty == false)
    }

    @Test("Adapter info has non-empty name")
    func adapterInfoName() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let info = adapter.info
        #expect(!info.name.isEmpty)
        #expect(!info.vendor.isEmpty)
        #expect(info.maxBufferSize > 0)
        #expect(info.maxTextureSize > 0)
    }

    @Test("Enumerate adapters returns at least one")
    func enumerateAdapters() {
        let adapters = MetalBackend.shared.enumerateAdapters()
        #expect(!adapters.isEmpty)
    }
}

@Suite("MetalDevice Tests")
struct MetalDeviceTests {
    @Test("Device creation from adapter")
    func deviceCreation() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        #expect(!device.adapter.name.isEmpty)
    }

    @Test("Buffer creation with small size")
    func bufferCreation() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let buffer = try device.createBuffer(size: 256, usage: .vertex)
        #expect(buffer.size == 256)
        #expect(buffer.usage.contains(.vertex))
    }

    @Test("Buffer creation and data write")
    func bufferDataWrite() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let data: [Float] = [1.0, 2.0, 3.0, 4.0]
        let size = data.count * MemoryLayout<Float>.stride
        let buffer = try device.createBuffer(size: size, usage: [.vertex, .transferDestination])

        data.withUnsafeBufferPointer { ptr in
            buffer.contents().copyMemory(from: ptr.baseAddress!, byteCount: size)
        }
        buffer.didModifyRange(0..<size)

        #expect(buffer.size == size)
    }

    @Test("Texture creation 2D rgba8Unorm 256x256")
    func textureCreation() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let desc = GPUTextureDescriptor(
            width: 256,
            height: 256,
            format: .rgba8Unorm,
            usage: [.shaderRead, .renderTarget]
        )
        let texture = try device.createTexture(descriptor: desc)
        #expect(texture.width == 256)
        #expect(texture.height == 256)
        #expect(texture.format == .rgba8Unorm)
    }

    @Test("Queue creation")
    func queueCreation() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let queue = try device.createQueue()
        // Queue was created successfully if no error was thrown
        _ = queue
    }

    @Test("Sampler creation with label")
    func samplerCreation() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let desc = GPUSamplerDescriptor(label: "Test Sampler")
        let sampler = try device.createSampler(descriptor: desc)
        _ = sampler
    }
}

@Suite("MetalDevice BindGroup Tests")
struct MetalDeviceBindGroupTests {
    @Test("createBindGroupLayout returns layout with matching entries")
    func createBindGroupLayout() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let entries: [GPUBindGroupLayoutEntry] = [
            GPUBindGroupLayoutEntry(binding: 0, visibility: .vertex, type: .uniformBuffer),
            GPUBindGroupLayoutEntry(binding: 1, visibility: .fragment, type: .texture),
        ]
        let layout = try device.createBindGroupLayout(entries: entries)
        #expect(layout.entries.count == 2)
        #expect(layout.entries[0].binding == 0)
        #expect(layout.entries[0].type == .uniformBuffer)
        #expect(layout.entries[1].binding == 1)
        #expect(layout.entries[1].type == .texture)
    }

    @Test("createBindGroupLayout with label stores label")
    func createBindGroupLayoutWithLabel() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let layout = try device.createBindGroupLayout(entries: [], label: "TestLayout")
        // Cast to MetalBindGroupLayout to verify label storage
        let metalLayout = layout as! MetalBindGroupLayout
        #expect(metalLayout.label == "TestLayout")
    }

    @Test("createBindGroupLayout default label is nil")
    func createBindGroupLayoutDefaultLabel() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let layout = try device.createBindGroupLayout(entries: [])
        let metalLayout = layout as! MetalBindGroupLayout
        #expect(metalLayout.label == nil)
    }

    @Test("createBindGroup returns bind group with correct layout")
    func createBindGroup() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let entries: [GPUBindGroupLayoutEntry] = [
            GPUBindGroupLayoutEntry(binding: 0, visibility: .vertex, type: .uniformBuffer),
        ]
        let layout = try device.createBindGroupLayout(entries: entries)
        let bindGroup = try device.createBindGroup(layout: layout, entries: [])
        // Verify the bind group references the same layout
        #expect(bindGroup.layout === layout)
    }

    @Test("createBindGroup with buffer entry")
    func createBindGroupWithBuffer() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let buffer = try device.createBuffer(size: 256, usage: .uniform)
        let layoutEntries: [GPUBindGroupLayoutEntry] = [
            GPUBindGroupLayoutEntry(binding: 0, visibility: .vertex, type: .uniformBuffer),
        ]
        let layout = try device.createBindGroupLayout(entries: layoutEntries)
        let bindGroupEntries: [GPUBindGroupEntry] = [
            .buffer(binding: 0, buffer: buffer, offset: 0, size: 256),
        ]
        let bindGroup = try device.createBindGroup(layout: layout, entries: bindGroupEntries)
        let metalBindGroup = bindGroup as! MetalBindGroup
        #expect(metalBindGroup.entries.count == 1)
    }
}

#endif
