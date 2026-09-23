//  StudioModel.swift — GamaStudioEditor
//
//  The editor's single source of behavior: every mutation an editor UI can
//  request is funneled through `EditorSession`, and the RealityKit
//  projection is kept current from the same funnel, so `bridge` can never
//  drift from `session.document` (AGENTS.md invariant 2).

#if canImport(RealityKit)
public import GamaAuthoring
public import GamaReality

/// Owns the editing session and its RealityKit projection for Gama Studio.
///
/// `RealityBridge` is the only reason this file needs anything beyond
/// `GamaAuthoring`, so it is gated on `canImport(RealityKit)` — the same
/// condition `RealityBridge` itself compiles under — rather than
/// `canImport(AppKit)` like `StudioApp.swift`. That lets `StudioModel`
/// compile everywhere RealityKit exists (macOS, iOS, tvOS, visionOS), not
/// only under AppKit.
@MainActor
public final class StudioModel {
    /// The command bus, undo history, and selection for the authored document.
    public private(set) var session: EditorSession

    /// The RealityKit projection of `session`'s document.
    public let bridge: RealityBridge

    /// The most recently refused command, transaction, undo, redo, or
    /// selection change. Cleared the next time any of those succeeds.
    public private(set) var lastError: AuthoringError?

    /// Called after every applied document change (an edit, an undo, or a
    /// redo), once `bridge` is already current. Not called for selection
    /// changes, which are editor state, nor for refusals.
    ///
    /// One listener slot: whoever installs a listener after another must
    /// keep and call the previous one, as ``ViewportController`` does.
    public var onDocumentChange: (@MainActor () -> Void)?

    /// Creates a model over `document`, projecting it into `bridge`
    /// immediately so the two never start out of sync.
    public init(document: SceneDocument = SceneDocument()) {
        session = EditorSession(document: document)
        bridge = RealityBridge()
        bridge.rebuild(from: session.document)
    }

    // MARK: History

    /// Reverses the most recent step. Sets `lastError` to `.nothingToUndo`
    /// and changes nothing if the undo stack is empty.
    public func undo() {
        settle { () throws(AuthoringError) in try session.undo() }
    }

    /// Reapplies the most recently undone step. Sets `lastError` to
    /// `.nothingToRedo` and changes nothing if the redo stack is empty.
    public func redo() {
        settle { () throws(AuthoringError) in try session.redo() }
    }

    // MARK: Selection

    /// Replaces the selection with `id`, or clears it when `id` is `nil`.
    /// An `id` absent from the document sets `lastError` and leaves the
    /// selection unchanged. Selection is editor state, not authored state, so
    /// this never touches `bridge`.
    public func select(_ id: EntityID?) {
        attempt { () throws(AuthoringError) in
            if let id {
                try session.select([id])
            } else {
                session.clearSelection()
            }
        }
    }

    // MARK: Editing

    /// Creates a new root entity for `primitive` with a default transform,
    /// mesh, and material, offset slightly from previous additions so they
    /// don't land exactly on top of each other, then selects it.
    public func addPrimitive(_ primitive: Primitive) {
        let id = session.document.nextEntityID
        let name = nextDisplayName(for: primitive)
        // Each successive addition steps along X, so new objects are visibly
        // distinct without needing real layout.
        let offset = Float(session.document.count) * 0.5
        let transform = Transform(position: SIMD3(offset, 0, 0))
        run(CreateEntity(
            name: name,
            components: [.transform(transform), .mesh(primitive), .material(Material())]
        ))
        guard lastError == nil else { return }
        select(id)
    }

    /// Deletes the selected entity and its subtree. With no selection this is
    /// a deliberate no-op — there is nothing to delete — rather than a
    /// refusal, so `lastError` is left untouched.
    public func deleteSelection() {
        guard let id = session.selection.primary else { return }
        run(DeleteEntity(id))
    }

    /// Duplicates the selected entity and its subtree, placed directly after
    /// the original under the same parent. With no selection this is a
    /// no-op.
    public func duplicateSelection() {
        guard let id = session.selection.primary else { return }
        run(DuplicateEntity(id))
    }

    /// Moves the selected entity by `delta`, relative to its current
    /// position (or the identity transform, if it has none yet). With no
    /// selection this is a no-op.
    public func nudgeSelection(by delta: SIMD3<Float>) {
        guard let id = session.selection.primary else { return }
        var transform = currentTransform(of: id)
        transform.position += delta
        run(SetComponent(id, .transform(transform)))
    }

    /// Flips the visibility of the selected entity (default visible, if it
    /// has no `Visibility` component yet). With no selection this is a
    /// no-op.
    public func toggleVisibility() {
        guard let id = session.selection.primary else { return }
        var visibility = currentVisibility(of: id)
        visibility.visible.toggle()
        run(SetComponent(id, .visibility(visibility)))
    }

    // MARK: Lights and cameras

