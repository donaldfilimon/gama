//  StudioModel.swift — GamaStudioEditor
//
//  The editor's single source of behavior: every mutation an editor UI can
//  request is funneled through `EditorSession`, and the RealityKit
//  projection is kept current from the same funnel, so `bridge` can never
//  drift from `session.document` (AGENTS.md invariant 2).

#if canImport(RealityKit)
public import GamaAuthoring
import GamaConsole
public import GamaGraph
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

    /// A one-time message for the status line, such as unsaved changes
    /// brought back at launch (ADR 0015). Editor state, not authored state:
    /// the next document change (an edit, undo, redo, or open) clears it.
    public var notice: String?

    /// Called after every applied document change (an edit, an undo, or a
    /// redo), once `bridge` is already current. Not called for selection
    /// changes, which are editor state, nor for refusals.
    ///
    /// One listener slot: whoever installs a listener after another must
    /// keep and call the previous one, as ``ViewportController`` does.
    public var onDocumentChange: (@MainActor () -> Void)?

    /// Called after the selection changes, whatever changed it: a click, a
    /// panel, an edit that selects what it created, an undo or delete that
    /// prunes it, or opening a document. Runs after ``onDocumentChange``
    /// when one action changes both. Not called when the selection is the
    /// same afterwards. Same single-slot, chain-the-previous rule as
    /// ``onDocumentChange``.
    public var onSelectionChange: (@MainActor () -> Void)?

    /// Creates a model over `document`, projecting it into `bridge`
    /// immediately so the two never start out of sync.
    public init(document: SceneDocument = SceneDocument()) {
        session = EditorSession(document: document)
        savedDocument = document
        bridge = RealityBridge()
        bridge.rebuild(from: session.document)
    }

    // MARK: Documents

    /// The content last opened or saved; ``hasUnsavedChanges`` compares
    /// against it, so undoing back to the saved state reads as clean.
    private var savedDocument: SceneDocument

    /// Whether the authored content differs from what was last opened or
    /// saved. Selection and undo history are not content.
    public var hasUnsavedChanges: Bool {
        !session.document.hasSameContent(as: savedDocument)
    }

    /// Records the current content as saved.
    public func markSaved() {
        savedDocument = session.document
    }

    /// Replaces the whole document, as opening a file does (ADR 0005).
    ///
    /// Not undoable: undo and redo history, selection, and `lastError` are
    /// cleared, the bridge is rebuilt from scratch, and the new content
    /// counts as saved unless `asSaved` is false, as when recovering unsaved
    /// changes (ADR 0012): the saved content is then left as it was.
    /// ``onDocumentChange`` runs last.
    public func replaceDocument(_ document: SceneDocument, asSaved: Bool = true) {
        let before = session.selection
        defer { reportSelection(changedFrom: before) }
        showGraph(nil)
        session = EditorSession(document: document)
        if asSaved { savedDocument = document }
        lastError = nil
        notice = nil
        bridge.rebuild(from: session.document)
        onDocumentChange?()
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
        select(id.map { [$0] } ?? [])
    }

    /// Replaces the selection with `ids`, the last one primary, or clears it
    /// when `ids` is empty. An id absent from the document sets `lastError`
    /// and leaves the selection unchanged.
    public func select(_ ids: [EntityID]) {
        let before = session.selection
        attempt { () throws(AuthoringError) in
            if ids.isEmpty {
                session.clearSelection()
            } else {
                try session.select(ids)
            }
        }
        reportSelection(changedFrom: before)
    }

    // MARK: Graphs (ADR 0007)

    /// Evaluates graphs; its registry is the node set the editor offers.
    public let graphEvaluator = GraphEvaluator()

    /// The graph the graph editor shows. Editor state; see ``currentGraph``.
    public private(set) var activeGraph: GraphID?
    /// The node the graph editor has selected, while it is still in the
    /// graph the editor shows. Editor state. Stored with its graph because
    /// node ids restart at `n1` in every graph: after an undo or a console
    /// `graph delete` switches the shown graph, a bare `n1` would silently
    /// name a different graph's node.
    public var selectedGraphNode: GraphNodeID? {
        guard let (graph, node) = nodeSelection, graph == currentGraph?.id,
              currentGraph?.node(node) != nil
        else { return nil }
        return node
    }
    private var nodeSelection: (GraphID, GraphNodeID)?

    /// An output picked as the start of a connection, waiting for an input,
    /// while it is still in the graph the editor shows (see
    /// ``selectedGraphNode``).
    public var pendingLink: PortReference? {
        guard let (graph, output) = linkStart, graph == currentGraph?.id,
              currentGraph?.node(output.node)?.output(output.port) != nil
        else { return nil }
        return output
    }
    private var linkStart: (GraphID, PortReference)?
    /// Whether the right-hand panel shows the graph editor instead of the
    /// inspector. Editor state.
    public private(set) var showsGraphEditor = false
    /// Which offered node type the graph editor's "Add" picker shows.
    public private(set) var nodePickerIndex = 0

    public func toggleGraphEditor() {
        showsGraphEditor.toggle()
    }

    /// The node types the current graph's domain offers.
    public var offeredNodes: [NodeDefinition] {
        guard let graph = currentGraph else { return [] }
        return graphEvaluator.registry.offered(in: graph.domain)
    }

    /// The node type the picker shows, if any.
    public var pickedNode: NodeDefinition? {
        let offered = offeredNodes
        guard !offered.isEmpty else { return nil }
        return offered[nodePickerIndex % offered.count]
    }

    public func cycleNodePicker(by delta: Int) {
        let count = offeredNodes.count
        guard count > 0 else { return }
        nodePickerIndex = ((nodePickerIndex + delta) % count + count) % count
    }

    /// The graph the editor shows: ``activeGraph`` while it exists, otherwise
    /// the first graph, or `nil` when the document has none.
    public var currentGraph: GraphDocument? {
        let document = session.document
        if let activeGraph, let graph = document.graph(activeGraph) { return graph }
        return document.graphOrder.first.flatMap(document.graph)
    }

    /// Creates a graph and shows it.
    public func createGraph(name: String, domain: GraphDomain) {
        let id = session.document.nextGraphID
        run(CreateGraph(name: name, domain: domain))
        guard lastError == nil else { return }
        showGraph(id)
    }

    /// Shows `id` in the graph editor.
    public func showGraph(_ id: GraphID?) {
        activeGraph = id
        nodeSelection = nil
        linkStart = nil
        nodePickerIndex = 0
    }

    /// Shows the next (or previous) graph in document order, wrapping.
    public func cycleGraph(by delta: Int) {
        let order = session.document.graphOrder
        guard !order.isEmpty else { return }
        let index = currentGraph.flatMap { order.firstIndex(of: $0.id) } ?? 0
        showGraph(order[((index + delta) % order.count + order.count) % order.count])
    }

    public func selectGraphNode(_ id: GraphNodeID?) {
        nodeSelection = zip(currentGraph?.id, id)
    }

    /// Applies graph edits and the graph's re-evaluation as one undoable
    /// step, so a graph edit and its effect on the scene undo together. An
    /// evaluation failure refuses the edit and records `lastError`.
    public func editGraph(_ graph: GraphID, label: String, _ commands: [any DocumentCommand]) {
        settle { () throws(AuthoringError) in
            try session.transaction(label, commands + [EvaluateGraph(graph, evaluator: graphEvaluator)])
        }
    }

    /// Adds a node of `definition` to the current graph and selects it.
    public func addGraphNode(_ definition: String) {
        guard let graph = currentGraph, let node = graphEvaluator.registry.definition(definition) else { return }
        let id = graph.nextNodeID
        let position = SIMD2<Float>(Float(graph.nodes.count) * 4, 0)
        editGraph(graph.id, label: "Add \(node.title)", [node.addCommand(to: graph.id, at: position)])
        if lastError == nil { nodeSelection = (graph.id, id) }
    }

    /// Removes the selected graph node and its connections.
    public func removeSelectedGraphNode() {
        guard let graph = currentGraph, let node = selectedGraphNode else { return }
        editGraph(graph.id, label: "Remove Node", [RemoveGraphNode(node, from: graph.id)])
        if lastError == nil { nodeSelection = nil }
    }

    /// Starts a connection at an output; ``completeLink(to:)`` finishes it.
    public func beginLink(from output: PortReference) {
        linkStart = zip(currentGraph?.id, output)
    }

    /// Connects the pending output to `input` in the current graph.
    public func completeLink(to input: PortReference) {
        guard let graph = currentGraph, let from = pendingLink else { return }
        linkStart = nil
        editGraph(graph.id, label: "Connect", [ConnectPorts(from, to: input, in: graph.id)])
    }

    public func cancelLink() {
        linkStart = nil
    }

    /// Disconnects `input` in the current graph.
    public func disconnect(_ input: PortReference) {
        guard let graph = currentGraph else { return }
        editGraph(graph.id, label: "Disconnect", [DisconnectPorts(input, in: graph.id)])
    }

    /// Sets a constant on an input of the current graph.
    public func setGraphValue(_ value: GraphValue?, for input: PortReference) {
        guard let graph = currentGraph else { return }
        editGraph(graph.id, label: "Set \(input.port)", [SetGraphValue(value, for: input.port, of: input.node, in: graph.id)])
    }

    /// Adds `delta` to a float constant (the editor's − and + buttons),
    /// rounded to hundredths so repeated steps do not drift (0.5 + 0.1 + 0.1
    /// stays 0.7, not 0.70000005).
    public func nudgeGraphValue(_ input: PortReference, by delta: Float) {
        guard let node = currentGraph?.node(input.node), case .float(let value)? = node.values[input.port] else { return }
        setGraphValue(.float(((value + delta) * 100).rounded() / 100), for: input)
    }

    /// Points an entity input at the primary selection.
    public func targetSelection(_ input: PortReference) {
        guard let id = session.selection.primary else { return }
        setGraphValue(.entity(id), for: input)
    }

    /// Re-applies the current graph to the scene, for example after the
    /// scene was edited by hand.
    public func applyCurrentGraph() {
        guard let graph = currentGraph else { return }
        run(EvaluateGraph(graph.id, evaluator: graphEvaluator))
    }

    /// Deletes the current graph.
    public func deleteCurrentGraph() {
        guard let graph = currentGraph else { return }
        run(DeleteGraph(graph.id))
        if lastError == nil { showGraph(nil) }
    }

    // MARK: Console

    /// One console exchange: what was typed and what came back. A note
    /// (ADR 0016) is a message from the editor with nothing typed; the
    /// panel shows it without the prompt.
    public struct ConsoleEntry: Hashable, Sendable {
        public var input: String
        public var output: String
        public var isError: Bool
        public var isNote: Bool

        public init(input: String, output: String, isError: Bool, isNote: Bool = false) {
            self.input = input
            self.output = output
            self.isError = isError
            self.isNote = isNote
        }

        /// A message from the editor, not an exchange.
        public static func note(_ text: String) -> ConsoleEntry {
            ConsoleEntry(input: "", output: text, isError: false, isNote: true)
        }
    }

    /// Shows `text` in the status line until the next document change and
    /// keeps it in the console log as a note (ADR 0015, ADR 0016).
    public func post(notice text: String) {
        notice = text
        appendConsole(.note(text))
    }

    /// Appends to ``consoleLog``, keeping at most ``consoleLogLimit``.
    private func appendConsole(_ entry: ConsoleEntry) {
        consoleLog.append(entry)
        if consoleLog.count > Self.consoleLogLimit {
            consoleLog.removeFirst(consoleLog.count - Self.consoleLogLimit)
        }
    }

    /// The most recent console exchanges, oldest first, at most
    /// ``consoleLogLimit``. Editor state, not authored state.
    public private(set) var consoleLog: [ConsoleEntry] = []
    public static let consoleLogLimit = 50

    /// The console's input line, bound to its text field.
    public var consoleInput = ""

    /// Runs ``consoleInput`` as a console line and clears it.
    public func submitConsole() {
        let line = consoleInput
        consoleInput = ""
        runConsole(line)
    }

    /// Parses `line` against the current document and selection and runs
    /// the result through the same funnel as every other edit (ADR 0006):
    /// document edits become ``EditorSession`` commands, one per step, and
    /// `add`, `select`, `undo`, and `redo` call the methods the toolbar and
    /// panels call. The exchange is appended to ``consoleLog`` and returned.
    /// A blank line does nothing and returns `nil`.
    @discardableResult
    public func runConsole(_ line: String) -> ConsoleEntry? {
        let trimmed = line.trimmingWhitespace()
        guard !trimmed.isEmpty else { return nil }
        let parser = ConsoleParser(
            document: session.document, selection: session.selection, registry: graphEvaluator.registry
        )
        var output: String
        var isError = false
        do {
            let action = try parser.parse(trimmed)
            // A refusal left over from an earlier action is not this line's.
            if case .help = action {} else { lastError = nil }
            switch action {
            case .edit(let label, let commands):
                if commands.count == 1 {
                    run(commands[0])
                } else {
                    settle { () throws(AuthoringError) in try session.transaction(label, commands) }
                }
                output = session.undoLabel ?? label
            case .addPrimitive(let primitive):
                addPrimitive(primitive)
                output = createdMessage()
            case .addLight(let kind):
                addLight(kind)
                output = createdMessage()
            case .addCamera:
                addCamera()
                output = createdMessage()
            case .select(let ids):
                select(ids)
                output = ids.isEmpty ? "Selection cleared" : "Selected \(ids.count == 1 ? name(of: ids[0]) : "\(ids.count) entities")"
            case .undo:
                let label = session.undoLabel
                undo()
                output = "Undid \(label ?? "")"
            case .redo:
                let label = session.redoLabel
                redo()
                output = "Redid \(label ?? "")"
            case .graphEdit(let graph, let label, let commands):
                editGraph(graph, label: label, commands)
                output = session.undoLabel ?? label
            case .createGraph(let name, let domain):
                createGraph(name: name, domain: domain)
                output = currentGraph.map { "Created graph \($0.id) \($0.name)" } ?? "Created graph"
            case .help(let text):
                output = text
            }
            if case .help = action {} else if let lastError {
                output = "refused: \(lastError)"
                isError = true
            }
        } catch {
            output = error.message
            isError = true
        }
        let entry = ConsoleEntry(input: trimmed, output: output, isError: isError)
        appendConsole(entry)
        return entry
    }

    private func createdMessage() -> String {
        guard let id = session.selection.primary else { return "Created" }
        return "Created \(name(of: id))"
    }

    private func name(of id: EntityID) -> String {
        session.document.entity(id)?.name ?? "\(id)"
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
        let before = session.selection
        defer { reportSelection(changedFrom: before) }
        var applied = false
        attempt { () throws(AuthoringError) in
            try operation()
            bridge.apply(session.drainChanges(), from: session.document)
            applied = true
        }
        if applied {
            notice = nil
            onDocumentChange?()
        }
    }

    private func reportSelection(changedFrom before: Selection) {
        if session.selection != before { onSelectionChange?() }
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
extension String {
    /// The string without leading and trailing whitespace, without Foundation.
    func trimmingWhitespace() -> String {
        let start = firstIndex { !$0.isWhitespace } ?? endIndex
        let end = lastIndex { !$0.isWhitespace }.map(index(after:)) ?? start
        return String(self[start..<max(start, end)])
    }
}
/// Both values, or `nil` when either is missing.
private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
#endif
