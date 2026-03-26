// InfoCommand.swift — Device info subcommand for GamaDemo
// Part of GamaDemo

import ArgumentParser
import GamaCore
#if canImport(Metal)
import GamaMetal
#endif

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List available GPU adapters and their capabilities"
    )

    func run() throws {
        print("Gama GPU Graphics API — Device Info")
        print("====================================")

        #if canImport(Metal)
        let backend = MetalBackend.shared
        let adapter = try backend.requestDefaultAdapter()
        let info = adapter.info

        print()
        print("Backend:        Metal")
        print("Device Name:    \(info.name)")
        print("Vendor:         \(info.vendor)")
        print("Type:           \(info.isDiscrete ? "Discrete" : "Integrated")")
        print("Max Buffer:     \(formatBytes(info.maxBufferSize))")
        print("Max Texture:    \(info.maxTextureSize)x\(info.maxTextureSize)")
        print()

        let allAdapters = backend.enumerateAdapters()
        if allAdapters.count > 1 {
            print("All available adapters (\(allAdapters.count)):")
            for (index, a) in allAdapters.enumerated() {
                let aInfo = a.info
                print("  [\(index)] \(aInfo.name) (\(aInfo.isDiscrete ? "discrete" : "integrated"))")
            }
        }
        #else
        print()
        print("Backend not available: Metal is not supported on this platform.")
        print("Gama currently supports Metal (macOS/iOS).")
        #endif
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return "\(bytes) bytes"
        }
    }
}
