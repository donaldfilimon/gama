#if canImport(RealityKit)
internal import Foundation
internal import GamaAuthoring
internal import RealityKit
#if canImport(AppKit)
internal import AppKit
#elseif canImport(UIKit)
internal import UIKit
#endif

extension GamaAuthoring.Material {
    /// The RealityKit physically based material for this authored material.
    ///
    /// `baseColor` is authored in linear sRGB (as USD material colors are).
    /// Platform colors built from bare components are gamma-encoded sRGB, so
    /// each channel is first encoded with the exact sRGB transfer function;
    /// passing linear values straight through would render every mid-tone
    /// darker, an authored 0.5 at about 0.21 (ADR 0002).
    @MainActor
    var physicallyBased: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let r = CGFloat(Self.encodeSRGB(baseColor.x))
        let g = CGFloat(Self.encodeSRGB(baseColor.y))
        let b = CGFloat(Self.encodeSRGB(baseColor.z))
        let a = CGFloat(baseColor.w)
        #if canImport(AppKit)
        let tint = NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        #else
        let tint = UIColor(red: r, green: g, blue: b, alpha: a)
        #endif
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: tint)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: metallic)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
        return material
    }

    /// The sRGB opto-electronic transfer function (IEC 61966-2-1).
    static func encodeSRGB(_ linear: Float) -> Float {
        linear <= 0.003_130_8 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }
}
#endif