    /// Where ``addLight(_:)`` places a new light: above the scene, aimed at
    /// the origin (which matters for directional and spot lights).
    static let newLightPosition = SIMD3<Float>(0, 4, 2)
    /// Where ``addCamera()`` places a new camera: in front of and above the
    /// scene, off to one side of the default view, aimed at the origin.
    static let newCameraPosition = SIMD3<Float>(4, 3, 6)

    /// Creates a root light entity "Light N" of `kind`, above the scene and
    /// aimed at the origin, visible, then selects it. A directional light
    /// starts at ``Light/defaultDirectional``'s intensity; a point or spot
    /// light at ``Light/defaultPoint``'s.
    public func addLight(_ kind: LightKind) {
        let id = session.document.nextEntityID
        let intensity = kind == .directional ? Light.defaultDirectional.intensity : Light.defaultPoint.intensity
        let position = Self.newLightPosition
        let transform = Transform(position: position, rotation: .lookAt(.zero, from: position))
        run(CreateEntity(
            name: "Light \(count(of: .light) + 1)",
            components: [
                .transform(transform),
                .light(Light(kind: kind, intensity: intensity)),
                .visibility(Visibility()),
            ]
        ))
        guard lastError == nil else { return }
        select(id)
    }

    /// Creates a root camera entity "Camera N" with default
    /// ``CameraSettings``, placed in front of the scene and aimed at the
    /// origin, then selects it.
    public func addCamera() {
        let id = session.document.nextEntityID
        let position = Self.newCameraPosition
        run(CreateEntity(
            name: "Camera \(count(of: .camera) + 1)",
            components: [
                .transform(Transform(position: position, rotation: .lookAt(.zero, from: position))),
                .camera(.default),
            ]
        ))
        guard lastError == nil else { return }
        select(id)
    }

    /// The spot cone ``cycleLightKind()`` gives a light that becomes a spot.
    static let cycledSpotAngles: (inner: Float, outer: Float) = (30, 45)
    /// The attenuation radius ``cycleLightKind()`` gives a directional light
    /// that becomes a point light.
    static let cycledAttenuationRadius: Float = 10

    /// Changes the selected light's kind: directional, then point, then
    /// spot, then directional again, as one undoable step. Color is kept;
    /// a point light's attenuation radius carries into the spot.
    ///
    /// Intensity is measured in different units by the two families
    /// (directional in lux, point and spot in lumens), so a step that
    /// crosses between them resets it to the new kind's default
    /// (``Light/defaultDirectional`` or ``Light/defaultPoint``); carrying
    /// the number across would make the light about 9× too dim or too
    /// bright. Point to spot keeps the intensity, since both are lumens.
    /// With no selection this is a no-op; a selection without a light sets
    /// `lastError` to `.componentAbsent` and changes nothing.
    public func cycleLightKind() {
        editLight { light in
            switch light.kind {
            case .directional:
                light.kind = .point(attenuationRadius: Self.cycledAttenuationRadius)
                light.intensity = Light.defaultPoint.intensity
            case .point(let radius):
                light.kind = .spot(
                    innerAngleDegrees: Self.cycledSpotAngles.inner,
                    outerAngleDegrees: Self.cycledSpotAngles.outer,
                    attenuationRadius: radius
                )
            case .spot:
                light.kind = .directional
                light.intensity = Light.defaultDirectional.intensity
            }
        }
    }

    /// Multiplies the selected light's intensity by `factor`. A factor that
    /// makes the intensity negative or non-finite is refused by the light's
    /// validation. With no selection this is a no-op; a selection without a
    /// light sets `lastError` to `.componentAbsent`.
    public func scaleLightIntensity(by factor: Float) {
        editLight { $0.intensity *= factor }
    }

    /// Adds `delta` degrees to the selected camera's field of view. A result
    /// outside `1...179` is refused by the camera's validation. With no
    /// selection this is a no-op; a selection without a camera sets
    /// `lastError` to `.componentAbsent`.
    public func adjustFieldOfView(by delta: Float) {
        guard let id = session.selection.primary else { return }
        guard case .camera(var settings)? = session.document.component(.camera, of: id) else {
            attempt { () throws(AuthoringError) in throw .componentAbsent(id, .camera) }
            return
        }
        settings.fieldOfViewDegrees += delta
        run(SetComponent(id, .camera(settings)))
    }

    /// Applies `change` to the selected entity's light through the funnel,
    /// refusing (never adding a light) when the entity has none.
    private func editLight(_ change: (inout Light) -> Void) {
        guard let id = session.selection.primary else { return }
        guard case .light(var light)? = session.document.component(.light, of: id) else {
            attempt { () throws(AuthoringError) in throw .componentAbsent(id, .light) }
            return
        }
        change(&light)
        run(SetComponent(id, .light(light)))
    }

    /// How many entities hold a component of `kind`, for generated names.
    private func count(of kind: ComponentKind) -> Int {
        let document = session.document
        return document.entities.keys.filter { document.component(kind, of: $0) != nil }.count
    }

    // MARK: Sample scene

