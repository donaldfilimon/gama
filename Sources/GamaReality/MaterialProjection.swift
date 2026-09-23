#if canImport(RealityKit)
internal import GamaAuthoring
internal import RealityKit
#if canImport(AppKit)
internal import AppKit
typealias PlatformColor = NSColor
#elseif canImport(UIKit)
internal import UIKit
typealias PlatformColor = UIColor
#endif

extension GamaAuthoring.Material {
    /// The RealityKit physically based material for this authored material.
    @MainActor
    var physicallyBased: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let color = PlatformColor(
            red: CGFloat(baseColor.x),
            green: CGFloat(baseColor.y),
            blue: CGFloat(baseColor.z),
            alpha: CGFloat(baseColor.w)
        )
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: metallic)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
        return material
    }
}
#endif
