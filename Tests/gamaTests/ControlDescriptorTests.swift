//  ControlDescriptorTests.swift — the control side table (ADR 0017,
//  native-presentation plan Tasks 3-5): registration through
//  `BuildContext`, the per-build table `FrameHost` and `HostPump` expose,
//  descriptor-driven control sizing, what each control registers, and the
//  host's direct `activate`/`focus` entry points.

import Testing

@testable import GamaCore
@testable import GamaDraw

/// Records every control registration a build makes, in order.
private final class ControlLog {
    var entries: [(NodeID, ControlDescriptor)] = []
}

/// A primitive that registers whatever descriptors it is given under its
/// own identity and renders a focusable interactive text node.
private struct Registrar: View {
    typealias Body = Never_
    var body: Never_ { Never_() }
    let descriptors: [ControlDescriptor]
    func render(in context: BuildContext) -> RenderNode {
        for descriptor in descriptors { context.registerControl(context.id, descriptor) }
        return .interactive(id: context.id, focusable: true, child: .text("ctl", style: .plain))
    }
}

private func buttonTitle(_ descriptor: ControlDescriptor?) -> String?? {
    guard case .button(let title, _)? = descriptor else { return nil }
    return .some(title)
}

@Suite("ControlDescriptor build")
struct ControlDescriptorBuildTests {
    @Test("a build context forwards registrations to its hook")
    func contextRecordsRegistrations() {
        let log = ControlLog()
        let context = BuildContext(registerControl: { id, descriptor in log.entries.append((id, descriptor)) })
        _ = Registrar(descriptors: [.button(title: "Go", isEnabled: true)]).render(in: context)
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.0 == .root)
        #expect(buttonTitle(log.entries.first?.1) == .some("Go"))
    }

    @Test("child contexts inherit the registration hook")
    func childInheritsHook() {
        let log = ControlLog()
        let context = BuildContext(registerControl: { id, descriptor in log.entries.append((id, descriptor)) })
        _ = Registrar(descriptors: [.progress(fraction: 0.5, label: nil)]).render(in: context.child(2))
        #expect(log.entries.first?.0 == NodeID.root.child(2))
    }

    @Test("the default hook is a no-op, so host-less builds still render")
    func defaultHookIsNoop() {
        let node = Registrar(descriptors: [.button(title: "Go", isEnabled: true)]).render(in: BuildContext())
        #expect(node == .interactive(id: .root, focusable: true, child: .text("ctl", style: .plain)))
    }
}

private struct ControlHostApp: App {
    let show: Signal<Bool>
    init() { show = Signal(true) }
    init(show: Signal<Bool>) { self.show = show }
    var scenes: some Scene {
        Window("Controls", id: "main", role: .primary) {
            VStack {
                if show.get() {
                    Registrar(descriptors: [.button(title: "First", isEnabled: true)])
                }
                Registrar(descriptors: [
                    .button(title: "Early", isEnabled: true),
                    .toggle(title: "Late", isOn: true, isEnabled: true),
                ])
            }
        }
    }
}

