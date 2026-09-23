//  ViewportSupport.swift — GamaStudioEditor
//
//  Viewport rules shared by the AppKit viewport (ViewportController) and the
//  touch viewport on iOS and visionOS (TouchViewport), so both pick and light
//  the same way (ADR 0008).

#if canImport(RealityKit)

public import GamaAuthoring
public import GamaReality
public import RealityKit

public enum ViewportSupport {
    /// The authored identity a hit on `entity` selects: the nearest of
    /// `entity` and its ancestors that `bridge` projected, or `nil` for no
    /// hit and for entities outside the projection. Walking up means a hit on
    /// an unprojected sub-part still selects the entity that owns it.
    @MainActor
    public static func pickedEntityID(for entity: Entity?, in bridge: RealityBridge) -> EntityID? {
        var current = entity
        while let candidate = current {
            if let id = bridge.id(for: candidate) { return id }
            current = candidate.parent
        }
        return nil
    }

    /// Whether `document` has a light that is shining: an entity with a
    /// light component whose own and every ancestor's ``Visibility`` is
    /// visible. A missing `Visibility` component counts as visible. The
    /// viewports light the scene with a fallback editor light otherwise.
    public static func documentHasEnabledLight(_ document: SceneDocument) -> Bool {
        document.entities.values.contains { record in
            guard record.components[.light] != nil else { return false }
            var cursor: EntityID? = record.id
            while let id = cursor, let current = document.entity(id) {
                if case .visibility(let visibility)? = current.components[.visibility], !visibility.visible {
                    return false
                }
                cursor = current.parent
            }
            return true
        }
    }
}

#endif
