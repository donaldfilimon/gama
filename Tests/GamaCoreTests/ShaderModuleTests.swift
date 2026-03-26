// ShaderModuleTests.swift — Tests for ShaderStage and related shader types
// Part of GamaCoreTests

import Testing
@testable import GamaCore

@Suite("ShaderStage Tests")
struct ShaderStageTests {
    @Test("ShaderStage individual stages are distinct")
    func individualStages() {
        let vertex: ShaderStage = .vertex
        let fragment: ShaderStage = .fragment
        let compute: ShaderStage = .compute
        #expect(vertex != fragment)
        #expect(fragment != compute)
        #expect(vertex != compute)
    }

    @Test("ShaderStage rawValues are distinct powers of 2")
    func rawValuesPowersOfTwo() {
        #expect(ShaderStage.vertex.rawValue == 1 << 0)
        #expect(ShaderStage.fragment.rawValue == 1 << 1)
        #expect(ShaderStage.compute.rawValue == 1 << 2)
        // All distinct
        #expect(ShaderStage.vertex.rawValue != ShaderStage.fragment.rawValue)
        #expect(ShaderStage.fragment.rawValue != ShaderStage.compute.rawValue)
        #expect(ShaderStage.vertex.rawValue != ShaderStage.compute.rawValue)
    }

    @Test("ShaderStage combinations contain expected stages")
    func combinations() {
        let vertexFragment: ShaderStage = [.vertex, .fragment]
        #expect(vertexFragment.contains(.vertex))
        #expect(vertexFragment.contains(.fragment))
        #expect(!vertexFragment.contains(.compute))
    }

    @Test("ShaderStage all stages combination")
    func allStages() {
        let all: ShaderStage = [.vertex, .fragment, .compute]
        #expect(all.contains(.vertex))
        #expect(all.contains(.fragment))
        #expect(all.contains(.compute))
    }

    @Test("ShaderStage union produces correct result")
    func union() {
        let a: ShaderStage = .vertex
        let b: ShaderStage = .fragment
        let combined = a.union(b)
        #expect(combined.contains(.vertex))
        #expect(combined.contains(.fragment))
        #expect(!combined.contains(.compute))
    }

    @Test("ShaderStage intersection")
    func intersection() {
        let a: ShaderStage = [.vertex, .fragment]
        let b: ShaderStage = [.fragment, .compute]
        let result = a.intersection(b)
        #expect(result.contains(.fragment))
        #expect(!result.contains(.vertex))
        #expect(!result.contains(.compute))
    }

    @Test("ShaderStage empty set contains nothing")
    func emptySet() {
        let empty = ShaderStage([])
        #expect(!empty.contains(.vertex))
        #expect(!empty.contains(.fragment))
        #expect(!empty.contains(.compute))
    }

    @Test("ShaderStage is Sendable conformance")
    func sendableConformance() {
        // Compile-time check: ShaderStage conforms to Sendable
        func takeSendable<T: Sendable>(_ value: T) -> T { value }
        let stage = takeSendable(ShaderStage.vertex)
        #expect(stage == .vertex)
    }
}
