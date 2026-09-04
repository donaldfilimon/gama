#if arch(wasm32)
import GamaCore
import GamaMacros
import GamaWASM

/// Built inline in the scene closure on every frame; its count lives in the
/// browser host's per-surface `@Reactive` store (ADR 0011). The WASM runtime
/// and browser smokes require the exact `0` to `1` transition after Enter,
/// which is the second-backend proof of that store.
@Component
struct WebCounter {
    @Reactive var count: Int = 0

    var body: some View {
        VStack {
            Text("Gama Web").bold()
            Text("count \(count)")
            Button("Interactive") { count += 1 }
            ProgressView(value: 3, total: 4, label: "Ready")
        }
        .padding()
        .border(.rounded)
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
