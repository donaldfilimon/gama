#if canImport(AppKit)
import AppKit
import XCTest

@testable import GamaAppleUI
import GamaCore

@MainActor
final class AppleHostRuntimeTests: XCTestCase {
    private struct SmokeApp: App {
        var content: some View {
            VStack {
                Text("Apple runtime")
                Button("Action") {}
            }
        }
    }

    func testAppKitHostBuildsLaysOutAndInvalidatesAFrame() {
        let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        view.install(app: SmokeApp())
        view.layoutSubtreeIfNeeded()
        view.invalidate()

        XCTAssertGreaterThan(view.currentDrawList.size.width, 1)
        XCTAssertGreaterThan(view.currentDrawList.size.height, 1)
        XCTAssertTrue(view.currentDrawList.commands.contains { command in
            if case .text(let text, _, _) = command { return text.contains("Apple runtime") }
            return false
        })
    }
}
#endif
