import Testing

@testable import GamaCore

/// Coverage for `AppRuntime.run()` itself — the blocking loop every
/// terminal-style backend depends on and which, before this suite, had no
/// test beyond a lifecycle-ordering check.
///
/// The loop is driven by a scripted in-memory `Renderer`: it hands back a
/// fixed sequence of events, records every `present`, and counts `begin`
/// and `end`. That makes the loop's contract observable without a
/// terminal — the dirty gate, eager resize, error propagation, and
/// teardown on every exit path.
@Suite("Runtime loop")
struct RuntimeLoopTests {
    /// Observation sink shared with the value-type renderer. `AppRuntime`
    /// owns its renderer by value and is `~Copyable`, so reading state back
    /// off the renderer after `run()` is awkward; a reference recorder is
    /// the same pattern the rest of the suite uses for out-of-band capture.
    private final class Recorder {
        var presented: [LaidOutNode] = []
        var beginCount = 0
        var endCount = 0
        var steps: [String] = []
        var presentedSizes: [Size] { presented.map(\.frame.size) }
    }

    private struct ScriptedRenderer: Renderer {
        var size: Size
        let recorder: Recorder
        /// Events handed to the loop in order; `nil` models a timeout.
        /// Exhausting the script ends the run by requesting quit.
        var script: [InputEvent?]
        private var index = 0

        init(size: Size, recorder: Recorder, script: [InputEvent?]) {
            self.size = size
            self.recorder = recorder
            self.script = script
        }

        mutating func begin() { recorder.beginCount += 1 }
        mutating func end() { recorder.endCount += 1 }
        mutating func present(_ root: LaidOutNode) {
            recorder.presented.append(root)
            recorder.steps.append("present")
        }

        mutating func nextEvent(timeoutMillis: Int) -> InputEvent? {
            recorder.steps.append("wait")
            guard index < script.count else { return .key(.ctrl("q")) }
            defer { index += 1 }
            return script[index]
        }
    }

    /// Changes its drawable extent without emitting `.resize`, which the
    /// Renderer protocol permits. The recorder owns the observable frame count
    /// because AppRuntime stores the renderer by value.
    private struct SilentlyResizingRenderer: Renderer {
        let recorder: Recorder
        let changeAfterFrames: Int
        let newSize: Size
        let startSize: Size
        private var remainingIdle: Int

        var size: Size {
            recorder.presented.count >= changeAfterFrames ? newSize : startSize
        }

        init(
            startSize: Size,
            newSize: Size,
            changeAfterFrames: Int,
            idleIterations: Int,
            recorder: Recorder
        ) {
            self.startSize = startSize
            self.newSize = newSize
            self.changeAfterFrames = changeAfterFrames
            self.remainingIdle = idleIterations
            self.recorder = recorder
        }

        mutating func begin() { recorder.beginCount += 1 }
        mutating func end() { recorder.endCount += 1 }
        mutating func present(_ root: LaidOutNode) { recorder.presented.append(root) }

        mutating func nextEvent(timeoutMillis: Int) -> InputEvent? {
            guard remainingIdle > 0 else { return .key(.ctrl("q")) }
            remainingIdle -= 1
            return nil
        }
    }

    /// A renderer whose `present` fails on the Nth frame, to prove the
    /// error leaves `run()` and that teardown still happens.
    private struct FailingRenderer: Renderer {
        struct Failure: Error, Equatable { var frame: Int }

        var size = Size(width: 10, height: 3)
        let recorder: Recorder
        var failOnFrame: Int

        mutating func begin() throws(Failure) { recorder.beginCount += 1 }
        mutating func end() throws(Failure) { recorder.endCount += 1 }

        mutating func present(_ root: LaidOutNode) throws(Failure) {
            recorder.presented.append(root)
            if recorder.presented.count == failOnFrame {
                throw Failure(frame: failOnFrame)
            }
        }

        mutating func nextEvent(timeoutMillis: Int) throws(Failure) -> InputEvent? {
            nil
        }
    }

