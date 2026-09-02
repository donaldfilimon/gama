import GamaCore
import GamaDraw
import GamaMacros
import Testing

@Component
private struct MacroBadge {
    let label: String
    @Reactive var count: Int = 0

    var body: some View {
        Text("\(label): \(count)").foregroundColor(#rgb("F80"))
    }
}

@Suite("Macro public surface")
struct MacroUsageTests {
    @Test("component, reactive, and RGB macros compile into core views")
    func macroSurface() {
        let badge = MacroBadge(label: "count")
        badge.count = 3
        let rendered = badge.render(in: BuildContext())
        guard case .styled(let style, let child) = rendered,
              case .text(let text, _) = child else {
            Issue.record("expected styled text render node")
            return
        }
        #expect(text == "count: 3")
        #expect(style.foreground == Color(r: 255, g: 136, b: 0))
    }
}

/// Counter whose whole state is one `@Reactive` property — the documented
/// `@State` pattern, exercised through a live host rather than a bare
/// `render(in:)` call.
@Component
private struct MacroCounter {
    @Reactive var count: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("count \(count)")
            Button("+1") { count += 1 }
        }
    }
}

/// One component instance, stored on the app and captured by the scene
/// closure. `@Reactive` state lives in the instance, and scene content is
/// rebuilt every frame, so an instance constructed *inside* the closure
/// would be replaced — along with its state — before the next frame paints.
private struct MacroCounterApp: App {
    let counter = MacroCounter()
    init() {}
    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) { counter }
    }
}

private func paintedCharacters(_ laid: LaidOutNode, size: Size) -> String {
    var buffer = CellBuffer(size: size)
    buffer.clearBack()
    CellPainter.paint(laid, into: &buffer)
    var out = ""
    for y in 0..<buffer.size.height {
        for x in 0..<buffer.size.width {
            if let cell = buffer.cell(atX: x, y: y), !cell.isContinuation {
                out.append(cell.character)
            }
        }
    }
    return out
}

@Suite("Reactive state lifetime")
struct ReactiveStateLifetimeTests {
    /// Keyboard activation must both run the focused button's action and
    /// leave the mutation visible in the next frame. Driving the pointer
    /// alone cannot catch a regression on either half of that.
    @Test("enter and space activate the focused button and the frame keeps the state")
    func keyboardActivationPersistsReactiveState() throws {
        let size = Size(width: 12, height: 2)
        let app = MacroCounterApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: size)

        host.handle(.key(.enter))
        let afterEnter = host.pump(size: size)
        #expect(app.counter.count == 1)
        #expect(paintedCharacters(afterEnter, size: size).hasPrefix("count 1"))

        host.handle(.key(.character(" ")))
        let afterSpace = host.pump(size: size)
        #expect(app.counter.count == 2)
        #expect(paintedCharacters(afterSpace, size: size).hasPrefix("count 2"))
    }

    /// The pointer path shares the action table but not the focus lookup;
    /// keep both wired so a keyboard-only or pointer-only regression fails.
    @Test("pointer press activates the same action and the frame keeps the state")
    func pointerActivationPersistsReactiveState() throws {
        let size = Size(width: 12, height: 2)
        let app = MacroCounterApp()
        var host = try FrameHost(app: app)
        let first = host.pump(size: size)
        var regions: [InteractiveRegion] = []
        first.collectInteractive(into: &regions)
        let button = try #require(regions.first)

        host.handle(
            .pointer(Point(x: button.frame.minX, y: button.frame.minY), pressed: true))
        let afterClick = host.pump(size: size)
        #expect(app.counter.count == 1)
        #expect(paintedCharacters(afterClick, size: size).hasPrefix("count 1"))
    }
}
