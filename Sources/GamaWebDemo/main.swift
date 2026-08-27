#if arch(wasm32)
import GamaCore
import GamaWASM

struct BrowserDemo: App {
    init() {}
    var scenes: some Scene {
        Window("Gama Web", id: "main", role: .primary) {
            VStack {
                Text("Gama Web").bold()
                Button("Interactive") {}
                ProgressView(value: 3, total: 4, label: "Ready")
            }
            .padding()
            .border(.rounded)
        }
    }
}

_ = try? GamaWeb.install(app: BrowserDemo())
#else
print("gama-web-demo must be built for wasm32")
#endif
