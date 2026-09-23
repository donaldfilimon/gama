#if canImport(RealityKit)
internal import GamaAuthoring
internal import RealityKit

/// One cached unit-size mesh per ``Primitive``. Size comes from the entity's
/// transform scale, never from the mesh, so the mesh cache stays tiny (ADR 0002).
@MainActor
struct PrimitiveMeshes {
    private var cache: [Primitive: MeshResource] = [:]

    mutating func mesh(for primitive: Primitive) -> MeshResource {
        if let mesh = cache[primitive] { return mesh }
        let mesh: MeshResource = switch primitive {
        case .box: .generateBox(size: 1)
        case .sphere: .generateSphere(radius: 0.5)
        case .cylinder: .generateCylinder(height: 1, radius: 0.5)
        case .cone: .generateCone(height: 1, radius: 0.5)
        case .plane: .generatePlane(width: 1, depth: 1)
        }
        cache[primitive] = mesh
        return mesh
    }
}
#endif
