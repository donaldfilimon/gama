import GamaCore

/// Built inline every frame with the same per-surface storage as `@Reactive`
/// (ADR 0011), without a host macro dependency in the wasm32 build.
struct WebCounter: View {
    private let count = ReactiveSlot(0)

    var body: some View {
        VStack {
            Text("Gama Web").bold()
            Text("count \(count.get())")
            Button("Interactive") { count.set(count.get() + 1) }
            ProgressView(value: 3, total: 4, label: "Ready")
        }
        .padding()
        .border(.rounded)
    }

    func render(in context: BuildContext) -> RenderNode {
        // Match @Component's expansion: bind before evaluating body, using
        // this component's identity and the count property's stable slot.
        count._bind(in: context, slot: 0)
        return body.render(in: context.child(0))
    }
}

struct BrowserDemo: App {
    init() {}
    var scenes: some Scene {
        Window("Gama Web", id: "main", role: .primary) { WebCounter() }
    }
}
