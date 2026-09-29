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

/// Demo state shared by every window: the controls the native
/// presentation maps (a checkbox, a text field, a progress bar) read and
/// write it.
private final class DemoModel {
    let showHints = Signal(true)
    let name = Signal("")
    let progress = Signal(0.4)
}

private struct DocumentView: View {
    let document: DocumentID
    let model: DemoModel

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
                Divider()
                Toggle("Show hints", isOn: model.showHints.binding())
                TextField("Your name", text: model.name.binding())
                Button("Advance progress") {
                    model.progress.update { $0 = min(1, $0 + 0.1) }
                }
                ProgressView(value: model.progress.get(), label: "Loaded")
                if model.showHints.get() {
                    Text("Close every window, then click the Dock icon to reopen the primary.")
                        .foregroundColor(.gray)
                }
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
    private let model = DemoModel()

    init() {}

    var scenes: some Scene {
        WindowGroup(
            "Gama Document",
            key: documentGroup,
            role: .primary,
            initialValue: DocumentID(rawValue: 1),
            initialCellSize: Size(width: 64, height: 26)
        ) { document in
            DocumentView(document: document, model: model)
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
    guard let hostView = controller.hostView else {
        print("error: smoke window is not a cell host")
        exit(1)
    }
    let commandCount = hostView.currentDrawList.commands.count
    guard commandCount > 0 else {
        print("error: smoke rendered an empty DrawList")
        exit(1)
    }
    coordinator.emitTerminationIfNeeded()
    print("OK — gama-apple-demo smoke: primary scene rendered \(commandCount) draw commands offscreen")
    exit(0)
}

/// Non-interactive gate for native presentation (ADR 0017): hosts the
/// primary scene offscreen in a `GamaNativeHostView` and requires a push
/// button, a checkbox, an editable text field, a progress indicator, and a
/// label among the presented AppKit views. Exits 0 only when all exist.
@MainActor
private func runAppleDemoNativeSmoke() throws(SceneConfigurationError) -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
    let graph = try compileSceneGraph(AppleDemoApp())
    let coordinator = GamaShellCoordinator(graph: graph, presentsWindows: false, presentation: .native)
    coordinator.beginApplication()
    guard let instance = coordinator.liveInstanceIDs.first,
        let host = coordinator.controllers[instance]?.nativeHostView
    else {
        print("error: native smoke opened no native primary window")
        exit(1)
    }
    func flatten(_ nodes: [PresentedNode]) -> [PresentedNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }
    var found: Set<String> = []
    for node in flatten(host.presentedTree) {
        let view = host.presentedView(for: node.id)
        switch node.kind {
        case .control(.button(let title?, _)) where (view as? NSButton)?.title == title:
            found.insert("button")
        case .control(.toggle(let title, _, _)) where (view as? NSButton)?.title == title:
            found.insert("checkbox")
        case .control(.textField) where (view as? NSTextField)?.isEditable == true:
            found.insert("text field")
        case .control(.progress) where view is NSProgressIndicator:
            found.insert("progress indicator")
        case .label(let text) where (view as? NSTextField)?.stringValue == text:
            found.insert("label")
        default:
            break
        }
    }
    let required: Set<String> = ["button", "checkbox", "text field", "progress indicator", "label"]
    let missing = required.subtracting(found).sorted()
    guard missing.isEmpty else {
        print("error: native smoke is missing \(missing.joined(separator: ", "))")
        exit(1)
    }
    coordinator.emitTerminationIfNeeded()
    print("OK — gama-apple-demo native smoke: \(required.sorted().joined(separator: ", ")) presented natively")
    exit(0)
}

if CommandLine.arguments.dropFirst().contains("--native-smoke") {
    try runAppleDemoNativeSmoke()
} else if CommandLine.arguments.dropFirst().contains("--native") {
    try GamaShell.run(AppleDemoApp.self, presentation: .native)
} else if CommandLine.arguments.dropFirst().contains("--smoke") {
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
