//  StudioApp.swift — GamaStudioEditor
//
//  The editor's Gama view tree: a toolbar, a scene hierarchy, a native
//  viewport region the AppKit host fills with RealityKit, an inspector, and a
//  status line. Every edit goes through `StudioModel`; this file only reads
//  it and forwards button presses.
//
//  Isolation. `App` is a nonisolated protocol and `Button` stores a plain
//  `() -> Void`, while `StudioModel` is `@MainActor`. Gama runs a surface's
//  content closure inside `FrameHost.pump` and a button's action inside
//  `FrameHost.handle`/`perform`; the only callers of those here are
//  `GamaHostView` (`@MainActor`) and the `@MainActor` tests. So each crossing
//  asserts the main actor with `MainActor.assumeIsolated`, which traps rather
//  than races if that ever stops holding. The content closure copies what it
//  needs into the `Sendable` `StudioFrameState` inside that assertion and
//  builds the view tree from the copy, because a view tree (it holds
//  non-`Sendable` action closures) cannot leave `assumeIsolated`.

#if canImport(AppKit)

public import GamaCore
public import GamaAuthoring

/// The Gama Studio application root: one primary window laid out as a
/// toolbar, a hierarchy panel, the RealityKit viewport region, an inspector
/// panel, and a status line, all driven by ``model``.
public struct StudioApp: App {
    /// The native region the host attaches the RealityKit view to. The
    /// executable and the tests both use this constant, so the identity
    /// cannot drift between declaration and attachment.
    public static let viewportRegion = NativeRegionID("viewport")

    /// Every toolbar button's action identity, in toolbar order. Tests use
    /// the count to Tab past the toolbar; add a button's id here when you add
    /// the button.
    public static let toolbarActionIDs: [ActionID] = [
        ActionID("studio.addBox"), ActionID("studio.addSphere"), ActionID("studio.addCone"),
        ActionID("studio.addLight"), ActionID("studio.addCamera"),
        ActionID("studio.duplicate"), ActionID("studio.delete"),
        ActionID("studio.undo"), ActionID("studio.redo"), ActionID("studio.frame"),
    ]

    /// The editing model every panel reads and every button edits.
    public let model: StudioModel

    /// What the viewport buttons do. The camera is editor state that the
    /// model deliberately does not own (ADR 0003), so the host injects the
    /// viewport's actions here; ``ViewportActions/none`` does nothing.
    public let viewport: ViewportActions

    /// Creates the application over an existing model, so a host can keep
    /// its own reference (for example to attach a viewport to its bridge).
    ///
    /// - Parameter viewport: The viewport actions the buttons run, typically
    ///   forwarding to a `ViewportController`.
    public init(model: StudioModel, viewport: ViewportActions = .none) {
        self.model = model
        self.viewport = viewport
    }

    /// Creates the application over ``StudioModel/sampleScene()``; Gama's
    /// `App` protocol requires a no-argument initializer. Must run on the
    /// main thread, which it asserts, because `StudioModel` is main-actor
    /// isolated.
    public init() {
        self.init(model: MainActor.assumeIsolated {
            StudioModel(document: StudioModel.sampleScene())
        })
    }

    /// One primary window, `"Gama Studio"`, rebuilt from ``model`` on every
    /// frame.
    public var scenes: some Scene {
        // Capture the (Sendable, main-actor) model rather than `self`, which
        // is not Sendable and so cannot be sent into the isolated closure.
        let model = model
        let viewport = viewport
        return Window("Gama Studio", id: "main", role: .primary) {
            StudioRootView(model: model, viewport: viewport, state: MainActor.assumeIsolated {
                StudioFrameState(model)
            })
        }
    }
}

// MARK: - Viewport actions

/// The viewport operations the editor's buttons can request. The viewport
/// camera is editor state that ``StudioModel`` does not own (ADR 0003), so a
/// host that has a viewport (a `ViewportController`) injects these, and a
/// host without one uses ``none``.
public struct ViewportActions: Sendable {
    /// Aims the viewport at the primary selection (the "Frame" button).
    public var frameSelection: @MainActor @Sendable () -> Void
    /// Views the scene through the authored camera with this id.
    public var lookThrough: @MainActor @Sendable (EntityID) -> Void

    /// Creates the actions; each defaults to doing nothing.
    public init(
        frameSelection: @escaping @MainActor @Sendable () -> Void = {},
        lookThrough: @escaping @MainActor @Sendable (EntityID) -> Void = { _ in }
    ) {
        self.frameSelection = frameSelection
        self.lookThrough = lookThrough
    }

    /// Actions that do nothing, for a host without a viewport (and tests).
    public static let none = ViewportActions()
}

// MARK: - Frame state

