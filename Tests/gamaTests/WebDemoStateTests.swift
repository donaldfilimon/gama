import GamaCore
import GamaDraw
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
        #expect(live == 1)
        #expect(transient.isEmpty)
    }

    @Test("web counter state stays independent across WindowGroup surfaces",
          arguments: [false, true])
    func counterIsPerSurface(hoisted: Bool) throws {
        struct GroupApp: App {
            let shared = WebCounter()
            var hoisted = false
            var scenes: some Scene {
                WindowGroup(
                    "Web", key: WindowGroupKey<Int>("web"), role: .primary, initialValue: 0
                ) { _ in
                    if hoisted { shared } else { WebCounter() }
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
        #expect(live.0 == 1 && live.1 == 1)
        #expect(transient.0.isEmpty && transient.1.isEmpty)
    }
}
