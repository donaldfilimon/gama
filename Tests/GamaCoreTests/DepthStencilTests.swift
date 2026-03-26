// DepthStencilTests.swift — Tests for depth-stencil state types
// Part of GamaCoreTests

import Testing
@testable import GamaCore

@Suite("StencilOperation Tests")
struct StencilOperationTests {
    @Test("All 8 cases exist")
    func allCases() {
        let ops: [StencilOperation] = [
            .keep,
            .zero,
            .replace,
            .incrementClamp,
            .decrementClamp,
            .invert,
            .incrementWrap,
            .decrementWrap,
        ]
        #expect(ops.count == 8)
    }
}

@Suite("GPUStencilFaceState Tests")
struct GPUStencilFaceStateTests {
    @Test("Default values are correct")
    func defaults() {
        let state = GPUStencilFaceState()
        #expect(state.compare == .always)
        #expect(state.failOperation == .keep)
        #expect(state.depthFailOperation == .keep)
        #expect(state.passOperation == .keep)
        #expect(state.readMask == 0xFF)
        #expect(state.writeMask == 0xFF)
    }

    @Test("Custom values are stored correctly")
    func customValues() {
        let state = GPUStencilFaceState(
            compare: .equal,
            failOperation: .replace,
            depthFailOperation: .invert,
            passOperation: .incrementWrap,
            readMask: 0x0F,
            writeMask: 0xF0
        )
        #expect(state.compare == .equal)
        #expect(state.failOperation == .replace)
        #expect(state.depthFailOperation == .invert)
        #expect(state.passOperation == .incrementWrap)
        #expect(state.readMask == 0x0F)
        #expect(state.writeMask == 0xF0)
    }
}

@Suite("GPUDepthStencilState Tests")
struct GPUDepthStencilStateTests {
    @Test("Default values are correct")
    func defaults() {
        let state = GPUDepthStencilState(format: .depth32Float)
        #expect(state.format == .depth32Float)
        #expect(state.depthWriteEnabled == true)
        #expect(state.depthCompare == .less)
        #expect(state.stencilFront.compare == .always)
        #expect(state.stencilBack.compare == .always)
    }

    @Test("Custom values are stored correctly")
    func customValues() {
        let front = GPUStencilFaceState(compare: .notEqual, failOperation: .zero, depthFailOperation: .keep, passOperation: .replace, readMask: 0x01, writeMask: 0x01)
        let back = GPUStencilFaceState(compare: .less, failOperation: .keep, depthFailOperation: .decrementClamp, passOperation: .incrementClamp, readMask: 0x02, writeMask: 0x02)
        let state = GPUDepthStencilState(
            format: .depth32FloatStencil8,
            depthWriteEnabled: false,
            depthCompare: .greaterEqual,
            stencilFront: front,
            stencilBack: back
        )
        #expect(state.format == .depth32FloatStencil8)
        #expect(state.depthWriteEnabled == false)
        #expect(state.depthCompare == .greaterEqual)
        #expect(state.stencilFront.compare == .notEqual)
        #expect(state.stencilFront.failOperation == .zero)
        #expect(state.stencilFront.passOperation == .replace)
        #expect(state.stencilFront.readMask == 0x01)
        #expect(state.stencilBack.compare == .less)
        #expect(state.stencilBack.depthFailOperation == .decrementClamp)
        #expect(state.stencilBack.passOperation == .incrementClamp)
        #expect(state.stencilBack.writeMask == 0x02)
    }
}
