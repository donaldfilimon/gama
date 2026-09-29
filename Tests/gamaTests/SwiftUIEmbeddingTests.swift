#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import GamaAppleUI
import GamaCore
import GamaDraw
import GamaMacros
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

/// A per-surface `@Reactive` counter: activating it in one host must not
/// change the count another host shows.
@Component
private struct EmbeddedCounter {
    @Reactive var count: Int = 0

    var body: some GamaCore.View {
        GamaCore.Button("count \(count)") { count += 1 }
    }
}

private struct CounterApp: GamaCore.App {
    init() {}
    var scenes: some GamaCore.Scene {
        GamaCore.Window("Counter", id: "counter", role: .primary) {
            EmbeddedCounter()
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

    @Test("each materialization owns independent @Reactive state and draw list")
    func eachInstanceOwnsAnIndependentHost() throws {
        let view = try GamaView(app: CounterApp())
        let first = view.makeHostView()
        let second = view.makeHostView()
        for host in [first, second] {
            host.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
            host.layoutSubtreeIfNeeded()
            host.invalidate()
        }
        #expect(drawListTexts(first.currentDrawList).contains { $0.contains("count 0") })
        #expect(drawListTexts(second.currentDrawList).contains { $0.contains("count 0") })

        first.send(.key(.enter))
        first.invalidate()
        second.invalidate()

        let firstTexts = drawListTexts(first.currentDrawList)
        let secondTexts = drawListTexts(second.currentDrawList)
        #expect(firstTexts.contains { $0.contains("count 1") })
        #expect(secondTexts.contains { $0.contains("count 0") })
        #expect(!secondTexts.contains { $0.contains("count 1") })
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

    @Test("NSHostingView materializes a live GamaHostView and removal tears it down")
    func hostingViewMaterializesTheHost() throws {
        let model = EmbeddingModel()
        let embedded = try GamaView(app: EmbeddedApp(model: model))
        let hosting = NSHostingView(
            rootView: AnyView(embedded.frame(width: 420, height: 120))
        )
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
        let before = drawListTexts(host.currentDrawList)
        #expect(before.contains { $0.contains("embedded:first") })

        // Replacing the root removes the representable; SwiftUI dismantles it.
        hosting.rootView = AnyView(SwiftUI.EmptyView())
        hosting.layoutSubtreeIfNeeded()
        #expect(findHostView(in: hosting) == nil)

        model.label = "embedded:after-removal"
        host.invalidate()
        let after = drawListTexts(host.currentDrawList)
        #expect(after == before)
        #expect(!after.contains { $0.contains("after-removal") })
        window.contentView = nil
    }
}
#endif
