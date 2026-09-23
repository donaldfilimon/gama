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
        run(
            [CreateEntity(
                name: name,
                components: [.transform(transform), .mesh(primitive), .material(Material())]
            )],
            label: "Add \(name)"
        )
        guard lastError == nil else { return }
        select(id)
    }

    /// Deletes the selected entity and its subtree. With no selection this is
    /// a deliberate no-op — there is nothing to delete — rather than a
    /// refusal, so `lastError` is left untouched.
    public func deleteSelection() {
        guard let id = session.selection.primary else { return }
        run([DeleteEntity(id)], label: "Delete")
    }

    /// Duplicates the selected entity and its subtree, placed directly after
    /// the original under the same parent. With no selection this is a
    /// no-op.
    public func duplicateSelection() {
        guard let id = session.selection.primary else { return }
        run([DuplicateEntity(id)], label: "Duplicate")
    }

    /// Moves the selected entity by `delta`, relative to its current
    /// position (or the identity transform, if it has none yet). With no
    /// selection this is a no-op.
    public func nudgeSelection(by delta: SIMD3<Float>) {
        guard let id = session.selection.primary else { return }
        var transform = currentTransform(of: id)
        transform.position += delta
        run([SetComponent(id, .transform(transform))], label: "Nudge")
    }

    /// Flips the visibility of the selected entity (default visible, if it
    /// has no `Visibility` component yet). With no selection this is a
    /// no-op.
    public func toggleVisibility() {
        guard let id = session.selection.primary else { return }
        var visibility = currentVisibility(of: id)
        visibility.visible.toggle()
        run([SetComponent(id, .visibility(visibility))], label: "Toggle Visibility")
    }

    // MARK: Sample scene

    /// Builds a small demonstration scene — a wide grey ground plane and a
    /// box, sphere, and cone spaced along X, each with a distinct material —
    /// entirely through `EditorSession` commands, never by constructing a
    /// `SceneDocument` directly.
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
        return session.document
    }

    // MARK: Funnel

    /// Applies `commands` as one undoable step — `EditorSession.execute` for
    /// a single command, `EditorSession.transaction` for several — then keeps
    /// `bridge` in sync. A refusal records `lastError` and leaves the
    /// session and bridge untouched. This is the only place any editing
    /// method reaches into `session`'s mutating command surface.
    private func run(_ commands: [any DocumentCommand], label: String) {
        settle { () throws(AuthoringError) in
            if commands.count == 1 {
                try session.execute(commands[0])
            } else {
                try session.transaction(label, commands)
            }
        }
    }

    /// Runs `operation`; on success clears `lastError` and projects the
    /// resulting change feed into `bridge`; on failure records the thrown
    /// error and leaves the session and bridge untouched.
    private func settle(_ operation: () throws(AuthoringError) -> Void) {
        attempt { () throws(AuthoringError) in
            try operation()
            bridge.apply(session.drainChanges(), from: session.document)
        }
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
