// Material.swift — Shader parameter container for surface appearance
// Part of GamaScene

import simd
import GamaCore

/// Describes the visual appearance of a surface.
///
/// Holds PBR-style parameters (color, roughness, metallic) and an optional
/// texture reference. The texture is stored as an existential conforming to
/// `GPUTexture` from GamaCore.
public struct Material: Sendable {
    // MARK: - Properties

    /// Base color (linear RGBA).
    public var color: SIMD4<Float>

    /// Roughness factor (0 = mirror, 1 = fully diffuse).
    public var roughness: Float

    /// Metallic factor (0 = dielectric, 1 = metal).
    public var metallic: Float

    /// Optional albedo texture.
    public var texture: (any GPUTexture)?

    // MARK: - Initializers

    /// Creates a material with the given surface parameters.
    ///
    /// - Parameters:
    ///   - color: Base color in linear RGBA. Defaults to opaque white.
    ///   - roughness: Surface roughness. Defaults to `0.5`.
    ///   - metallic: Metalness factor. Defaults to `0.0`.
    ///   - texture: An optional GPU texture for the surface.
    public init(
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        roughness: Float = 0.5,
        metallic: Float = 0.0,
        texture: (any GPUTexture)? = nil
    ) {
        self.color = color
        self.roughness = roughness
        self.metallic = metallic
        self.texture = texture
    }

    /// A default white material with mid-roughness.
    public static let `default` = Material()
}