@Suite("ControlDescriptor host table")
struct ControlDescriptorHostTests {
    @Test("the host exposes this build's controls after pump")
    func hostExposesControls() throws {
        var host = try FrameHost(app: ControlHostApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        let controls = host.controls
        #expect(controls.count == 2)
        #expect(controls.values.contains { buttonTitle($0) == .some("First") })
    }

    @Test("a duplicate registration keeps the last descriptor")
    func duplicateKeepsLast() throws {
        var host = try FrameHost(app: ControlHostApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        let controls = host.controls
        let toggles = controls.values.filter {
            if case .toggle(let title, _, _) = $0 { return title == "Late" }
            return false
        }
        #expect(toggles.count == 1)
        #expect(!controls.values.contains { buttonTitle($0) == .some("Early") })
    }

    @Test("each build pass clears the table")
    func buildPassClears() throws {
        let show = Signal(true)
        var host = try FrameHost(app: ControlHostApp(show: show))
        _ = host.pump(size: Size(width: 20, height: 6))
        show.set(false)
        _ = host.pump(size: Size(width: 20, height: 6))
        let controls = host.controls
        #expect(controls.count == 1)
        #expect(!controls.values.contains { buttonTitle($0) == .some("First") })
    }

    @Test("HostPump mirrors the host's table")
    func pumpMirrorsTable() throws {
        var pump = HostPump(host: try FrameHost(app: ControlHostApp()), size: Size(width: 20, height: 6))
        _ = pump.advance()
        let controls = pump.controls
        #expect(controls.count == 2)
    }
}

private struct SizedButtonApp: App {
    var scenes: some Scene {
        Window("Sized", id: "main", role: .primary) {
            HStack {
                Registrar(descriptors: [.button(title: "Save", isEnabled: true)])
                Text("x")
            }
        }
    }
}

@Suite("ControlDescriptor sizing")
struct ControlDescriptorSizingTests {
    private static func interactiveFrames(_ laid: LaidOutNode) -> [Rect] {
        var regions: [InteractiveRegion] = []
        laid.collectInteractive(into: &regions)
        return regions.map(\.frame)
    }

    @Test("descriptorSize sizes a registered control inside a host")
    func descriptorSizeWins() throws {
        var metrics = LayoutMetrics.cell
        metrics.descriptorSize = { descriptor, _ in
            if case .button = descriptor { return Size(width: 9, height: 2) }
            return nil
        }
        var host = try FrameHost(app: SizedButtonApp(), metrics: metrics)
        let laid = host.pump(size: Size(width: 30, height: 6))
        #expect(Self.interactiveFrames(laid).first?.size == Size(width: 9, height: 2))
    }

    @Test("with cell metrics a registered control measures its child")
    func cellLayoutUnchanged() throws {
        var host = try FrameHost(app: SizedButtonApp())
        let laid = host.pump(size: Size(width: 30, height: 6))
        #expect(Self.interactiveFrames(laid).first?.size == Size(width: 3, height: 1))
    }

    @Test("a nil descriptorSize falls back to the base controlSize")
    func fallsBackToControlSize() throws {
        var metrics = LayoutMetrics.cell
        metrics.controlSize = { _, _ in Size(width: 4, height: 3) }
        var host = try FrameHost(app: SizedButtonApp(), metrics: metrics)
        let laid = host.pump(size: Size(width: 30, height: 6))
        #expect(Self.interactiveFrames(laid).first?.size == Size(width: 4, height: 3))
    }

    @Test("cell metrics report no descriptor size")
    func cellHasNoDescriptorSize() {
        let size = LayoutMetrics.cell.descriptorSize(.button(title: "A", isEnabled: true), .unspecified)
        #expect(size == nil)
    }
}

/// Renders `view` with a registering context and returns the node plus the
/// descriptors it registered, keyed by node.
private func renderRegistering<V: View>(
    _ view: V, environment: EnvironmentValues = EnvironmentValues()
) -> (node: RenderNode, controls: [NodeID: ControlDescriptor], log: ControlLog) {
    let log = ControlLog()
    let context = BuildContext(
        environment: environment,
        registerControl: { id, descriptor in log.entries.append((id, descriptor)) })
    let node = view.render(in: context)
    var table: [NodeID: ControlDescriptor] = [:]
    for (id, descriptor) in log.entries { table[id] = descriptor }
    return (node, table, log)
}

/// Paints `node` laid out in a `size` grid.
private func paintCells(_ node: RenderNode, size: Size = Size(width: 40, height: 3)) -> CellBuffer {
    var buffer = CellBuffer(size: size)
    CellPainter.paint(LayoutEngine.layout(node, in: Rect(origin: .zero, size: size)), into: &buffer)
    return buffer
}

@Suite("Control registration")
struct ControlRegistrationTests {
    @Test("a titled button registers its trimmed title, enabled")
    func titledButton() {
        let (node, controls, _) = renderRegistering(Button("Save", action: {}))
        guard case .button(let title, let isEnabled)? = controls[.root] else {
            Issue.record("no button descriptor"); return
        }
        #expect(title == "Save")
        #expect(isEnabled)
        #expect(paintCells(node) == paintCells(Button("Save", action: {}).render(in: BuildContext())))
    }

    @Test("a composite label registers a nil title")
    func compositeButton() {
        let (_, controls, _) = renderRegistering(
            Button(action: {}) {
                HStack {
                    Text("A")
                    Text("B")
                }
            })
        guard case .button(let title, _)? = controls[.root] else {
            Issue.record("no button descriptor"); return
        }
        #expect(title == nil)
    }

    @Test("a styled single-run label still has a title")
    func styledLabelHasTitle() {
        let (_, controls, _) = renderRegistering(Button(action: {}) { Text("Go").bold() })
        #expect(buttonTitle(controls[.root]) == .some("Go"))
    }

    @Test("a disabled button registers isEnabled false and no action")
    func disabledButton() {
        var env = EnvironmentValues()
        env.isEnabled = false
        var actions = 0
        let log = ControlLog()
        let context = BuildContext(
            environment: env,
            registerAction: { _, _ in actions += 1 },
            registerControl: { id, descriptor in log.entries.append((id, descriptor)) })
        _ = Button("Off", action: {}).render(in: context)
        #expect(actions == 0)
        guard case .button(let title, let isEnabled)? = log.entries.last?.1 else {
            Issue.record("no button descriptor"); return
        }
        #expect(title == "Off")
        #expect(!isEnabled)
    }

    @Test("a toggle's descriptor replaces its button's")
    func toggleReplacesButton() {
        let flag = Signal(true)
        let (node, controls, log) = renderRegistering(Toggle("Wifi", isOn: flag.binding()))
        #expect(log.entries.count == 2)
        guard case .toggle(let title, let isOn, let isEnabled)? = controls[.root] else {
            Issue.record("no toggle descriptor"); return
        }
        #expect(title == "Wifi")
        #expect(isOn)
        #expect(isEnabled)
        #expect(paintCells(node) == paintCells(Toggle("Wifi", isOn: flag.binding()).render(in: BuildContext())))
    }

    @Test("a text field registers its state and setText writes the binding")
    func textField() {
        let text = Signal("")
        let (node, controls, _) = renderRegistering(TextField("Name", text: text.binding()))
        guard case .textField(let placeholder, let value, let isEnabled, let setText)? = controls[.root] else {
            Issue.record("no text field descriptor"); return
        }
        #expect(placeholder == "Name")
        #expect(value == "")
        #expect(isEnabled)
        setText("Ada")
        #expect(text.get() == "Ada")
        #expect(paintCells(node) == paintCells(TextField("Name", text: Signal("").binding()).render(in: BuildContext())))
    }

    @Test("progress registers its clamped fraction and label")
    func progress() {
        let (node, controls, _) = renderRegistering(ProgressView(value: 3, total: 2, label: "Load"))
        guard case .progress(let fraction, let label)? = controls[.root] else {
            Issue.record("no progress descriptor"); return
        }
        #expect(fraction == 1)
        #expect(label == "Load")
        guard case .interactive(let id, let focusable, let child) = node else {
            Issue.record("progress is not interactive"); return
        }
        #expect(id == .root)
        #expect(!focusable)
        // Cells are identical to the bare text the view compiled to before.
        #expect(paintCells(node) == paintCells(child))
    }

    @Test("a pointer press on a progress bar runs nothing and moves no focus")
    func progressPointerIsNoop() throws {
        let app = ProgressPointerApp()
        var host = try FrameHost(app: app)
        let before = host.pump(size: Size(width: 40, height: 4))
        var regions: [InteractiveRegion] = []
        before.collectInteractive(into: &regions)
        guard let bar = regions.first(where: { !$0.isFocusable }) else {
            Issue.record("no progress region"); return
        }
        host.handle(.pointer(bar.frame.origin, pressed: true))
        let after = host.pump(size: Size(width: 40, height: 4))
        #expect(app.taps.get() == 0)
        // Same tree, including the focus highlight: focus did not move.
        #expect(after == before)
    }

    @Test("a pointer press on a progress bar inside a button runs the button's action")
    func progressInsideButtonPassesPressThrough() throws {
        let app = NestedProgressApp()
        var host = try FrameHost(app: app)
        let laid = host.pump(size: Size(width: 40, height: 4))
        var regions: [InteractiveRegion] = []
        laid.collectInteractive(into: &regions)
        guard let bar = regions.last, !bar.isFocusable else {
            Issue.record("no nested progress region"); return
        }
        host.handle(.pointer(bar.frame.origin, pressed: true))
        #expect(app.taps.get() == 1)
    }

    @Test("hovering a progress bar inside a button hovers the button")
    func progressInsideButtonPassesHoverThrough() throws {
        let app = NestedProgressApp()
        var host = try FrameHost(app: app)
        let laid = host.pump(size: Size(width: 40, height: 4))
        var regions: [InteractiveRegion] = []
        laid.collectInteractive(into: &regions)
        guard let button = regions.first, let bar = regions.last, !bar.isFocusable, button.id != bar.id else {
            Issue.record("no nested progress region"); return
        }
        host.handle(.pointerEvent(PointerEvent(phase: .hover, location: bar.frame.origin)))
        let hovered = host.hoveredID
        #expect(hovered == button.id)
    }
}

private struct NestedProgressApp: App {
    let taps = Signal(0)
    init() {}
    var scenes: some Scene {
        Window("Nested", id: "main", role: .primary) {
            Button(action: { taps.update { $0 += 1 } }) {
                ProgressView(value: 0.5, label: "Load")
            }
        }
    }
}

private struct ProgressPointerApp: App {
    let taps = Signal(0)
    init() {}
    var scenes: some Scene {
        Window("Progress", id: "main", role: .primary) {
            VStack {
                Button("Tap") { taps.update { $0 += 1 } }
                ProgressView(value: 0.5, label: "Load")
            }
        }
    }
}

private struct ActivationApp: App {
    let taps = Signal(0)
    let text = Signal("")
    init() {}
    var scenes: some Scene {
        Window("Activation", id: "main", role: .primary) {
            VStack {
                Button("Tap") { taps.update { $0 += 1 } }
                TextField("Name", text: text.binding())
                ProgressView(value: 0.25)
            }
        }
    }
}

/// The ids of a frame's interactive nodes in visual order.
private func interactiveIDs(_ laid: LaidOutNode) -> [NodeID] {
    var regions: [InteractiveRegion] = []
    laid.collectInteractive(into: &regions)
    return regions.map(\.id)
}

@Suite("Host activation and focus")
struct HostActivationTests {
    @Test("activate runs the node's action and marks the host dirty")
    func activateRunsAction() throws {
        let app = ActivationApp()
        var host = try FrameHost(app: app)
        let ids = interactiveIDs(host.pump(size: Size(width: 40, height: 5)))
        host.activate(ids[0])
        let dirty = host.needsFrame
        #expect(app.taps.get() == 1)
        #expect(dirty)
    }

    @Test("activate on a node with no action changes nothing")
    func activateWithoutActionIsNoop() throws {
        let app = ActivationApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 5))
        // A second pump settles any focus-reconciliation follow-up.
        let ids = interactiveIDs(host.pump(size: Size(width: 40, height: 5)))
        let focusedBefore = host.focusedID
        host.activate(ids[2])
        host.activate(NodeID(raw: 42))
        let dirty = host.needsFrame
        let focusedAfter = host.focusedID
        #expect(app.taps.get() == 0)
        #expect(!dirty)
        #expect(focusedAfter == focusedBefore)
    }