/// Everything the panels display, copied out of the model on the main actor
/// once per frame. Plain `Sendable` data, so it can leave `assumeIsolated`.
struct StudioFrameState: Sendable {
    /// One hierarchy row, in depth-first authored order.
    struct Row: Sendable {
        var id: EntityID
        var name: String
        var depth: Int
        var isSelected: Bool
    }

    /// What the inspector shows about the primary selection.
    struct Inspected: Sendable {
        var id: EntityID
        var name: String
        var position: SIMD3<Float>
        var mesh: Primitive?
        var material: Material?
        var isVisible: Bool
        /// Present when the selection has a ``Light`` component; the
        /// inspector's light section renders from this.
        var light: Light?
        /// Present when the selection has a ``CameraSettings`` component; the
        /// inspector's camera section renders from this.
        var camera: CameraSettings?
    }

    var rows: [Row]
    var inspected: Inspected?
    var revision: UInt64
    var selectionName: String?
    var undoLabel: String?
    var lastError: AuthoringError?
    /// The console exchanges the panel shows, oldest first.
    var console: [StudioModel.ConsoleEntry]

    @MainActor
    init(_ model: StudioModel) {
        let session = model.session
        let document = session.document
        let primary = session.selection.primary

        var rows: [Row] = []
        func visit(_ id: EntityID, depth: Int) {
            guard let record = document.entity(id) else { return }
            var hint = ""
            if record.components[.camera] != nil {
                hint = " (C)"
            } else if record.components[.light] != nil {
                hint = " (L)"
            }
            rows.append(Row(id: id, name: record.name + hint, depth: depth, isSelected: id == primary))
            for child in record.children { visit(child, depth: depth + 1) }
        }
        for root in document.roots { visit(root, depth: 0) }
        self.rows = rows

        if let primary, let record = document.entity(primary) {
            var inspected = Inspected(
                id: primary, name: record.name, position: .zero, mesh: nil, material: nil,
                isVisible: true, light: nil, camera: nil
            )
            if case .transform(let transform)? = record.components[.transform] {
                inspected.position = transform.position
            }
            if case .mesh(let mesh)? = record.components[.mesh] { inspected.mesh = mesh }
            if case .material(let material)? = record.components[.material] {
                inspected.material = material
            }
            if case .visibility(let visibility)? = record.components[.visibility] {
                inspected.isVisible = visibility.visible
            }
            if case .light(let light)? = record.components[.light] { inspected.light = light }
            if case .camera(let camera)? = record.components[.camera] { inspected.camera = camera }
            self.inspected = inspected
            self.selectionName = record.name
        } else {
            self.inspected = nil
            self.selectionName = nil
        }
        self.revision = session.revision
        self.undoLabel = session.undoLabel
        self.lastError = model.lastError
        self.console = Array(model.consoleLog.suffix(ConsolePanel.visibleEntries))
    }
}

// MARK: - Views

/// Forwards `edit` to `model` on the main actor. Button actions run inside
/// `FrameHost.handle`/`perform`, which only main-actor hosts call.
private func onMain(
    _ model: StudioModel, _ edit: @escaping @MainActor (StudioModel) -> Void
) -> () -> Void {
    { MainActor.assumeIsolated { edit(model) } }
}

/// The whole window: toolbar, body, status line.
struct StudioRootView: View {
    let model: StudioModel
    let viewport: ViewportActions
    let state: StudioFrameState

    var body: some View {
        VStack {
            toolbar
            HStack {
                HierarchyPanel(model: model, rows: state.rows)
                NativeRegion(StudioApp.viewportRegion) {
                    Text("3D viewport — RealityKit on macOS")
                }
                .frame(maxWidth: .max, maxHeight: .max)
                InspectorPanel(model: model, viewport: viewport, inspected: state.inspected)
            }
            .frame(maxWidth: .max, maxHeight: .max)
            ConsolePanel(model: model, entries: state.console)
            Text(Self.statusLine(state))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            Button("Add Box", action: onMain(model) { $0.addPrimitive(.box) })
                .actionIdentity(ActionID("studio.addBox"))
            Button("Add Sphere", action: onMain(model) { $0.addPrimitive(.sphere) })
                .actionIdentity(ActionID("studio.addSphere"))
            Button("Add Cone", action: onMain(model) { $0.addPrimitive(.cone) })
                .actionIdentity(ActionID("studio.addCone"))
            Button("Add Light", action: onMain(model) { $0.addLight(.point(attenuationRadius: 10)) })
                .actionIdentity(ActionID("studio.addLight"))
            Button("Add Camera", action: onMain(model) { $0.addCamera() })
                .actionIdentity(ActionID("studio.addCamera"))
            Button("Duplicate", action: onMain(model) { $0.duplicateSelection() })
                .actionIdentity(ActionID("studio.duplicate"))
            Button("Delete", action: onMain(model) { $0.deleteSelection() })
                .actionIdentity(ActionID("studio.delete"))
            Button("Undo", action: onMain(model) { $0.undo() })
                .actionIdentity(ActionID("studio.undo"))
            Button("Redo", action: onMain(model) { $0.redo() })
                .actionIdentity(ActionID("studio.redo"))
            Button("Frame", action: { [viewport] in MainActor.assumeIsolated { viewport.frameSelection() } })
                .actionIdentity(ActionID("studio.frame"))
        }
    }

