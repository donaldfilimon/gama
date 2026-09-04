import GamaCore
import GamaEmbed
import GamaMacros

/// Built inline in the scene closure on every frame; its tap count lives in
/// the embed context's per-surface `@Reactive` store (ADR 0011). The
/// emulator gate taps it and asserts the frame changed, which is the
/// third-backend proof of that store.
@Component
private struct TapCounter {
    @Reactive var taps: Int = 0

    var body: some View {
        VStack {
            Text("Gama Android").bold()
            Text("Tapped \(taps)")
            Button("Tap") { taps += 1 }
        }
    }
}

private struct AndroidDemo: App {
    init() {}
    var scenes: some Scene {
        Window("Gama Android", id: "main", role: .primary) { TapCounter() }
    }
}

@_cdecl("gama_android_demo_v1_create")
public nonisolated func gama_android_demo_v1_create() -> UnsafeMutableRawPointer? {
    unsafe try? GamaEmbed.makeContext(app: AndroidDemo())
}
