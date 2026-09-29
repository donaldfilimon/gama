#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import GamaAppleUI
import GamaCore
import GamaDraw
import GamaSwiftUI
import SwiftUI
import Testing

/// A reference-backed counter the tests mutate outside any Gama event, so a
/// post-teardown `invalidate()` has something new to render if the host were
/// still live.
private final class EmbeddingModel {
    var label = "embedded:first"
}

private struct EmbeddedApp: GamaCore.App {
    let model: EmbeddingModel

    init() { model = EmbeddingModel() }
    init(model: EmbeddingModel) { self.model = model }

    var scenes: some GamaCore.Scene {
        GamaCore.Window("Auxiliary", id: "auxiliary") {
            GamaCore.Text("embedded auxiliary must not render")
        }
        GamaCore.Window("Embedded", id: "embedded", role: .primary) {
            GamaCore.Text(model.label)
        }
    }
}

private struct PrimarylessApp: GamaCore.App {
    var scenes: some GamaCore.Scene {
        GamaCore.Window("Only auxiliary", id: "aux") { GamaCore.Text("aux") }
    }
}

private func drawListTexts(_ list: DrawList) -> [String] {
    list.commands.compactMap { command in
        if case .text(let text, _, _) = command { return text }
        return nil
    }
}

@MainActor
private func findHostView(in view: NSView) -> GamaHostView? {
    if let host = view as? GamaHostView { return host }
    for child in view.subviews {
        if let host = findHostView(in: child) { return host }
    }
    return nil
}

@MainActor
@Suite("SwiftUI embedding", .serialized)
struct SwiftUIEmbeddingTests {
    @Test("an app without a primary scene is rejected before presentation")
    func rejectsInvalidSceneGraph() {
        #expect(throws: SceneConfigurationError.noPrimaryScene) {
            _ = try GamaView(app: PrimarylessApp())
        }
        #expect(throws: SceneConfigurationError.noPrimaryScene) {
            _ = try GamaView(PrimarylessApp.self)
        }
    }

    @Test("the representable installs the primary surface into a GamaHostView")
    func representableInstallsPrimarySurface() throws {
        let view = try GamaView(app: EmbeddedApp())
        let host = view.makeHostView()
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        host.layoutSubtreeIfNeeded()
        host.invalidate()

        let texts = drawListTexts(host.currentDrawList)
        #expect(texts.contains { $0.contains("embedded:first") })
        #expect(!texts.contains { $0.contains("must not render") })
    }

    @Test("each representable instance owns an independent host")
    func eachInstanceOwnsAnIndependentHost() throws {
        let view = try GamaView(app: EmbeddedApp())
        let first = view.makeHostView()
        let second = view.makeHostView()
        #expect(first !== second)
    }

    @Test("dismantling tears the host session down")
    func dismantleTearsDownTheSession() throws {
        let model = EmbeddingModel()
        let view = try GamaView(app: EmbeddedApp(model: model))
        let host = view.makeHostView()
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        host.layoutSubtreeIfNeeded()
        host.invalidate()
        let before = drawListTexts(host.currentDrawList)
        #expect(before.contains { $0.contains("embedded:first") })

        GamaView.dismantleHostView(host)
        model.label = "embedded:after-teardown"
        host.invalidate()

        let after = drawListTexts(host.currentDrawList)
        #expect(after == before)
        #expect(!after.contains { $0.contains("after-teardown") })
    }

    @Test("NSHostingView materializes a live GamaHostView")
    func hostingViewMaterializesTheHost() throws {
        let root = try GamaView(app: EmbeddedApp())
            .frame(width: 420, height: 120)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let host = try #require(findHostView(in: hosting))
        host.layoutSubtreeIfNeeded()
        host.invalidate()
        let texts = drawListTexts(host.currentDrawList)
        #expect(texts.contains { $0.contains("embedded:first") })
        window.contentView = nil
    }
}
#endif