    private struct PlainApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Text("hello") }
        }
    }

    private struct InvalidatingView: View {
        typealias Body = Never_
        let signal: Signal<Int>
        var body: Never_ { Never_() }

        func render(in context: BuildContext) -> RenderNode {
            let value = signal.get()
            if value == 0 { signal.set(1) }
            return .text("frame \(value)", style: context.inheritedStyle)
        }
    }

    private struct InvalidatingApp: App {
        let signal: Signal<Int>

        init() { signal = Signal(0) }
        init(signal: Signal<Int>) { self.signal = signal }

        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { InvalidatingView(signal: signal) }
        }
    }

    @Test("begin runs once before the first frame and end runs on the way out")
    func acquiresAndReleasesTheSurface() throws {
        let recorder = Recorder()
        var runtime = try AppRuntime(
            app: PlainApp(),
            renderer: ScriptedRenderer(
                size: Size(width: 20, height: 4), recorder: recorder, script: []))

        runtime.run()

        #expect(recorder.beginCount == 1)
        #expect(recorder.endCount == 1)
        #expect(!recorder.presented.isEmpty)
    }

    @Test("the dirty gate holds: idle ticks do not produce frames")
    func idleTicksProduceNoExtraFrames() throws {
        let recorder = Recorder()
        // Six idle iterations: three explicit ticks and three timeouts.
        // `.tick` is a documented no-op in the host, so none of them may
        // produce a frame — only the initial launch frame should appear.
        var runtime = try AppRuntime(
            app: PlainApp(),
            renderer: ScriptedRenderer(
                size: Size(width: 20, height: 4),
                recorder: recorder,
                script: [.tick, nil, .tick, nil, .tick, nil]))

        runtime.run()

        #expect(recorder.presented.count == 1)
    }

    @Test("a requested follow-up frame is presented before the renderer waits")
    func followUpFrameSkipsTheInputWait() throws {
        let recorder = Recorder()
        let signal = Signal(0)
        var runtime = try AppRuntime(
            app: InvalidatingApp(signal: signal),
            renderer: ScriptedRenderer(
                size: Size(width: 20, height: 4), recorder: recorder, script: [nil]))
        runtime.observe(signal)

        runtime.run()

        #expect(Array(recorder.steps.prefix(2)) == ["present", "present"])
        #expect(recorder.presented.count == 2)
    }

    @Test("a resize inside the loop re-lays out at the new extent")
    func resizeInsideTheLoopRelaysOut() throws {
        let recorder = Recorder()
        var runtime = try AppRuntime(
            app: PlainApp(),
            renderer: ScriptedRenderer(
                size: Size(width: 20, height: 4),
                recorder: recorder,
                script: [.resize(Size(width: 44, height: 9))]))

        runtime.run()

        // Initial frame at the starting extent, then one at the new one.
        #expect(recorder.presentedSizes.count == 2)
        #expect(recorder.presentedSizes.first == Size(width: 20, height: 4))
        #expect(recorder.presentedSizes.last == Size(width: 44, height: 9))
    }

    @Test("a renderer that resizes without emitting an event still re-lays out")
    func silentRendererResizeIsPickedUp() throws {
        let recorder = Recorder()
        var runtime = try AppRuntime(
            app: PlainApp(),
            renderer: SilentlyResizingRenderer(
                startSize: Size(width: 20, height: 4),
                newSize: Size(width: 51, height: 13),
                changeAfterFrames: 1,
                idleIterations: 4,
                recorder: recorder))

        runtime.run()

        #expect(recorder.presentedSizes.first == Size(width: 20, height: 4))
        #expect(recorder.presentedSizes.last == Size(width: 51, height: 13))
        #expect(recorder.presentedSizes.count == 2)
    }

    @Test("run re-syncs to the renderer extent that begin established")
    func runResyncsToTheExtentBeginEstablished() throws {
        let recorder = Recorder()
        // Model a terminal whose real size is only known after `begin()`
        // takes it: the runtime is constructed at one extent and the
        // renderer reports another. The very first presented frame must
        // already be at the renderer's extent, not the stale one — this is
        // the post-begin re-sync in `run()`, routed through the same eager
        // resize path as any later resize rather than a special case.
        var renderer = ScriptedRenderer(
            size: Size(width: 20, height: 4), recorder: recorder, script: [])
        var runtime = try AppRuntime(app: PlainApp(), renderer: renderer)
        renderer.size = Size(width: 60, height: 15)
        runtime.renderer = renderer

        runtime.run()

        let first = try #require(recorder.presentedSizes.first)
        #expect(first == Size(width: 60, height: 15))
    }

    @Test("a renderer failure leaves run and the surface is still released")
    func rendererFailurePropagatesAndStillTearsDown() throws {
        let recorder = Recorder()
        var runtime = try AppRuntime(
            app: PlainApp(),
            renderer: FailingRenderer(recorder: recorder, failOnFrame: 1))

        var thrown: FailingRenderer.Failure?
        do {
            try runtime.run()
        } catch {
            thrown = error
        }

        #expect(thrown == FailingRenderer.Failure(frame: 1))
        // `end()` is invoked from a `defer`, so it must have run even
        // though `present` threw.
        #expect(recorder.endCount == 1)
    }

    @Test("ctrl-c ends the loop without consuming the rest of the script")
    func quitEndsTheLoopPromptly() throws {
        let recorder = Recorder()
        var runtime = try AppRuntime(
            app: PlainApp(),
            renderer: ScriptedRenderer(
                size: Size(width: 20, height: 4),
                recorder: recorder,
                script: [.key(.ctrl("c")), .resize(Size(width: 99, height: 99))]))

        runtime.run()

        // The resize after the quit key must never be handled.
        #expect(!recorder.presentedSizes.contains(Size(width: 99, height: 99)))
        #expect(recorder.endCount == 1)
    }
}
