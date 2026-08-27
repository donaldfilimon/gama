import GamaCore
import GamaEmbed

private struct AndroidDemo: App {
    private let taps = Signal(0)
    init() {}
    var scenes: some Scene {
        Window("Gama Android", id: "main", role: .primary) {
            VStack {
                Text("Gama Android").bold()
                Text("Tapped \(taps.get())")
                Button("Tap") { taps.update { $0 += 1 } }
            }
        }
    }
}

@_cdecl("gama_android_demo_v1_create")
public nonisolated func gama_android_demo_v1_create() -> UnsafeMutableRawPointer? {
    try? GamaEmbed.makeContext(app: AndroidDemo())
}
