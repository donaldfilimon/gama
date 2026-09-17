import GamaAppleShell
import GamaCore

#if canImport(AppKit)

import AppKit
import GamaAppleUI
import GamaDraw

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

/// Non-interactive launch gate for the packaged bundle: boots
/// `NSApplication` without entering the event loop, hosts the primary
/// scene offscreen through the same coordinator the shell uses, and
/// requires the first pumped frame to produce a non-empty `DrawList`.
/// Exits 0 only when that render evidence exists.
@MainActor
private func runAppleDemoSmoke() throws(SceneConfigurationError) -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
    let graph = try compileSceneGraph(AppleDemoApp())
    let coordinator = GamaShellCoordinator(graph: graph, presentsWindows: false)
    coordinator.beginApplication()
    guard let instance = coordinator.liveInstanceIDs.first,
        let controller = coordinator.controllers[instance]
    else {
        print("error: smoke opened no primary window instance")
        exit(1)
    }
    let commandCount = controller.hostView.currentDrawList.commands.count
    guard commandCount > 0 else {
        print("error: smoke rendered an empty DrawList")
        exit(1)
    }
    coordinator.emitTerminationIfNeeded()
    print("OK — gama-apple-demo smoke: primary scene rendered \(commandCount) draw commands offscreen")
    exit(0)
}

if CommandLine.arguments.dropFirst().contains("--smoke") {
    try runAppleDemoSmoke()
} else if CommandLine.arguments.dropFirst().contains("--scenario") {
    // Deterministic, non-interactive profiling scenario (Scenario.swift).
    try runAppleHostScenario()
} else {
    try GamaShell.run(AppleDemoApp.self)
}

#else

print("gama-apple-demo requires macOS and AppKit")

#endif