    @Test("activate focuses a focusable target like a pointer press")
    func activateFocuses() throws {
        let app = ActivationApp()
        var host = try FrameHost(app: app)
        let ids = interactiveIDs(host.pump(size: Size(width: 40, height: 5)))
        host.focus(ids[1])
        _ = host.pump(size: Size(width: 40, height: 5))
        host.activate(ids[0])
        let focused = host.focusedID
        #expect(focused == ids[0])
    }

    @Test("focus moves to a focusable node and marks dirty")
    func focusMoves() throws {
        var host = try FrameHost(app: ActivationApp())
        let ids = interactiveIDs(host.pump(size: Size(width: 40, height: 5)))
        let initial = host.focusedID
        #expect(initial == ids[0])
        host.focus(ids[1])
        let focused = host.focusedID
        let dirty = host.needsFrame
        #expect(focused == ids[1])
        #expect(dirty)
    }

    @Test("focus on the focused, a non-focusable, or an unknown node changes nothing")
    func focusNoops() throws {
        var host = try FrameHost(app: ActivationApp())
        _ = host.pump(size: Size(width: 40, height: 5))
        let ids = interactiveIDs(host.pump(size: Size(width: 40, height: 5)))
        host.focus(ids[0])
        host.focus(ids[2])
        host.focus(NodeID(raw: 42))
        let focused = host.focusedID
        let dirty = host.needsFrame
        #expect(focused == ids[0])
        #expect(!dirty)
    }

