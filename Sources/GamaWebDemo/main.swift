#if arch(wasm32)
import GamaCore
import GamaWASM

/// Built inline in the scene closure on every frame; its count lives in the
/// browser host's per-surface `@Reactive` store (ADR 0011). The WASM runtime
/// and browser smokes press the button and assert the next frame paints the
/// incremented count, which is the second-backend proof of that store.
///
/// The slot is spelled out instead of written as `@Reactive` because a
/// `GamaMacros` dependency does not build under `check-wasm.sh`: the
/// `--export=gama_web_*` linker flags the gate passes for the reactor apply
/// to every link step, including the host-side `GamaMacrosImpl` plugin, and
/// the macOS linker rejects them. This is exactly the code `@Component`
/// would synthesize.
struct WebCounter: View {
    private let _count = ReactiveSlot(0)
    private var count: Int { _count.get() }

    var body: some View {
        VStack {
            Text("Gama Web").bold()
            Text("count \(count)")
            Button("Interactive") { [_count] in _count.set(_count.get() + 1) }
            ProgressView(value: 3, total: 4, label: "Ready")
        }
        .padding()
        .border(.rounded)
    }

    func render(in context: BuildContext) -> RenderNode {
        _count._bind(in: context, slot: 0)
        return body.render(in: context.child(0))
    }
}

struct BrowserDemo: App {
    init() {}
    var scenes: some Scene {
        Window("Gama Web", id: "main", role: .primary) { WebCounter() }
    }
}

_ = try? GamaWeb.install(app: BrowserDemo())
#else
print("gama-web-demo must be built for wasm32")
#endif
