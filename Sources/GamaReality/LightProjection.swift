#if canImport(RealityKit)
internal import GamaAuthoring
internal import RealityKit
#if canImport(AppKit)
internal import AppKit
#elseif canImport(UIKit)
internal import UIKit
#endif

/// The platform color RealityKit's light and unlit-material initializers take
/// (`NSColor` on macOS, `UIColor` elsewhere).
#if canImport(AppKit)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    /// A platform color for a linear-sRGB authored color: each channel is
    /// sRGB-encoded first, as for material base colors (ADR 0002 item 8).
    static func encoding(linear color: SIMD3<Float>) -> PlatformColor {
        let r = CGFloat(GamaAuthoring.Material.encodeSRGB(color.x))
        let g = CGFloat(GamaAuthoring.Material.encodeSRGB(color.y))
        let b = CGFloat(GamaAuthoring.Material.encodeSRGB(color.z))
        #if canImport(AppKit)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        #else
        return UIColor(red: r, green: g, blue: b, alpha: 1)
        #endif
    }
}

extension Light {
    /// Sets exactly one RealityKit light component on `entity` for this
    /// light's kind, or none for `nil`. The other two light component types
    /// are always removed first, so a kind change and a removal both leave
    /// no stale light behind (ADR 0002 item 10).
    @MainActor
    static func project(_ light: Light?, onto entity: Entity) {
        entity.components.remove(DirectionalLightComponent.self)
        entity.components.remove(PointLightComponent.self)
        entity.components.remove(SpotLightComponent.self)
        guard let light else { return }
        let color = PlatformColor.encoding(linear: light.color)
        switch light.kind {
        case .directional:
            #if os(visionOS)
            entity.components.set(DirectionalLightComponent(color: color, intensity: light.intensity))
            #else
            entity.components.set(DirectionalLightComponent(
                color: color, intensity: light.intensity, isRealWorldProxy: false
            ))
            #endif
        case .point(let attenuationRadius):
            entity.components.set(PointLightComponent(
                color: color, intensity: light.intensity, attenuationRadius: attenuationRadius
            ))
        case .spot(let inner, let outer, let attenuationRadius):
            entity.components.set(SpotLightComponent(
                color: color,
                intensity: light.intensity,
                innerAngleInDegrees: inner,
                outerAngleInDegrees: outer,
                attenuationRadius: attenuationRadius
            ))
        }
    }

    /// The linear color of this light's viewport marker: the light's own
    /// color, lifted uniformly so its brightest channel is at least 0.5, so a
    /// dim or black light still has a visible marker.
    var markerColor: SIMD3<Float> {
        let floor: Float = 0.5
        let brightest = max(color.x, color.y, color.z)
        guard brightest < floor else { return color }
        return color + SIMD3(repeating: floor - brightest)
    }
}

/// What a camera or light entity shows in the viewport so it can be seen and
/// picked: an unmapped child entity named ``marker``.
enum Marker: Equatable {
    /// A small dark-grey box.
    case camera
    /// A small sphere in the light's (visibility-floored) linear color.
    case light(SIMD3<Float>)

    /// The name every marker entity carries.
    static let name = "GamaReality.marker"

    /// The linear dark grey of a camera marker.
    static let cameraColor = SIMD3<Float>(repeating: 0.05)

    /// The marker a record needs, if any. A camera wins over a light.
    init?(_ record: EntityRecord) {
        if case .camera? = record.components[.camera] {
            self = .camera
        } else if case .light(let light)? = record.components[.light] {
            self = .light(light.markerColor)
        } else {
            return nil
        }
    }
}
#endif
