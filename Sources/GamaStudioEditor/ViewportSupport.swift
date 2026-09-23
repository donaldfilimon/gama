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

    // MARK: Console notes (ADR 0018)

    /// Notes what a click or tap in the viewport selected, after the
    /// selection changed; nothing when the model refused it (the refusal is
    /// its own note).
    @MainActor
    public static func notePick(in model: StudioModel) {
        guard model.lastError == nil else { return }
        let name = model.session.selection.primary.flatMap { model.session.document.entity($0)?.name }
        model.log(note: name.map { "picked \($0)" } ?? "cleared selection", coalescing: true)
    }

    /// Notes what Frame fitted: the primary selection, or the whole scene.
    @MainActor
    public static func noteFrame(in model: StudioModel) {
        let name = model.session.selection.primary.flatMap { model.session.document.entity($0)?.name }
        model.log(note: name.map { "framed \($0)" } ?? "framed the scene", coalescing: true)
    }

    /// Notes that the viewport now looks through the camera `id`.
    @MainActor
    public static func noteLookThrough(_ id: EntityID, in model: StudioModel) {
        model.log(note: "looking through \(model.session.document.entity(id)?.name ?? "a camera")", coalescing: true)
    }

    /// Notes a camera move (orbit, pan, zoom, pinch). Coalesced, so a whole
    /// gesture, or a run of them, is one line, and repeats do not repaint.
    @MainActor
    public static func noteCameraMove(in model: StudioModel) {
        model.log(note: "moved the camera", coalescing: true)
    }
}

#endif
