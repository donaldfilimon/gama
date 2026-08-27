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
        var content: some View {
            VStack {
                Text("Apple runtime")
                Button("Action") {}
            }
        }
    }

    @Test("host builds, lays out, and invalidates a frame")
    func appKitHostBuildsLaysOutAndInvalidatesAFrame() {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        view.install(app: SmokeApp())
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
    }
}
#endif
