import GamaAuthoring

/// The names and constants the writer and reader share, so the two cannot
/// drift (ADR 0005).
enum USDSchema {
    static let formatVersion = 1
    static let formatVersionKey = "gama:formatVersion"
    static let nextEntityIDKey = "gama:nextEntityID"

    static let idAttribute = "gama:id"
    static let nameAttribute = "gama:name"
    static let componentAttribute = "gama:component"
    static let visibleAttribute = "gama:visible"
    static let lockedAttribute = "gama:locked"
    static let intensityAttribute = "gama:intensity"
    static let attenuationRadiusAttribute = "gama:attenuationRadius"
    static let innerAngleAttribute = "gama:innerAngle"
    static let outerAngleAttribute = "gama:outerAngle"
    static let fieldOfViewAttribute = "gama:fieldOfView"

    /// The material library scope, placed last under the first root prim.
    static let looksScope = "Looks"
    static let meshChild = "GamaMesh"
    static let lightChild = "GamaLight"
    static let cameraChild = "GamaCamera"
    static let shaderName = "Surface"
    /// Prim names the writer creates itself; an entity with one of these names
    /// gets a suffix so the two can never collide.
    static let reservedNames: Set<String> = [looksScope, meshChild, lightChild, cameraChild]

    /// Camera film back height in millimetres. USD derives the field of view
    /// from aperture and focal length; `gama:fieldOfView` stays exact.
    static let verticalAperture: Float = 24

    /// The UsdLux `inputs:intensity` written for external viewers: Gama's lux
    /// (directional) or lumens (point, spot) divided by 1000. UsdLux has its
    /// own photometric model, so this is a preview approximation only;
    /// `gama:intensity` is what Gama reads back.
    static let previewIntensityDivisor: Float = 1000

    static func typeName(for primitive: Primitive) -> String {
        switch primitive {
        case .box: "Cube"
        case .sphere: "Sphere"
        case .cylinder: "Cylinder"
        case .cone: "Cone"
        case .plane: "Plane"
        }
    }

    static func primitive(forTypeName name: String) -> Primitive? {
        switch name {
        case "Cube": .box
        case "Sphere": .sphere
        case "Cylinder": .cylinder
        case "Cone": .cone
        case "Plane": .plane
        default: nil
        }
    }

    static func typeName(for light: LightKind) -> String {
        switch light {
        case .directional: "DistantLight"
        case .point, .spot: "SphereLight"
        }
    }

    static let lightTypeNames: Set<String> = ["DistantLight", "SphereLight"]
    static let cameraTypeName = "Camera"
}
