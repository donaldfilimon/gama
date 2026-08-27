//  main.swift — gama-demo
//  Run:            swift run gama-demo
//  Emit MLIR:      swift run gama-demo --emit-mlir
//                  (or GAMA_EMIT_MLIR=1 swift run gama-demo)
//
//  Tab / Shift-Tab move focus, Enter/Space activates, mouse clicks work,
//  Ctrl-C / Ctrl-Q quits.

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Android)
    import Android
#endif

import GamaTUI
import GamaMLIR
import GamaMacros
import GamaPlugin
import GamaPlatformServices

let accent = #rgb("FF8800")
let teal = #rgb("34C9B0")

@Component
struct StatBadge {
    var label: String
    var value: Int

    var body: some View {
        HStack(spacing: 1) {
            Text(label).foregroundColor(.gray)
            Text("\(value)").bold().foregroundColor(teal)
        }
        .padding(EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1))
    }
}

@Component
struct CounterPanel {
    @Reactive var count: Int = 0
    @Reactive var step: Int = 1
    private let name = Signal("")
    private let notifications = Signal(true)

    var body: some View {
        VStack(spacing: 1) {
            Text("Gama").bold().foregroundColor(accent)
            Text("Swift 6 · macros · Embedded-ready · MLIR-lowered")
                .italic()
                .foregroundColor(.gray)
            Divider()
            HStack(spacing: 2) {
                StatBadge(label: "count", value: count)
                StatBadge(label: "step", value: step)
            }
            HStack(spacing: 2) {
                Button("−\(step)") { count -= step }
                Button("+\(step)") { count += step }
                Button("step ×2") { step *= 2 }
                Button("reset") {
                    count = 0
                    step = 1
                }
                // Disabled until there's something to undo.
                Button("−reset") { count = 0 }
                    .disabled(count == 0)
            }
            HStack(spacing: 2) {
                TextField("your name", text: name.binding())
                Toggle("notifications", isOn: notifications.binding())
            }
            ProgressView(value: Double(min(10, abs(count))), total: 10, label: "activity")
            List {
                Text("• shared retained layout")
                Text("• Unicode-aware cells")
            }
            Text("Tab focus · Enter/Space press · click works · Ctrl-C quit")
                .foregroundColor(.gray)
        }
        .padding(EdgeInsets(all: 1))
        .border(.rounded, title: "demo")
        .frame(width: 72, height: 18)
    }
}

// Fills after the FrameHost exists: scene content closures evaluate
// lazily, so the slot picks the runtime up on the first pump. Confined
// to the demo's single-threaded setup.
final class PluginRuntimeBox {
    var runtime: PluginRuntime?
}

/// Tier-1 demo plugin: renders a status line into the app's "status"
/// slot using the granted `.log` and `.clock` capabilities.
struct StatusLinePlugin: GamaPluginProtocol {
    var manifest: PluginManifest {
        PluginManifest(
            id: "dev.gama.demo.status",
            version: PluginVersion(major: 0, minor: 1, patch: 0),
            requires: [.log, .clock]
        )
    }

    private var clock: ClockAccess?

    mutating func activate(in context: PluginContext) throws(PluginError) {
        clock = context.clock
        context.log?.log("status plugin activated")
    }

    func render(slot: SlotID, in context: BuildContext) -> RenderNode {
        guard slot == "status" else { return .empty }
        let seconds = (clock?.nowMillis() ?? 0) / 1000
        return .text(
            "plugin: dev.gama.demo.status · host uptime \(seconds)s · log+clock granted",
            style: TextStyle(foreground: .gray)
        )
    }
}

struct DemoApp: App {
    let pluginBox: PluginRuntimeBox
    // One panel instance for the life of the app. `@Reactive` state lives in
    // the component instance and scene content is rebuilt every frame, so a
    // `CounterPanel()` constructed inside the closure below would be replaced
    // — along with its count, step, name, and toggle — before the frame that
    // follows a press ever paints.
    private let panel = CounterPanel()
    init() { pluginBox = PluginRuntimeBox() }
    init(pluginBox: PluginRuntimeBox) { self.pluginBox = pluginBox }
    var scenes: some Scene {
        Window("Gama Demo", id: "main", role: .primary) {
            ZStack(alignment: .center) {
                VStack(spacing: 0) {
                    panel
                    if let runtime = pluginBox.runtime {
                        PluginSlot("status", runtime: runtime)
                    }
                }
            }
        }
    }
}

// MARK: - Entry

let wantsMLIR =
    CommandLine.arguments.contains("--emit-mlir")
    || ProcessEnvLookup.isSet("GAMA_EMIT_MLIR")

if wantsMLIR {
    // Structural + frame-annotated lowering of the demo tree at 80×24.
    let graph = try compileSceneGraph(DemoApp())
    let surface = try graph.makePrimarySurface()
    let ir = surface.render(BuildContext(id: .root))
    print("// ── gama dialect · structural ─────────────────────────────")
    print(GamaLowering.lower(module: ir, name: "demo"))
    let laid = LayoutEngine.layout(ir, in: Rect(x: 0, y: 0, width: 80, height: 24))
    print("// ── gama dialect · frame-annotated (80×24) ────────────────")
    print(GamaLowering.lower(laidOut: laid, name: "demo_laid"))
    print("// pipe into: mlir-opt --allow-unregistered-dialect")
} else {
    try runDemoWithPlugins()
}

// The plugin runtime needs the host's SubscriptionContext, so the demo
// builds its FrameHost explicitly and mirrors AppRuntime.run()'s loop
// instead of using the plugin-free App.main(renderer:) convenience.
func runDemoWithPlugins() throws {
    let box = PluginRuntimeBox()
    var host = try FrameHost(app: DemoApp(pluginBox: box))
    let plugins = PluginRuntime(
        grants: CapabilityGrants(table: ["dev.gama.demo.status": [.log, .clock]]),
        services: .standard,
        subscriptions: host.subscriptions
    )
    try plugins.install(StatusLinePlugin())
    box.runtime = plugins

    let renderer = TUIRenderer()
    try renderer.begin()
    host.handle(.lifecycle(.didLaunch))
    defer {
        host.handle(.lifecycle(.willTerminate))
        try? renderer.end()
    }
    while !host.wantsQuit {
        if host.needsFrame {
            let laid = host.pump(size: renderer.size)
            try renderer.present(laid)
        }
        if let event = try renderer.nextEvent(timeoutMillis: 250) {
            host.handle(event)
        }
    }
}

// Foundation-free getenv.
enum ProcessEnvLookup {
    static func isSet(_ name: String) -> Bool {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)
            return name.withCString { getenv($0) != nil }
        #else
            // Windows and other hosts: the MLIR emit toggle is unavailable.
            return false
        #endif
    }
}