    /// Builds a small demonstration scene — a wide grey ground plane; a
    /// box, sphere, and cone spaced along X, each with a distinct material;
    /// then a directional "Key Light" and a "Camera", both aimed at the
    /// origin — entirely through `EditorSession` commands, never by
    /// constructing a `SceneDocument` directly. The light and camera come
    /// last so the first four hierarchy rows are unchanged.
    public static func sampleScene() -> SceneDocument {
        var session = EditorSession()
        // Every command below is fixed and known-valid (finite transforms,
        // in-range material channels), so a throw here would be a bug in
        // this function, not a runtime condition to recover from.
        try! session.execute(CreateEntity(
            name: "Ground",
            components: [
                .transform(Transform(scale: SIMD3(10, 1, 10))),
                .mesh(.plane),
                .material(Material(baseColor: SIMD4(0.5, 0.5, 0.5, 1))),
            ]
        ))
        try! session.execute(CreateEntity(
            name: "Box",
            components: [
                .transform(Transform(position: SIMD3(-2, 0.5, 0))),
                .mesh(.box),
                .material(Material(baseColor: SIMD4(0.8, 0.2, 0.2, 1))),
            ]
        ))
        try! session.execute(CreateEntity(
            name: "Sphere",
            components: [
                .transform(Transform(position: SIMD3(0, 0.5, 0))),
                .mesh(.sphere),
                .material(Material(baseColor: SIMD4(0.2, 0.8, 0.2, 1))),
            ]
        ))
        try! session.execute(CreateEntity(
            name: "Cone",
            components: [
                .transform(Transform(position: SIMD3(2, 0.5, 0))),
                .mesh(.cone),
                .material(Material(baseColor: SIMD4(0.2, 0.2, 0.8, 1))),
            ]
        ))
        // The key light replaces the editor's old fixed light: the same
        // direction (from (3, 6, 4) toward the origin) and intensity.
        let keyLightPosition = SIMD3<Float>(3, 6, 4)
        try! session.execute(CreateEntity(
            name: "Key Light",
            components: [
                .transform(Transform(position: keyLightPosition, rotation: .lookAt(.zero, from: keyLightPosition))),
                .light(Light(kind: .directional, intensity: 3000)),
            ]
        ))
        // Where the viewport's orbit camera starts, looking at the origin.
        let cameraPosition = SIMD3<Float>(0, 3, 7)
        try! session.execute(CreateEntity(
            name: "Camera",
            components: [
                .transform(Transform(position: cameraPosition, rotation: .lookAt(.zero, from: cameraPosition))),
                .camera(.default),
            ]
        ))
        return session.document
    }

    // MARK: Funnel

    /// Applies `command` as one undoable step through `EditorSession.execute`,
    /// then keeps `bridge` in sync. A refusal records `lastError` and leaves
    /// the session and bridge untouched. This is the only place any editing
    /// method reaches into `session`'s mutating command surface.
    ///
    /// Every caller passes exactly one command, so there is no multi-command
    /// `EditorSession.transaction` path here; a future action that needs to
    /// apply several commands as one undo step can add one back, with a test
    /// that exercises it.
    private func run(_ command: any DocumentCommand) {
        settle { () throws(AuthoringError) in try session.execute(command) }
    }

    /// Runs `operation`; on success clears `lastError` and projects the
    /// resulting change feed into `bridge`; on failure records the thrown
    /// error and leaves the session and bridge untouched.
    ///
    /// On success ``onDocumentChange`` runs last, after `lastError` is
    /// cleared, so a listener sees the settled state.
    private func settle(_ operation: () throws(AuthoringError) -> Void) {
        var applied = false
        attempt { () throws(AuthoringError) in
            try operation()
            bridge.apply(session.drainChanges(), from: session.document)
            applied = true
        }
        if applied { onDocumentChange?() }
    }

    /// Runs `operation`; on success clears `lastError`; on failure records
    /// the thrown error and leaves the session untouched.
    private func attempt(_ operation: () throws(AuthoringError) -> Void) {
        do {
            try operation()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    private func currentTransform(of id: EntityID) -> Transform {
        if case .transform(let transform)? = session.document.component(.transform, of: id) {
            return transform
        }
        return .identity
    }

    private func currentVisibility(of id: EntityID) -> Visibility {
        if case .visibility(let visibility)? = session.document.component(.visibility, of: id) {
            return visibility
        }
        return Visibility()
    }

    private func nextDisplayName(for primitive: Primitive) -> String {
        let document = session.document
        let count = document.entities.keys.filter {
            if case .mesh(primitive)? = document.component(.mesh, of: $0) { return true }
            return false
        }.count
        return "\(Self.displayName(for: primitive)) \(count + 1)"
    }

    /// A title-case name for a primitive kind, used in generated entity names
    /// and undo labels. `Primitive.rawValue` stays lowercase (spec data), and
    /// `Foundation`'s `capitalized` is out of reach for a target that stays
    /// import-light, so this spells out the mapping by hand.
    private static func displayName(for primitive: Primitive) -> String {
        switch primitive {
        case .box: "Box"
        case .sphere: "Sphere"
        case .cylinder: "Cylinder"
        case .cone: "Cone"
        case .plane: "Plane"
        }
    }
}
#endif