    @Test("setText writes a text field's binding and marks the host dirty")
    func setTextWritesBinding() throws {
        let app = ActivationApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 5))
        let ids = interactiveIDs(host.pump(size: Size(width: 40, height: 5)))
        host.setText(ids[1], "typed")
        let dirty = host.needsFrame
        #expect(app.text.get() == "typed")
        #expect(dirty)
    }

    @Test("setText on a node that is not a text field changes nothing")
    func setTextIgnoresOtherNodes() throws {
        let app = ActivationApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 40, height: 5))
        let ids = interactiveIDs(host.pump(size: Size(width: 40, height: 5)))
        host.setText(ids[0], "typed")
        host.setText(NodeID(raw: 42), "typed")
        let dirty = host.needsFrame
        #expect(app.text.get() == "")
        #expect(app.taps.get() == 0)
        #expect(!dirty)
    }

    @Test("HostPump passes activate, focus, and focusedID through")
    func pumpPassThrough() throws {
        let app = ActivationApp()
        var pump = HostPump(host: try FrameHost(app: app), size: Size(width: 40, height: 5))
        guard let frame = pump.advance()?.frame else {
            Issue.record("no frame"); return
        }
        let ids = interactiveIDs(frame)
        pump.focus(ids[1])
        let focused = pump.focusedID
        #expect(focused == ids[1])
        pump.activate(ids[0])
        #expect(app.taps.get() == 1)
        let dirty = pump.needsFrame
        #expect(dirty)
        pump.setText(ids[1], "via pump")
        #expect(app.text.get() == "via pump")
    }
}
