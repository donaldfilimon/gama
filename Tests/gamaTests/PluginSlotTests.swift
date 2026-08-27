import GamaCore
import GamaPlugin
import Testing

/// Lets the app's scene closure pick up a runtime created after the
/// host, the same pattern the demo uses.
private final class RuntimeBox: @unchecked Sendable {
    var runtime: PluginRuntime?
}

private struct SlotApp: App {
    let box: RuntimeBox
    init() { box = RuntimeBox() }
    init(box: RuntimeBox) { self.box = box }

    var scenes: some Scene {
        Window("Main", id: "main", role: .primary) {
            VStack(spacing: 0) {
                Text("header")
                if let runtime = box.runtime {
                    PluginSlot("sidebar", runtime: runtime)
                }
            }
        }
    }
}

/// A plugin contributing one interactive line backed by a Signal.
private struct CounterPlugin: GamaPluginProtocol {
    let id: PluginID
    let counter: Signal<Int>

    var manifest: PluginManifest {
        PluginManifest(id: id, version: PluginVersion(major: 1, minor: 0, patch: 0))
    }

    mutating func activate(in context: PluginContext) throws(PluginError) {
        context.subscriptions.observe(counter)
    }

    func render(slot: SlotID, in context: BuildContext) -> RenderNode {
        guard slot == "sidebar" else { return .empty }
        let counter = counter
        context.registerAction(context.id) { counter.update { $0 += 1 } }
        return .interactive(
            id: context.id,
            focusable: true,
            child: .text("\(id.raw):\(counter.get())", style: .plain)
        )
    }
}

private func collectTexts(_ node: LaidOutNode, into out: inout [String]) {
    if case .text(let text, _) = node.node { out.append(text) }
    for child in node.children { collectTexts(child, into: &out) }
}

private func makeAttachedRuntime(
    _ box: RuntimeBox, subscriptions: SubscriptionContext
) -> PluginRuntime {
    let runtime = PluginRuntime(
        grants: .denyAll,
        services: HostServices(),
        subscriptions: subscriptions
    )
    box.runtime = runtime
    return runtime
}

@Suite("Plugin slots: render contribution through one host")
struct PluginSlotTests {
    @Test("a slot with zero plugins renders empty and adds no interactive nodes")
    func emptySlot() throws {
        let box = RuntimeBox()
        var host = try FrameHost(app: SlotApp(box: box))
        let runtime = makeAttachedRuntime(box, subscriptions: host.subscriptions)
        #expect(runtime.render(slot: "sidebar", in: BuildContext()) == .empty)
        let laid = host.pump(size: Size(width: 40, height: 6))
        var regions: [InteractiveRegion] = []
        laid.collectInteractive(into: &regions)
        #expect(regions.isEmpty)
        var texts: [String] = []
        collectTexts(laid, into: &texts)
        #expect(texts == ["header"])
    }

    @Test("contributed IR appears in pump output at the slot's position")
    func contributedIRInFrame() throws {
        let box = RuntimeBox()
        var host = try FrameHost(app: SlotApp(box: box))
        let runtime = makeAttachedRuntime(box, subscriptions: host.subscriptions)
        try runtime.install(CounterPlugin(id: "test.one", counter: Signal(7)))
        let laid = host.pump(size: Size(width: 40, height: 6))
        var texts: [String] = []
        collectTexts(laid, into: &texts)
        #expect(texts == ["header", "test.one:7"])
    }

    @Test("a contributed interactive node's action registers in the owning host")
    func actionRegistersThroughHost() throws {
        let box = RuntimeBox()
        var host = try FrameHost(app: SlotApp(box: box))
        let runtime = makeAttachedRuntime(box, subscriptions: host.subscriptions)
        let counter = Signal(0)
        try runtime.install(CounterPlugin(id: "test.one", counter: counter))
        let laid = host.pump(size: Size(width: 40, height: 6))
        var regions: [InteractiveRegion] = []
        laid.collectInteractive(into: &regions)
        let region = try #require(regions.first)

        host.handle(
            .pointer(Point(x: region.frame.minX, y: region.frame.minY), pressed: true))
        #expect(counter.get() == 1)
        let dirtyAfterPress = host.needsFrame
        #expect(dirtyAfterPress)
        var texts: [String] = []
        collectTexts(host.pump(size: Size(width: 40, height: 6)), into: &texts)
        #expect(texts == ["header", "test.one:1"])
    }

    @Test("two plugins get distinct stable identities and reinstalls reproduce them")
    func identityStability() throws {
        let box = RuntimeBox()
        var host = try FrameHost(app: SlotApp(box: box))
        let runtime = makeAttachedRuntime(box, subscriptions: host.subscriptions)
        try runtime.install(CounterPlugin(id: "test.one", counter: Signal(0)))
        try runtime.install(CounterPlugin(id: "test.two", counter: Signal(0)))
        let first = host.pump(size: Size(width: 40, height: 6))
        var firstRegions: [InteractiveRegion] = []
        first.collectInteractive(into: &firstRegions)
        #expect(firstRegions.count == 2)
        #expect(firstRegions[0].id != firstRegions[1].id)
        let firstDuplicates = host.duplicateIDs
        #expect(firstDuplicates.isEmpty)

        runtime.uninstall("test.one")
        runtime.uninstall("test.two")
        try runtime.install(CounterPlugin(id: "test.one", counter: Signal(0)))
        try runtime.install(CounterPlugin(id: "test.two", counter: Signal(0)))
        let second = host.pump(size: Size(width: 40, height: 6))
        var secondRegions: [InteractiveRegion] = []
        second.collectInteractive(into: &secondRegions)
        #expect(secondRegions.map(\.id) == firstRegions.map(\.id))
        let secondDuplicates = host.duplicateIDs
        #expect(secondDuplicates.isEmpty)
    }

    @Test("a plugin Signal observed through the context dirties the host end to end")
    func reactiveSignalPath() throws {
        let box = RuntimeBox()
        var host = try FrameHost(app: SlotApp(box: box))
        let runtime = makeAttachedRuntime(box, subscriptions: host.subscriptions)
        let counter = Signal(1)
        try runtime.install(CounterPlugin(id: "test.one", counter: counter))
        _ = host.pump(size: Size(width: 40, height: 6))
        let cleanAfterPump = host.needsFrame
        #expect(!cleanAfterPump)

        counter.set(9)
        let dirtyAfterSet = host.needsFrame
        #expect(dirtyAfterSet)
        var texts: [String] = []
        collectTexts(host.pump(size: Size(width: 40, height: 6)), into: &texts)
        #expect(texts == ["header", "test.one:9"])
    }
}
