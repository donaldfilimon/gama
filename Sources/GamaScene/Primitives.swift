// Primitives.swift — Static factories for common mesh shapes
// Part of GamaScene

import simd

/// Convenience extensions for generating primitive geometry.
extension Mesh {
    // MARK: - Cube

    /// Creates an axis-aligned cube centered at the origin.
    ///
    /// - Parameter size: The length of each edge.
    /// - Returns: A mesh with 24 vertices (4 per face) and 36 indices.
    public static func cube(size: Float = 1) -> Mesh {
        let h = size * 0.5
        // 6 faces × 4 vertices each, with normals and UVs
        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [UInt32]()

        let faceData: [(normal: SIMD3<Float>, tangent: SIMD3<Float>, bitangent: SIMD3<Float>)] = [
            // +Z
            (SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)),
            // -Z
            (SIMD3<Float>(0, 0, -1), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1, 0)),
            // +X
            (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, -1), SIMD3<Float>(0, 1, 0)),
            // -X
            (SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 1, 0)),
            // +Y
            (SIMD3<Float>(0, 1, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, -1)),
            // -Y
            (SIMD3<Float>(0, -1, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)),
        ]

        for (i, face) in faceData.enumerated() {
            let n = face.normal
            let t = face.tangent
            let b = face.bitangent

            let v0 = n * h - t * h - b * h
            let v1 = n * h + t * h - b * h
            let v2 = n * h + t * h + b * h
            let v3 = n * h - t * h + b * h

            positions.append(contentsOf: [v0, v1, v2, v3])
            normals.append(contentsOf: [n, n, n, n])
            uvs.append(contentsOf: [
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
                SIMD2<Float>(1, 1), SIMD2<Float>(0, 1),
            ])

            let base = UInt32(i * 4)
            indices.append(contentsOf: [
                base, base + 1, base + 2,
                base, base + 2, base + 3,
            ])
        }

        return Mesh(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    // MARK: - Sphere

    /// Creates a UV sphere centered at the origin.
    ///
    /// - Parameters:
    ///   - radius: The sphere radius.
    ///   - segments: The number of longitudinal and latitudinal divisions.
    /// - Returns: An indexed mesh approximating a sphere.
    public static func sphere(radius: Float = 0.5, segments: Int = 16) -> Mesh {
        let stacks = max(segments, 3)
        let slices = max(segments, 3)

        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [UInt32]()

        for stack in 0...stacks {
            let phi = Float.pi * Float(stack) / Float(stacks)
            let sinPhi = sin(phi)
            let cosPhi = cos(phi)

            for slice in 0...slices {
                let theta = 2.0 * Float.pi * Float(slice) / Float(slices)
                let sinTheta = sin(theta)
                let cosTheta = cos(theta)

                let x = cosTheta * sinPhi
                let y = cosPhi
                let z = sinTheta * sinPhi

                let normal = SIMD3<Float>(x, y, z)
                positions.append(normal * radius)
                normals.append(normal)
                uvs.append(SIMD2<Float>(
                    Float(slice) / Float(slices),
                    Float(stack) / Float(stacks)
                ))
            }
        }

        for stack in 0..<stacks {
            for slice in 0..<slices {
                let first = UInt32(stack * (slices + 1) + slice)
                let second = first + UInt32(slices + 1)

                indices.append(contentsOf: [first, second, first + 1])
                indices.append(contentsOf: [second, second + 1, first + 1])
            }
        }

        return Mesh(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    // MARK: - Plane

    /// Creates a horizontal plane centered at the origin in the XZ plane.
    ///
    /// - Parameters:
    ///   - width: Extent along the X axis.
    ///   - height: Extent along the Z axis.
    /// - Returns: A mesh with 4 vertices and 6 indices.
    public static func plane(width: Float = 1, height: Float = 1) -> Mesh {
        let hw = width * 0.5
        let hh = height * 0.5

        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(-hw, 0, -hh),
            SIMD3<Float>( hw, 0, -hh),
            SIMD3<Float>( hw, 0,  hh),
            SIMD3<Float>(-hw, 0,  hh),
        ]

        let normal = SIMD3<Float>(0, 1, 0)
        let normals = [SIMD3<Float>](repeating: normal, count: 4)

        let uvCoords: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1), SIMD2<Float>(0, 1),
        ]

        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]

        return Mesh(positions: positions, normals: normals, uvs: uvCoords, indices: indices)
    }

    // MARK: - Cylinder

    /// Creates a cylinder centered at the origin along the Y axis.
    ///
    /// - Parameters:
    ///   - radius: The cylinder radius.
    ///   - height: The total height.
    ///   - segments: The number of radial divisions.
    /// - Returns: An indexed mesh approximating a cylinder with caps.
    public static func cylinder(radius: Float = 0.5, height: Float = 1, segments: Int = 16) -> Mesh {
        let segs = max(segments, 3)
        let halfH = height * 0.5

        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [UInt32]()

        // Side vertices: two rings (top and bottom)
        for i in 0...segs {
            let angle = 2.0 * Float.pi * Float(i) / Float(segs)
            let x = cos(angle)
            let z = sin(angle)
            let u = Float(i) / Float(segs)

            // Bottom ring
            positions.append(SIMD3<Float>(x * radius, -halfH, z * radius))
            normals.append(SIMD3<Float>(x, 0, z))
            uvs.append(SIMD2<Float>(u, 0))

            // Top ring
            positions.append(SIMD3<Float>(x * radius, halfH, z * radius))
            normals.append(SIMD3<Float>(x, 0, z))
            uvs.append(SIMD2<Float>(u, 1))
        }

        // Side indices
        for i in 0..<segs {
            let bl = UInt32(i * 2)
            let br = UInt32(i * 2 + 2)
            let tl = bl + 1
            let tr = br + 1
            indices.append(contentsOf: [bl, br, tl])
            indices.append(contentsOf: [br, tr, tl])
        }

        // Top cap (normal pointing up, CCW winding)
        appendCap(
            y: halfH, normal: SIMD3<Float>(0, 1, 0), flipWinding: false,
            radius: radius, segments: segs,
            positions: &positions, normals: &normals, uvs: &uvs, indices: &indices
        )

        // Bottom cap (normal pointing down, CW winding)
        appendCap(
            y: -halfH, normal: SIMD3<Float>(0, -1, 0), flipWinding: true,
            radius: radius, segments: segs,
            positions: &positions, normals: &normals, uvs: &uvs, indices: &indices
        )

        return Mesh(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }

    // MARK: - Cap Helper

    /// Appends a circular cap at the given Y height.
    ///
    /// - Parameters:
    ///   - y: The Y coordinate of the cap plane.
    ///   - normal: The face normal for all cap vertices.
    ///   - flipWinding: When `true`, reverses triangle winding order.
    ///   - radius: The cap radius.
    ///   - segments: The number of radial divisions.
    ///   - positions: Vertex position buffer (mutated).
    ///   - normals: Vertex normal buffer (mutated).
    ///   - uvs: Texture coordinate buffer (mutated).
    ///   - indices: Index buffer (mutated).
    private static func appendCap(
        y: Float,
        normal: SIMD3<Float>,
        flipWinding: Bool,
        radius: Float,
        segments: Int,
        positions: inout [SIMD3<Float>],
        normals: inout [SIMD3<Float>],
        uvs: inout [SIMD2<Float>],
        indices: inout [UInt32]
    ) {
        let center = UInt32(positions.count)
        positions.append(SIMD3<Float>(0, y, 0))
        normals.append(normal)
        uvs.append(SIMD2<Float>(0.5, 0.5))

        for i in 0..<segments {
            let angle0 = 2.0 * Float.pi * Float(i) / Float(segments)
            let angle1 = 2.0 * Float.pi * Float(i + 1) / Float(segments)
            let idx = UInt32(positions.count)

            positions.append(SIMD3<Float>(cos(angle0) * radius, y, sin(angle0) * radius))
            normals.append(normal)
            uvs.append(SIMD2<Float>(cos(angle0) * 0.5 + 0.5, sin(angle0) * 0.5 + 0.5))

            positions.append(SIMD3<Float>(cos(angle1) * radius, y, sin(angle1) * radius))
            normals.append(normal)
            uvs.append(SIMD2<Float>(cos(angle1) * 0.5 + 0.5, sin(angle1) * 0.5 + 0.5))

            if flipWinding {
                indices.append(contentsOf: [center, idx + 1, idx])
            } else {
                indices.append(contentsOf: [center, idx, idx + 1])
            }
        }
    }
}
