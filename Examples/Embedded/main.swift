import GamaCore

struct EmbeddedExample: App {
    init() {}
    var scenes: some Scene {
        Window("Gama Embedded", id: "main", role: .primary) {
            VStack {
                Text("Gama Embedded")
                ProgressView(value: 1, total: 4, label: "boot")
            }
        }
    }
}

// A board integration supplies its renderer/event driver. The repository's
// Embedded gate compiles the unchanged portable GamaCore implementation.
