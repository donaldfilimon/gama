// VulkanBackendTests.swift — Tests for the Vulkan stub backend
// Part of GamaVulkanTests

import Testing
import GamaCore
@testable import GamaVulkan

@Suite("VulkanBackend Tests")
struct VulkanBackendTests {
    @Test("requestDefaultAdapter throws backendNotAvailable")
    func requestDefaultAdapterThrows() throws {
        #expect(throws: GPUError.self) {
            _ = try VulkanBackend.shared.requestDefaultAdapter()
        }
    }

    @Test("requestDefaultAdapter throws with Vulkan description")
    func requestDefaultAdapterErrorMessage() throws {
        do {
            _ = try VulkanBackend.shared.requestDefaultAdapter()
            #expect(Bool(false), "Expected GPUError.backendNotAvailable to be thrown")
        } catch let error as GPUError {
            guard case .backendNotAvailable(let name) = error else {
                #expect(Bool(false), "Expected backendNotAvailable, got \(error)")
                return
            }
            #expect(name == "Vulkan")
        }
    }
}
