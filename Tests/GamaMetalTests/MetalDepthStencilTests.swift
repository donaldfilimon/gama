// MetalDepthStencilTests.swift — Tests for Metal depth-stencil state creation
// Part of GamaMetalTests

#if canImport(Metal)

import Testing
import GamaCore
@testable import GamaMetal

@Suite("MetalDepthStencilState Tests")
struct MetalDepthStencilStateTests {
    @Test("Default depth-stencil state creation succeeds")
    func defaultState() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let descriptor = GPUDepthStencilDescriptor(format: .depth32Float)
        let state = try device.createDepthStencilState(descriptor: descriptor)
        #expect(state.descriptor.depthWriteEnabled == true)
        #expect(state.descriptor.depthCompare == .less)
        #expect(state.descriptor.format == .depth32Float)
    }

    @Test("Depth-disabled state creation succeeds")
    func depthDisabled() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let descriptor = GPUDepthStencilDescriptor(
            format: .depth32Float,
            depthWriteEnabled: false,
            depthCompare: .always
        )
        let state = try device.createDepthStencilState(descriptor: descriptor)
        #expect(state.descriptor.depthWriteEnabled == false)
        #expect(state.descriptor.depthCompare == .always)
    }

    @Test("Custom compare function state creation succeeds")
    func customCompareFunction() throws {
        let adapter = try MetalBackend.shared.requestDefaultAdapter()
        let device = try adapter.requestDevice()
        let front = GPUStencilFaceState(
            compare: .notEqual,
            failOperation: .zero,
            depthFailOperation: .replace,
            passOperation: .incrementClamp,
            readMask: 0x0F,
            writeMask: 0xF0
        )
        let descriptor = GPUDepthStencilDescriptor(
            format: .depth32FloatStencil8,
            depthWriteEnabled: true,
            depthCompare: .greaterEqual,
            stencilFront: front
        )
        let state = try device.createDepthStencilState(descriptor: descriptor)
        #expect(state.descriptor.depthCompare == .greaterEqual)
        #expect(state.descriptor.stencilFront.compare == .notEqual)
        #expect(state.descriptor.stencilFront.failOperation == .zero)
        #expect(state.descriptor.stencilFront.readMask == 0x0F)
        #expect(state.descriptor.stencilFront.writeMask == 0xF0)
        // Verify it's a MetalDepthStencilState under the hood
        let metalState = state as? MetalDepthStencilState
        #expect(metalState != nil)
    }
}

#endif