    /// `rev N · <selection> · undo: <label> · <refusal>`, the refusal only
    /// when one is recorded.
    static func statusLine(_ state: StudioFrameState) -> String {
        var line = "rev \(state.revision) · \(state.selectionName ?? "no selection")"
        line += " · undo: \(state.undoLabel ?? "—")"
        if let error = state.lastError { line += " · \(error)" }
        return line
    }
}

/// The command console (ADR 0006): the latest exchanges above an input
/// line. Enter submits the line through ``StudioModel/submitConsole()``,
/// which runs it through the same funnel as every other edit.
struct ConsolePanel: View {
    /// How many past exchanges the panel shows.
    static let visibleEntries = 3

    let model: StudioModel
    let entries: [StudioModel.ConsoleEntry]

    var body: some View {
        VStack {
            ForEach(entries) { entry in
                Text("> \(entry.input)  →  \(entry.output)", style: entry.isError ? TextStyle(attributes: [.dim]) : .plain)
            }
            HStack(spacing: 1) {
                Text(">")
                ConsoleField(
                    placeholder: "type a command, e.g. move selected 0 1 0 — 'help' lists them",
                    text: Binding(
                        get: { [model] in MainActor.assumeIsolated { model.consoleInput } },
                        set: { [model] value in MainActor.assumeIsolated { model.consoleInput = value } }
                    ),
                    onSubmit: onMain(model) { $0.submitConsole() }
                )
                .frame(maxWidth: .max)
            }
        }
        .frame(maxWidth: .max, alignment: .topLeading)
        .border(title: "Console")
    }
}

/// A `TextField` whose Enter submits instead of doing nothing.
///
/// `TextField` declines Enter, and the host then activates the node. A
/// plain action would also fire on a click into the field, since a pointer
/// press invokes the hit node's action, so the submit is attached to Enter
/// alone by wrapping the key handler the field registers.
struct ConsoleField: View {
    typealias Body = Never_
    var body: Never_ { Never_() }

    let placeholder: String
    let text: Binding<String>
    let onSubmit: () -> Void

    func render(in context: BuildContext) -> RenderNode {
        var inner = context
        let register = context.registerKeyHandler
        let submit = onSubmit
        inner.registerKeyHandler = { id, handler in
            register(id) { key in
                if key == .enter {
                    submit()
                    return true
                }
                return handler(key)
            }
        }
        return TextField(placeholder, text: text).render(in: inner)
    }
}

/// Stable per-entity identity for hierarchy rows, namespaced away from
/// gama's structural ids so focus follows the entity across edits.
private let hierarchyScope = NodeID(raw: 0x5354_5544_494F_0000)

/// The "Scene" panel: one selectable row per entity, indented by depth.
struct HierarchyPanel: View {
    let model: StudioModel
    let rows: [StudioFrameState.Row]

    var body: some View {
        VStack {
            IdentifiedForEach(rows, id: { hierarchyScope.child(Int(truncatingIfNeeded: $0.id.rawValue)) }) { row in
                Button(action: onMain(model) { [id = row.id] in $0.select(id) }) {
                    Text(
                        String(repeating: "  ", count: row.depth) + (row.isSelected ? "▸ " : "  ") + row.name,
                        style: row.isSelected ? TextStyle(attributes: [.inverse]) : .plain
                    )
                }
            }
        }
        .frame(maxWidth: .max, maxHeight: .max, alignment: .topLeading)
        .border(title: "Scene")
        .frame(width: 26)
    }
}

/// The "Inspector" panel: the primary selection's properties plus nudge and
/// visibility controls.
struct InspectorPanel: View {
    let model: StudioModel
    let viewport: ViewportActions
    let inspected: StudioFrameState.Inspected?

    /// One nudge step, in scene units.
    static let step: Float = 0.25

