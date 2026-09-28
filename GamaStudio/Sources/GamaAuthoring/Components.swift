/// A built-in mesh shape. Asset-backed meshes arrive with the USD phase.
public enum Primitive: String, Hashable, Codable, Sendable, CaseIterable {
    case box
    case sphere
    case cylinder
    case cone
    case plane
}

/// A physically based surface description.
public struct Material: Hashable, Codable, Sendable {
    /// Linear RGBA, each channel in `0...1`.
    public var baseColor: SIMD4<Float>
    /// In `0...1`.
    public var metallic: Float
    /// In `0...1`.
    public var roughness: Float

    public init(
        baseColor: SIMD4<Float> = SIMD4(0.8, 0.8, 0.8, 1),
        metallic: Float = 0,
        roughness: Float = 0.5
    ) {
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
    }

    /// Rejects any channel, metallic, or roughness value outside `0...1`
    /// (which also rejects NaN).
    public func validate() throws(AuthoringError) {
        for channel in 0..<4 {
            guard (0...1).contains(baseColor[channel]) else {
                throw .invalidMaterial("base color channels must be in 0...1")
            }
        }
        guard (0...1).contains(metallic) else {
            throw .invalidMaterial("metallic must be in 0...1")
        }
        guard (0...1).contains(roughness) else {
            throw .invalidMaterial("roughness must be in 0...1")
        }
    }
}

/// Editor visibility and lock state.
public struct Visibility: Hashable, Codable, Sendable {
    public var visible: Bool
    public var locked: Bool

    public init(visible: Bool = true, locked: Bool = false) {
        self.visible = visible
        self.locked = locked
    }
}

/// The kind of a ``Component``. An entity holds at most one component per kind.
public enum ComponentKind: String, Hashable, Codable, Sendable, CaseIterable, Comparable {
    case transform
    case mesh
    case material
    case visibility
    case light
    case camera

    /// Declaration order, so iteration over kinds is deterministic.
    public static func < (lhs: ComponentKind, rhs: ComponentKind) -> Bool {
        lhs.order < rhs.order
    }

    /// Title-case name for command labels, such as `Transform`.
    public var displayName: String {
        switch self {
        case .transform: "Transform"
        case .mesh: "Mesh"
        case .material: "Material"
        case .visibility: "Visibility"
        case .light: "Light"
        case .camera: "Camera"
        }
    }

    private var order: Int {
        switch self {
        case .transform: 0
        case .mesh: 1
        case .material: 2
        case .visibility: 3
        case .light: 4
        case .camera: 5
        }
    }
}

/// One piece of authored state attached to an entity.
public enum Component: Hashable, Codable, Sendable {
    case transform(Transform)
    case mesh(Primitive)
    case material(Material)
    case visibility(Visibility)
    case light(Light)
    case camera(CameraSettings)

    public var kind: ComponentKind {
        switch self {
        case .transform: .transform
        case .mesh: .mesh
        case .material: .material
        case .visibility: .visibility
        case .light: .light
        case .camera: .camera
        }
    }

    /// Validates the payload of kinds that have invariants.
    public func validate() throws(AuthoringError) {
        switch self {
        case .transform(let transform): try transform.validate()
        case .material(let material): try material.validate()
        case .light(let light): try light.validate()
        case .camera(let camera): try camera.validate()
        case .mesh, .visibility: break
        }
    }
}
