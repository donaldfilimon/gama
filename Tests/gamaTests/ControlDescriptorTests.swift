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
