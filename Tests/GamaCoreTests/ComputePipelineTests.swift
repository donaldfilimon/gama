// ComputePipelineTests.swift — Tests for GPUComputePipelineDescriptor
// Part of GamaCoreTests

import Testing
@testable import GamaCore

// MARK: - Minimal stub for tests requiring a GPUShaderModule

private final class StubShaderModule: GPUShaderModule, @unchecked Sendable {
    let label: String?
    init(label: String? = nil) { self.label = label }
}

@Suite("GPUComputePipelineDescriptor Tests")
struct ComputePipelineDescriptorTests {
    private var stubModule: StubShaderModule { StubShaderModule(label: "stub") }

    @Test("Descriptor stores compute function")
    func storesComputeFunction() {
        let fn = GPUShaderFunction(module: stubModule, entryPoint: "main", stage: .compute)
        let desc = GPUComputePipelineDescriptor(computeFunction: fn)
        #expect(desc.computeFunction.entryPoint == "main")
        #expect(desc.computeFunction.stage == .compute)
    }

    @Test("Descriptor default label is nil")
    func defaultLabelIsNil() {
        let fn = GPUShaderFunction(module: stubModule, entryPoint: "main", stage: .compute)
        let desc = GPUComputePipelineDescriptor(computeFunction: fn)
        #expect(desc.label == nil)
    }

    @Test("Descriptor stores custom label")
    func customLabel() {
        let fn = GPUShaderFunction(module: stubModule, entryPoint: "computeKernel", stage: .compute)
        let desc = GPUComputePipelineDescriptor(computeFunction: fn, label: "My Compute Pipeline")
        #expect(desc.label == "My Compute Pipeline")
    }

    @Test("Descriptor entry point is preserved")
    func entryPointPreserved() {
        let entryPoints = ["computeMain", "particleUpdate", "skinningPass"]
        for ep in entryPoints {
            let fn = GPUShaderFunction(module: stubModule, entryPoint: ep, stage: .compute)
            let desc = GPUComputePipelineDescriptor(computeFunction: fn)
            #expect(desc.computeFunction.entryPoint == ep)
        }
    }

    @Test("Descriptor function stage is compute")
    func functionStageIsCompute() {
        let fn = GPUShaderFunction(module: stubModule, entryPoint: "main", stage: .compute)
        let desc = GPUComputePipelineDescriptor(computeFunction: fn)
        #expect(desc.computeFunction.stage == .compute)
        #expect(!desc.computeFunction.stage.contains(.vertex))
        #expect(!desc.computeFunction.stage.contains(.fragment))
    }

    @Test("Descriptor is mutable after creation")
    func mutability() {
        let fn = GPUShaderFunction(module: stubModule, entryPoint: "main", stage: .compute)
        var desc = GPUComputePipelineDescriptor(computeFunction: fn)
        desc.label = "Updated Label"
        #expect(desc.label == "Updated Label")
    }
}

@Suite("GPUShaderFunction Tests")
struct ShaderFunctionTests {
    private var stubModule: StubShaderModule { StubShaderModule(label: "stub") }

    @Test("ShaderFunction stores entry point")
    func storesEntryPoint() {
        let fn = GPUShaderFunction(module: stubModule, entryPoint: "vertMain", stage: .vertex)
        #expect(fn.entryPoint == "vertMain")
    }

    @Test("ShaderFunction stores stage")
    func storesStage() {
        let fn = GPUShaderFunction(module: stubModule, entryPoint: "fragMain", stage: .fragment)
        #expect(fn.stage == .fragment)
    }

    @Test("ShaderFunction stores module label via protocol")
    func storesModuleLabel() {
        let module = StubShaderModule(label: "MyShader")
        let fn = GPUShaderFunction(module: module, entryPoint: "main", stage: .vertex)
        #expect(fn.module.label == "MyShader")
    }

    @Test("ShaderFunction all pipeline stages can be assigned")
    func allStagesAssignable() {
        let stages: [ShaderStage] = [.vertex, .fragment, .compute]
        for stage in stages {
            let fn = GPUShaderFunction(module: stubModule, entryPoint: "main", stage: stage)
            #expect(fn.stage == stage)
        }
    }
}
