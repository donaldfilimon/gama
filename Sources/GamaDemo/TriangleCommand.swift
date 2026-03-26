// TriangleCommand.swift — Triangle setup subcommand for GamaDemo
// Part of GamaDemo

import ArgumentParser
import GamaCore
#if canImport(Metal)
import GamaMetal
#endif

struct Triangle: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set up a triangle vertex buffer (proves the API works end-to-end)"
    )

    func run() throws {
        print("Gama GPU Graphics API — Triangle Setup")
        print("=======================================")

        #if canImport(Metal)
        // 1. Get adapter and create device
        let backend = MetalBackend.shared
        let adapter = try backend.requestDefaultAdapter()
        print("Adapter: \(adapter.info.name)")

        let device = try adapter.requestDevice()
        print("Device created successfully.")

        // 2. Create a command queue
        let queue = try device.createQueue()
        print("Command queue created.")

        // 3. Define triangle vertex data: 3 vertices, each with (x, y) as Float
        //    Positions: top (0.0, 0.5), bottom-left (-0.5, -0.5), bottom-right (0.5, -0.5)
        let vertices: [Float] = [
             0.0,  0.5,   // top center
            -0.5, -0.5,   // bottom left
             0.5, -0.5,   // bottom right
        ]
        let vertexDataSize = vertices.count * MemoryLayout<Float>.stride

        // 4. Create vertex buffer
        let buffer = try device.createBuffer(size: vertexDataSize, usage: .vertex)
        print("Vertex buffer created: \(buffer.size) bytes")

        // 5. Copy vertex data into the buffer
        vertices.withUnsafeBufferPointer { ptr in
            buffer.contents().copyMemory(
                from: ptr.baseAddress!,
                byteCount: vertexDataSize
            )
        }
        buffer.didModifyRange(0..<vertexDataSize)
        print("Vertex data uploaded: 3 vertices, 2 floats each")

        _ = queue // Suppress unused variable warning

        print()
        print("Triangle setup complete!")
        print("Buffer size: \(buffer.size) bytes (\(vertices.count / 2) vertices)")
        #else
        print()
        print("Backend not available: Metal is not supported on this platform.")
        print("Cannot set up triangle without a GPU backend.")
        #endif
    }
}
