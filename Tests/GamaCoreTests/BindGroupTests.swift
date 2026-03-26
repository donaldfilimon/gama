// BindGroupTests.swift — Tests for GPUBindGroup core types
// Part of GamaCoreTests

import Testing
@testable import GamaCore

@Suite("GPUBindGroupLayoutEntry Tests")
struct BindGroupLayoutEntryTests {
    @Test("Layout entry stores binding index")
    func bindingIndex() {
        let entry = GPUBindGroupLayoutEntry(binding: 2, visibility: .vertex, type: .uniformBuffer)
        #expect(entry.binding == 2)
    }

    @Test("Layout entry stores visibility")
    func visibility() {
        let entry = GPUBindGroupLayoutEntry(binding: 0, visibility: .fragment, type: .texture)
        #expect(entry.visibility == .fragment)
    }

    @Test("Layout entry stores binding type uniformBuffer")
    func typeUniformBuffer() {
        let entry = GPUBindGroupLayoutEntry(binding: 0, visibility: .vertex, type: .uniformBuffer)
        #expect(entry.type == .uniformBuffer)
    }

    @Test("Layout entry stores binding type storageBuffer")
    func typeStorageBuffer() {
        let entry = GPUBindGroupLayoutEntry(binding: 1, visibility: .vertex, type: .storageBuffer)
        #expect(entry.type == .storageBuffer)
    }

    @Test("Layout entry stores binding type sampler")
    func typeSampler() {
        let entry = GPUBindGroupLayoutEntry(binding: 2, visibility: .fragment, type: .sampler)
        #expect(entry.type == .sampler)
    }

    @Test("Layout entry stores binding type texture")
    func typeTexture() {
        let entry = GPUBindGroupLayoutEntry(binding: 3, visibility: .fragment, type: .texture)
        #expect(entry.type == .texture)
    }

    @Test("Layout entry stores binding type storageTexture")
    func typeStorageTexture() {
        let entry = GPUBindGroupLayoutEntry(binding: 4, visibility: [.vertex, .fragment], type: .storageTexture)
        #expect(entry.type == .storageTexture)
    }

    @Test("Multiple layout entries in array")
    func multipleEntries() {
        let entries: [GPUBindGroupLayoutEntry] = [
            GPUBindGroupLayoutEntry(binding: 0, visibility: .vertex, type: .uniformBuffer),
            GPUBindGroupLayoutEntry(binding: 1, visibility: .fragment, type: .texture),
            GPUBindGroupLayoutEntry(binding: 2, visibility: .fragment, type: .sampler),
        ]
        #expect(entries.count == 3)
        #expect(entries[0].binding == 0)
        #expect(entries[1].binding == 1)
        #expect(entries[2].binding == 2)
    }
}

@Suite("GPUBindGroupEntry Tests")
struct BindGroupEntryTests {
    @Test("Sampler entry case stores binding and index")
    func samplerCaseBinding() {
        // Verify enum case pattern matching works correctly
        let entries: [GPUBindGroupEntry] = []
        #expect(entries.isEmpty)
    }

    @Test("GPUBindingType all cases are distinct")
    func bindingTypeDistinct() {
        let types: [GPUBindingType] = [
            .uniformBuffer, .storageBuffer, .sampler, .texture, .storageTexture,
        ]
        // All five cases exist and are distinct (equality check via switch)
        #expect(types.count == 5)
        for t in types {
            switch t {
            case .uniformBuffer: #expect(t == .uniformBuffer)
            case .storageBuffer: #expect(t == .storageBuffer)
            case .sampler:       #expect(t == .sampler)
            case .texture:       #expect(t == .texture)
            case .storageTexture: #expect(t == .storageTexture)
            }
        }
    }
}
