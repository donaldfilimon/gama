import GamaCore

struct EmbeddedExample: App {
    init() {}
    var content: some View {
        VStack {
            Text("Gama Embedded")
            ProgressView(value: 1, total: 4, label: "boot")
        }
    }
}

// A board integration supplies its renderer/event driver. The repository's
// Embedded gate compiles the unchanged portable GamaCore implementation.
