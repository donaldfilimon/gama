import GamaCore
import GamaEmbed

/// Built inline in the scene closure on every frame; its tap count lives in
/// the embed context's per-surface `@Reactive` store (ADR 0011). The
/// emulator gate taps it and asserts the frame changed, which is the
/// third-backend proof of that store.
///
/// The slot is spelled out instead of written as `@Reactive` so the Android
/// and web demos share one shape: a `GamaMacros` dependency does not build
/// under `check-wasm.sh` (its `--export=` linker flags reach the host-side
/// macro plugin link), and the Android product was kept identical rather
/// than proven separately. This is exactly the code `@Component` would
/// synthesize.
private struct TapCounter: View {
    private let _taps = ReactiveSlot(0)
    private var taps: Int { _taps.get() }

    var body: some View {
        VStack {
            Text("Gama Android").bold()
            Text("Tapped \(taps)")
            Button("Tap") { [_taps] in _taps.set(_taps.get() + 1) }
        }
    }

    func render(in context: BuildContext) -> RenderNode {
        _taps._bind(in: context, slot: 0)
        return body.render(in: context.child(0))
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
