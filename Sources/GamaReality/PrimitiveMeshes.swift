#if canImport(RealityKit)
internal import GamaAuthoring
internal import RealityKit

/// One cached unit-size mesh per ``Primitive``. Size comes from the entity's
/// transform scale, never from the mesh, so the mesh cache stays tiny (ADR 0002).
@MainActor
struct PrimitiveMeshes {
    private var cache: [Primitive: MeshResource] = [:]
    private var shapeCache: [Primitive: ShapeResource] = [:]

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

    /// One cached pickable collision shape per ``Primitive``, matching the
    /// unit-size mesh (ADR 0002): a box for box and plane (the plane is a
    /// thin box so it stays pickable), a sphere for sphere, and the exact
    /// convex hull of the cached mesh for cylinder and cone.
    mutating func shape(for primitive: Primitive) -> ShapeResource {
        if let shape = shapeCache[primitive] { return shape }
        let shape: ShapeResource = switch primitive {
        case .box: .generateBox(size: [1, 1, 1])
        case .sphere: .generateSphere(radius: 0.5)
        case .plane: .generateBox(size: [1, 0.01, 1])
        case .cylinder: .generateConvex(from: mesh(for: .cylinder))
        case .cone: .generateConvex(from: mesh(for: .cone))
        }
        shapeCache[primitive] = shape
        return shape
    }
}
#endif
