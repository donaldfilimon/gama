import GamaAppleShell
import GamaCore

#if canImport(AppKit)

private struct DocumentID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: Int
    var description: String { "Document \(rawValue)" }
}

private let documentGroup = WindowGroupKey<DocumentID>("documents")
private let inspectorWindow: SceneID = "inspector"

private struct DocumentView: View {
    let document: DocumentID

    var body: some View {
        WindowContextReader { context in
            VStack(spacing: 1) {
                Text(document.description).bold().foregroundColor(.cyan)
                Text("Each payload owns an independent retained host.")
                Button("Open this payload again") {
                    _ = context.actions.openWindow(group: documentGroup, value: document)
                }
                Button("Open a different payload") {
                    _ = context.actions.openWindow(
                        group: documentGroup,
                        value: DocumentID(rawValue: document.rawValue + 1)
                    )
                }
                Button("Open inspector") {
                    _ = context.actions.openWindow(inspectorWindow)
                }
                Button("Close this window") {
                    _ = context.actions.dismissWindow()
                }
                Text("Close every window, then click the Dock icon to reopen the primary.")
                    .foregroundColor(.gray)
            }
            .padding(EdgeInsets(all: 1))
            .border(.rounded, title: document.description)
        }
    }
}

private struct InspectorView: View {
    var body: some View {
        WindowContextReader { context in
            VStack(spacing: 1) {
                Text("Inspector").bold().foregroundColor(.yellow)
                Text("This is an auxiliary singleton scene.")
                Button("Close inspector") {
                    _ = context.actions.dismissWindow()
                }
            }
            .padding(EdgeInsets(all: 1))
            .border(.rounded, title: "Inspector")
        }
    }
}

private struct AppleDemoApp: App {
    init() {}

    var scenes: some Scene {
        WindowGroup(
            "Gama Document",
            key: documentGroup,
            role: .primary,
            initialValue: DocumentID(rawValue: 1),
            initialCellSize: Size(width: 64, height: 18)
        ) { document in
            DocumentView(document: document)
        }

        Window(
            "Gama Inspector",
            id: inspectorWindow,
            initialCellSize: Size(width: 42, height: 10)
        ) {
            InspectorView()
        }
    }
}

try GamaShell.run(AppleDemoApp.self)

#else

print("gama-apple-demo requires macOS and AppKit")

#endif
