import Testing

@testable import GamaCore
@testable import GamaDraw
@testable import GamaTUI

/// One binary, two presentations. These pin the selection rule, the
/// non-interactive renderer's contract, and the loop's completion exit.
@Suite("Adaptive terminal surface")
struct AdaptiveSurfaceTests {

    // MARK: Selection

    @Test("A terminal selects the interactive surface")
    func ttySelectsInteractive() {
        #expect(SurfaceMode.select(isTerminal: true, arguments: ["app"]) == .interactive)
    }

    @Test("A redirected descriptor selects the stream surface")
    func pipeSelectsStream() {
        #expect(SurfaceMode.select(isTerminal: false, arguments: ["app"]) == .stream)
    }

    @Test("An explicit flag beats the descriptor in both directions")
    func overridesBeatDetection() {
        #expect(SurfaceMode.select(isTerminal: true, arguments: ["app", "--gama-plain"]) == .stream)
        #expect(SurfaceMode.select(isTerminal: false, arguments: ["app", "--gama-tui"]) == .interactive)
    }

    /// Conflicting flags follow the usual command-line rule so the meaning
    /// never depends on which flag the implementation happens to check first.
    @Test("With both flags, the last one wins")
    func lastFlagWins() {
        #expect(
            SurfaceMode.select(isTerminal: true, arguments: ["app", "--gama-tui", "--gama-plain"])
                == .stream
        )
        #expect(
            SurfaceMode.select(isTerminal: true, arguments: ["app", "--gama-plain", "--gama-tui"])
                == .interactive
        )
    }

    @Test("Unrelated arguments do not change the mode")
    func unrelatedArgumentsIgnored() {
        #expect(
            SurfaceMode.select(isTerminal: false, arguments: ["app", "--verbose", "target"])
                == .stream
        )
    }

    // MARK: Stream renderer

    private struct Panel: View {
        var body: some View { Text("step 1/3") }
    }

    private struct StreamApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Panel() }
        }
    }

    /// The non-interactive path takes no input at all, so the loop never
    /// blocks waiting for a keyboard that is not there.
    @Test("The stream renderer never produces an input event")
    func streamRendererHasNoInput() throws {
        var renderer = StreamRenderer(sink: RecordingSink())
        try renderer.begin()
        let event = try renderer.nextEvent(timeoutMillis: 0)
        #expect(event == nil)
    }

    @Test("The stream renderer emits changed rows as lines")
    func streamRendererEmitsLines() throws {
        let sink = RecordingSink()
        var renderer = StreamRenderer(sink: sink)
        try renderer.begin()

        var host = try FrameHost(app: StreamApp())
        var pump = HostPump(host: consume host, size: renderer.size)
        let produced = pump.advance()
        let advanced = try #require(produced)
        try renderer.present(advanced.frame)

        #expect(sink.lines.contains("step 1/3"))
    }

    /// A surface with no input source cannot receive a quit key, so a loop
    /// that only ended on quit-or-completion spun forever for an application
    /// that never declared one. Found by an end-to-end probe, not by a unit
    /// test driving the renderer directly.
    @Test("A run with no input and no completion still terminates")
    func inputlessRunTerminates() throws {
        let sink = RecordingSink()
        var runtime = try AppRuntime(
            app: SilentApp(),
            renderer: StreamRenderer(sink: sink),
            frameTimeoutMillis: 0
        )
        // Would not return before this change.
        try runtime.run()
        let completion = runtime.completion
        #expect(completion == nil)
        #expect(sink.lines.isEmpty == false)
    }

    @Test("An input-less renderer declares that it does not wait")
    func streamRendererDoesNotWait() {
        let renderer = StreamRenderer(sink: RecordingSink())
        #expect(renderer.waitsForInput == false)
    }

    @Test("A terminal renderer still waits for input")
    func terminalRendererWaits() {
        #expect(TUIRenderer().waitsForInput)
    }

    private struct SilentApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Text("one frame") }
        }
    }

    // MARK: Completion exits the loop

    @Test("Completion ends the run and the final frame is presented")
    func completionEndsRun() throws {
        let sink = RecordingSink()
        var runtime = try AppRuntime(
            app: CompletingApp(),
            renderer: StreamRenderer(sink: sink),
            frameTimeoutMillis: 0
        )
        runtime.complete(.failure(code: 2, "two targets failed"))
        try runtime.run()

        let completion = runtime.completion
        #expect(completion == CompletionStatus.failure(code: 2, "two targets failed"))
        #expect(sink.lines.isEmpty == false)
    }

    private struct CompletingApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Text("working") }
        }
    }
}

/// Captures lines instead of writing to the process's stdout, so the
/// renderer's behavior is provable without a terminal or a pipe.
private final class RecordingSink: StreamSink {
    private(set) var lines: [String] = []
    func write(_ line: String) { lines.append(line) }
}
