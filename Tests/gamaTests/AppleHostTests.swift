#if canImport(AppKit)
import AppKit
import GamaAppleUI
import GamaCore
import GamaDraw
import Testing

@Suite("AppKit host")
@MainActor
struct AppleHostRuntimeTests {
    private struct SmokeApp: App {
        var scenes: some Scene {
            Window("Auxiliary", id: "auxiliary") {
                Text("Must not render")
            }
            Window("Apple runtime", id: "main", role: .primary) {
                VStack {
                    Text("Apple runtime")
                    Button("Action") {}
                }
            }
        }
    }

    private struct SecondApp: App {
        var scenes: some Scene {
            Window("Second", id: "second", role: .primary) { Text("SECOND APP") }
        }
    }

    @Test("host builds, lays out, and invalidates a frame")
    func appKitHostBuildsLaysOutAndInvalidatesAFrame() throws {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        try view.install(app: SmokeApp())
        view.layoutSubtreeIfNeeded()
        view.invalidate()

        #expect(view.currentDrawList.size.width > 1)
        #expect(view.currentDrawList.size.height > 1)
        #expect(
            view.currentDrawList.commands.contains { command in
                if case .text(let text, _, _) = command {
                    return text.contains("Apple runtime")
                }
                return false
            }
        )
        #expect(
            !view.currentDrawList.commands.contains { command in
                if case .text(let text, _, _) = command {
                    return text.contains("Must not render")
                }
                return false
            }
        )
    }

    @Test("second install replaces the previous session")
    func secondInstallReplacesPreviousSession() throws {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        try view.install(app: SmokeApp())
        view.layoutSubtreeIfNeeded()
        view.invalidate()
        try view.install(app: SecondApp())
        view.invalidate()
        #expect(
            view.currentDrawList.commands.contains { command in
                if case .text(let text, _, _) = command {
                    return text.contains("SECOND APP")
                }
                return false
            }
        )
        #expect(
            !view.currentDrawList.commands.contains { command in
                if case .text(let text, _, _) = command {
                    return text.contains("Apple runtime")
                }
                return false
            }
        )
    }
}
#endif
