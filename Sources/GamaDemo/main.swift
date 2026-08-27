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

struct DemoApp: App {
    init() {}
    var content: some View {
        ZStack(alignment: .center) { CounterPanel() }
    }
}

// MARK: - Entry

let wantsMLIR =
    CommandLine.arguments.contains("--emit-mlir")
    || ProcessEnvLookup.isSet("GAMA_EMIT_MLIR")

if wantsMLIR {
    // Structural + frame-annotated lowering of the demo tree at 80×24.
    let ctx = BuildContext(id: .root)
    let ir = DemoApp().content.render(in: ctx)
    print("// ── gama dialect · structural ─────────────────────────────")
    print(GamaLowering.lower(module: ir, name: "demo"))
    let laid = LayoutEngine.layout(ir, in: Rect(x: 0, y: 0, width: 80, height: 24))
    print("// ── gama dialect · frame-annotated (80×24) ────────────────")
    print(GamaLowering.lower(laidOut: laid, name: "demo_laid"))
    print("// pipe into: mlir-opt --allow-unregistered-dialect")
} else {
    try DemoApp.main(renderer: TUIRenderer())
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

