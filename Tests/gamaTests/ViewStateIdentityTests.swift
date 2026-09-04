import GamaCore
import GamaDraw
import GamaMacros
import Testing

/// Counter constructed *inline* inside the scene closure — the shape that
/// used to lose its state on every frame.
@Component
private struct InlineCounter {
    @Reactive var count: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("count \(count)")
            Button("+1") { count += 1 }
        }
    }
}

private struct InlineCounterApp: App {
    init() {}
    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) { InlineCounter() }
    }
}

private func painted(_ laid: LaidOutNode, size: Size) -> String {
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

@Suite("View-state identity")
struct ViewStateIdentityTests {
    @Test("an inline @Reactive component keeps its state across frames")
    func inlineComponentKeepsState() throws {
        let size = Size(width: 12, height: 2)
        var host = try FrameHost(app: InlineCounterApp())
        _ = host.pump(size: size)
        host.handle(.key(.enter))
        let frame = host.pump(size: size)
        #expect(painted(frame, size: size).hasPrefix("count 1"))
        let transient = host.transientStateIDs
        #expect(transient.isEmpty)
    }
}

// MARK: - Per-surface, eviction, subscription, and diagnostics

@Component
private struct LabeledCounter {
    let label: String
    @Reactive var count: Int = 0

    var body: some View {
        Button("\(label) \(count)") { count += 1 }
    }
}

@Component
private struct NamedSlot {
    @Reactive var name: String = "x"

    var body: some View {
        Button("name \(name)") { name += "!" }
    }
}

private final class Flag {
    var on = true
}

private extension ViewStateIdentityTests {
    func first(_ laid: LaidOutNode) throws -> InteractiveRegion {
        var regions: [InteractiveRegion] = []
        laid.collectInteractive(into: &regions)
        return try #require(regions.first)
    }
}

extension ViewStateIdentityTests {
    @Test("two surfaces of one WindowGroup get independent inline state")
    func windowGroupSurfacesAreIndependent() throws {
        struct GroupApp: App {
            var scenes: some Scene {
                WindowGroup(
                    "Doc", key: WindowGroupKey<Int>("doc"), role: .primary, initialValue: 0
                ) { value in
                    LabeledCounter(label: "doc\(value)")
                }
            }
        }
        let size = Size(width: 14, height: 1)
        let graph = try compileSceneGraph(GroupApp())
        var left = FrameHost(
            surface: try graph.makeSurface(
                scene: graph.primary, payload: ScenePayload(1),
                instanceID: WindowInstanceID(rawValue: 10)))
        var right = FrameHost(
            surface: try graph.makeSurface(
                scene: graph.primary, payload: ScenePayload(2),
                instanceID: WindowInstanceID(rawValue: 11)))
        _ = left.pump(size: size)
        _ = right.pump(size: size)

        left.handle(.key(.enter))
        left.handle(.key(.enter))
        right.handle(.key(.enter))
        let leftFrame = left.pump(size: size)
        let rightFrame = right.pump(size: size)
        #expect(painted(leftFrame, size: size).hasPrefix(" doc1 2 "))
        #expect(painted(rightFrame, size: size).hasPrefix(" doc2 1 "))
        let transient = (left.transientStateIDs, right.transientStateIDs)
        #expect(transient.0.isEmpty)
        #expect(transient.1.isEmpty)
    }

    @Test("a hoisted instance rendered by two hosts still writes per surface")
    func hoistedInstanceIsPerSurface() throws {
        struct HoistedApp: App {
            let shared = LabeledCounter(label: "n")
            init() {}
            var scenes: some Scene {
                WindowGroup(
                    "Doc", key: WindowGroupKey<Int>("doc"), role: .primary, initialValue: 0
                ) { _ in shared }
            }
        }
        let size = Size(width: 14, height: 1)
        let app = HoistedApp()
        app.shared.count = 5  // pre-render local value seeds every surface
        let graph = try compileSceneGraph(app)
        var left = FrameHost(
            surface: try graph.makeSurface(
                scene: graph.primary, payload: ScenePayload(1),
                instanceID: WindowInstanceID(rawValue: 10)))
        var right = FrameHost(
            surface: try graph.makeSurface(
                scene: graph.primary, payload: ScenePayload(2),
                instanceID: WindowInstanceID(rawValue: 11)))
        _ = left.pump(size: size)
        _ = right.pump(size: size)
        // Right rendered last, so the slot currently points at right's
        // signal; left's action must still land in left's storage.
        left.handle(.key(.enter))
        let leftFrame = left.pump(size: size)
        let rightFrame = right.pump(size: size)
        #expect(painted(leftFrame, size: size).hasPrefix(" n 6 "))
        #expect(painted(rightFrame, size: size).hasPrefix(" n 5 "))
    }

    @Test("a subtree that stops rendering releases its state")
    func branchFlipEvictsState() throws {
        struct FlipApp: App {
            let flag: Flag
            init() { flag = Flag() }
            init(flag: Flag) { self.flag = flag }
            var scenes: some Scene {
                Window("Flip", id: "main", role: .primary) {
                    if flag.on {
                        LabeledCounter(label: "a")
                    } else {
                        Text("off")
                    }
                }
            }
        }
        let size = Size(width: 10, height: 1)
        let flag = Flag()
        var host = try FrameHost(app: FlipApp(flag: flag))
        _ = host.pump(size: size)
        let liveAtStart = host.reactiveStateCount
        #expect(liveAtStart == 1)
        host.handle(.key(.enter))
        _ = host.pump(size: size)

        flag.on = false
        host.invalidate()
        _ = host.pump(size: size)
        let liveAfterFlip = host.reactiveStateCount
        #expect(liveAfterFlip == 0)

        flag.on = true
        host.invalidate()
        let back = host.pump(size: size)
        // A new subtree starts from the declared default: dropped, not leaked.
        #expect(painted(back, size: size).hasPrefix(" a 0 "))
        let liveAfterReturn = host.reactiveStateCount
        #expect(liveAfterReturn == 1)
    }

    @Test("an out-of-band @Reactive write requests a frame without observe()")
    func outOfBandWriteInvalidatesHost() throws {
        struct HoistedApp: App {
            let counter = LabeledCounter(label: "n")
            init() {}
            var scenes: some Scene {
                Window("Counter", id: "main", role: .primary) { counter }
            }
        }
        let size = Size(width: 10, height: 1)
        let app = HoistedApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: size)
        let cleanAfterPump = host.needsFrame
        #expect(!cleanAfterPump)
        app.counter.count += 1
        let dirtyAfterWrite = host.needsFrame
        #expect(dirtyAfterWrite)
        let frame = host.pump(size: size)
        #expect(painted(frame, size: size).hasPrefix(" n 1 "))
    }

    @Test("transientStateIDs names a node whose state was reconstructed")
    func transientDiagnosticNamesReconstructedNode() throws {
        struct SwapApp: App {
            let flag: Flag
            init() { flag = Flag() }
            init(flag: Flag) { self.flag = flag }
            var scenes: some Scene {
                Window("Swap", id: "main", role: .primary) {
                    // Both branches render under the same explicit identity
                    // with a different slot type, so the store must replace
                    // the entry — and report it.
                    if flag.on {
                        LabeledCounter(label: "a").stateScope(NodeID(raw: 77))
                    } else {
                        NamedSlot().stateScope(NodeID(raw: 77))
                    }
                }
            }
        }
        let size = Size(width: 10, height: 1)
        let flag = Flag()
        var host = try FrameHost(app: SwapApp(flag: flag))
        _ = host.pump(size: size)
        let transientAtStart = host.transientStateIDs
        #expect(transientAtStart.isEmpty)
        flag.on = false
        host.invalidate()
        _ = host.pump(size: size)
        let transientAfterSwap = host.transientStateIDs
        let live = host.reactiveStateCount
        #expect(transientAfterSwap == [NodeID(raw: 77)])
        #expect(live == 1)
    }

    @Test("stateScope keeps state with its element across insertion")
    func stateScopeSurvivesReordering() throws {
        final class Items { var values: [Int] = [7] }
        struct ListApp: App {
            let items: Items
            init() { items = Items() }
            init(items: Items) { self.items = items }
            var scenes: some Scene {
                Window("List", id: "main", role: .primary) {
                    VStack(spacing: 0) {
                        ForEach(items.values) { item in
                            LabeledCounter(label: "i\(item)").stateScope(NodeID(raw: UInt64(item)))
                        }
                    }
                }
            }
        }
        let size = Size(width: 10, height: 2)
        let items = Items()
        var host = try FrameHost(app: ListApp(items: items))
        _ = host.pump(size: size)
        host.handle(.key(.enter))
        _ = host.pump(size: size)

        items.values.insert(3, at: 0)
        host.invalidate()
        let frame = host.pump(size: size)
        let text = painted(frame, size: size)
        #expect(text.hasPrefix(" i3 0 "))
        #expect(text.dropFirst(size.width).hasPrefix(" i7 1 "))
        let transient = host.transientStateIDs
        #expect(transient.isEmpty)
    }

    @Test("host-less rendering keeps instance-local storage")
    func hostLessRenderingStaysLocal() {
        let counter = LabeledCounter(label: "n")
        counter.count = 3
        let node = counter.render(in: BuildContext())
        #expect(node != .empty)
        #expect(counter.count == 3)
        counter.count = 4
        #expect(counter.count == 4)
    }
}
