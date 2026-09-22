import GamaCore
import GamaDraw
@testable import GamaWASM
@testable import GamaWebDemo
import Testing

@Suite("Web demo state")
struct WebDemoStateTests {
    private let size = Size(width: 40, height: 12)

    private func painted(_ frame: LaidOutNode) -> String {
        var buffer = CellBuffer(size: size)
        buffer.clearBack()
        CellPainter.paint(frame, into: &buffer)
        var text = ""
        for y in 0..<size.height {
            for x in 0..<size.width {
                if let cell = buffer.cell(atX: x, y: y), !cell.isContinuation {
                    text.append(cell.character)
                }
            }
        }
        return text
    }

    @Test("the inline web counter retains Enter mutations across rebuilds")
    func inlineCounterRetainsState() throws {
        var host = try FrameHost(app: BrowserDemo())
        #expect(painted(host.pump(size: size)).contains("count 0 "))
        host.handle(.key(.enter))
        #expect(painted(host.pump(size: size)).contains("count 1 "))
        host.invalidate()
        #expect(painted(host.pump(size: size)).contains("count 1 "))
        host.handle(.key(.enter))
        #expect(painted(host.pump(size: size)).contains("count 2 "))
        let live = host.reactiveStateCount
        let transient = host.transientStateIDs
        #expect(live == 4)
        #expect(transient.isEmpty)
    }

    @Test("web counter state stays independent across WindowGroup surfaces",
          arguments: [false, true])
    func counterIsPerSurface(hoisted: Bool) throws {
        struct GroupApp: App {
            let shared = WebDemoPanel()
            var hoisted = false
            var scenes: some Scene {
                WindowGroup(
                    "Web", key: WindowGroupKey<Int>("web"), role: .primary, initialValue: 0
                ) { _ in
                    if hoisted { shared } else { WebDemoPanel() }
                }
            }
        }
        var app = GroupApp()
        app.hoisted = hoisted
        let graph = try compileSceneGraph(app)
        var left = FrameHost(surface: try graph.makeSurface(
            scene: graph.primary, payload: ScenePayload(1),
            instanceID: WindowInstanceID(rawValue: 10)))
        var right = FrameHost(surface: try graph.makeSurface(
            scene: graph.primary, payload: ScenePayload(2),
            instanceID: WindowInstanceID(rawValue: 11)))
        #expect(painted(left.pump(size: size)).contains("count 0 "))
        #expect(painted(right.pump(size: size)).contains("count 0 "))

        // Right rendered last. A shared slot must rebind to left before
        // its action runs, and an inline slot must survive reconstruction.
        left.handle(.key(.enter))
        #expect(painted(left.pump(size: size)).contains("count 1 "))
        #expect(painted(right.pump(size: size)).contains("count 0 "))
        right.handle(.key(.enter))
        right.handle(.key(.enter))
        #expect(painted(right.pump(size: size)).contains("count 2 "))
        #expect(painted(left.pump(size: size)).contains("count 1 "))
        let live = (left.reactiveStateCount, right.reactiveStateCount)
        let transient = (left.transientStateIDs, right.transientStateIDs)
        #expect(live.0 == 4 && live.1 == 4)
        #expect(transient.0.isEmpty && transient.1.isEmpty)
    }

    /// The headless driver's grid. `scripts/wasm-runtime-smoke.mjs` resizes
    /// to exactly this before reading the painted frame.
    private let headlessSize = Size(width: 40, height: 8)

    private func html(_ frame: LaidOutNode, size: Size) -> String {
        var buffer = CellBuffer(size: size)
        buffer.clearBack()
        CellPainter.paint(frame, into: &buffer)
        return HTMLSerializer.grid(from: buffer)
    }

    /// Guards the trap this demo actually fell into: the Node driver matches
    /// `/\bcount ([0-9]+)\b/` against the *raw HTML*, where every styled run
    /// is its own `<span>`. Rendering the label and the value as two `Text`s
    /// puts a tag between them and the match vanishes — and the browser
    /// driver does not notice, because it reads `textContent`, which
    /// concatenates spans. This fails in milliseconds instead of in the WASM
    /// gate. It also pins the 40x8 degradation: the count line must still be
    /// painted at the size the driver uses, not merely laid out.
    @Test("the count reads as one span at the headless driver's 40x8 grid")
    func countIsOneSpanAtHeadlessSize() throws {
        var host = try FrameHost(app: BrowserDemo())
        let first = html(host.pump(size: headlessSize), size: headlessSize)
        #expect(first.contains("count 0"))

        // Same event order as the driver: Tab moves focus off the first
        // control, then Enter activates whatever holds it. Either of the
        // first two controls takes count to exactly 1.
        host.handle(.key(.tab))
        host.handle(.key(.enter))
        let activated = html(host.pump(size: headlessSize), size: headlessSize)
        #expect(activated.contains("count 1"))
        #expect(!activated.contains("count 0"))
    }
}
