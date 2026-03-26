// DX12BackendTests.swift — Tests for the DirectX 12 stub backend
// Part of GamaDX12Tests

import Testing
import GamaCore
@testable import GamaDX12

@Suite("DX12Backend Tests")
struct DX12BackendTests {
    @Test("requestDefaultAdapter throws backendNotAvailable")
    func requestDefaultAdapterThrows() throws {
        #expect(throws: GPUError.self) {
            _ = try DX12Backend.shared.requestDefaultAdapter()
        }
    }

    @Test("requestDefaultAdapter throws with DirectX 12 description")
    func requestDefaultAdapterErrorMessage() throws {
        do {
            _ = try DX12Backend.shared.requestDefaultAdapter()
            #expect(Bool(false), "Expected GPUError.backendNotAvailable to be thrown")
        } catch let error as GPUError {
            guard case .backendNotAvailable(let name) = error else {
                #expect(Bool(false), "Expected backendNotAvailable, got \(error)")
                return
            }
            #expect(name == "DirectX 12")
        }
    }
}