    var body: some View {
        VStack {
            if let inspected {
                Text("Name: \(inspected.name)").bold()
                Text("Position")
                Text("  x: \(formatted(inspected.position.x))")
                Text("  y: \(formatted(inspected.position.y))")
                Text("  z: \(formatted(inspected.position.z))")
                Text("Mesh: \(inspected.mesh?.rawValue ?? "—")")
                Text("Metallic: \(inspected.material.map { formatted($0.metallic) } ?? "—")")
                Text("Roughness: \(inspected.material.map { formatted($0.roughness) } ?? "—")")
                Text("Visible: \(inspected.isVisible ? "yes" : "no")")
                HStack {
                    nudge("-X", "studio.nudge.-x", SIMD3(-Self.step, 0, 0))
                    nudge("+X", "studio.nudge.+x", SIMD3(Self.step, 0, 0))
                    nudge("-Y", "studio.nudge.-y", SIMD3(0, -Self.step, 0))
                    nudge("+Y", "studio.nudge.+y", SIMD3(0, Self.step, 0))
                    nudge("-Z", "studio.nudge.-z", SIMD3(0, 0, -Self.step))
                    nudge("+Z", "studio.nudge.+z", SIMD3(0, 0, Self.step))
                }
                Button(inspected.isVisible ? "Hide" : "Show", action: onMain(model) { $0.toggleVisibility() })
                    .actionIdentity(ActionID("studio.toggleVisibility"))
                if let light = inspected.light {
                    lightSection(light)
                }
                if let camera = inspected.camera {
                    cameraSection(camera, id: inspected.id)
                }
            } else {
                Text("Nothing selected")
            }
        }
        .frame(maxWidth: .max, maxHeight: .max, alignment: .topLeading)
        .border(title: "Inspector")
        .frame(width: 30)
    }

    private func nudge(_ title: String, _ id: String, _ delta: SIMD3<Float>) -> some View {
        Button(title, action: onMain(model) { $0.nudgeSelection(by: delta) })
            .actionIdentity(ActionID(id))
    }

    /// Kind (cycling button), intensity with −/+, and color, for a selected
    /// light.
    private func lightSection(_ light: Light) -> some View {
        VStack {
            Text("Light").bold()
            Button("Kind: \(Self.kindLabel(light.kind))", action: onMain(model) { $0.cycleLightKind() })
                .actionIdentity(ActionID("studio.lightKind"))
            Text("Intensity: \(formatted(light.intensity)) \(Self.intensityUnit(light.kind))")
            HStack {
                Button("-", action: onMain(model) { $0.scaleLightIntensity(by: 0.8) })
                    .actionIdentity(ActionID("studio.lightIntensity.-"))
                Button("+", action: onMain(model) { $0.scaleLightIntensity(by: 1.25) })
                    .actionIdentity(ActionID("studio.lightIntensity.+"))
            }
            Text("Color: \(formatted(light.color.x)), \(formatted(light.color.y)), \(formatted(light.color.z))")
        }
    }

    /// FOV with −/+, near/far, and a "Look through" button, for a selected
    /// camera.
    private func cameraSection(_ camera: CameraSettings, id: EntityID) -> some View {
        VStack {
            Text("Camera").bold()
            Text("FOV: \(formatted(camera.fieldOfViewDegrees))°")
            HStack {
                Button("-", action: onMain(model) { $0.adjustFieldOfView(by: -5) })
                    .actionIdentity(ActionID("studio.cameraFov.-"))
                Button("+", action: onMain(model) { $0.adjustFieldOfView(by: 5) })
                    .actionIdentity(ActionID("studio.cameraFov.+"))
            }
            Text("Near: \(formatted(camera.near))")
            Text("Far: \(formatted(camera.far))")
            Button("Look through", action: { [viewport, id] in MainActor.assumeIsolated { viewport.lookThrough(id) } })
                .actionIdentity(ActionID("studio.lookThrough"))
        }
    }

    /// "Directional", "Point", or "Spot", for the kind-cycling button.
    private static func kindLabel(_ kind: LightKind) -> String {
        switch kind {
        case .directional: "Directional"
        case .point: "Point"
        case .spot: "Spot"
        }
    }

    /// Lux for a directional light (illuminance), lumens for point and spot
    /// (luminous flux) — the two families ``StudioModel/cycleLightKind()``
    /// documents as measured in different units.
    private static func intensityUnit(_ kind: LightKind) -> String {
        switch kind {
        case .directional: "lx"
        case .point, .spot: "lm"
        }
    }
}

/// `value` rounded to two decimals, without Foundation: `-2.00`, `0.50`.
/// Values too large for exact hundredths fall back to Swift's own spelling.
func formatted(_ value: Float) -> String {
    guard value.isFinite, abs(value) < 1e12 else { return "\(value)" }
    let hundredths = Int((Double(value) * 100).rounded())
    let magnitude = abs(hundredths)
    let fraction = magnitude % 100
    return (hundredths < 0 ? "-" : "") + "\(magnitude / 100)." + (fraction < 10 ? "0" : "") + "\(fraction)"
}

#endif
