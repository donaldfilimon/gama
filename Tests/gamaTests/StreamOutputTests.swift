import Testing

@testable import GamaCore
@testable import GamaDraw
@testable import GamaTUI

/// Phase 4: derivation cannot invent what was never drawn, so an author who
/// needs semantic output declares it. A chronology is event-shaped, not
/// state-shaped, so emitted lines are a channel beside the view tree rather
/// than a node inside it.
@Suite("Author-declared stream output")
struct StreamOutputTests {
    private final class Recorder: StreamSink {
        private(set) var lines: [String] = []
        func write(_ line: String) { lines.append(line) }
    }

    private struct Panel: View {
        var body: some View { Text("drawn text") }
    }

    private struct PlainApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Panel() }
        }
    }

    @Test("Emitted lines drain exactly once")
    func drainsOnce() throws {
        let host = try FrameHost(app: PlainApp())
        host.subscriptions.emit("step 1/3 building")
        host.subscriptions.emit("step 2/3 linking")
        #expect(host.subscriptions.drainStreamLines() == ["step 1/3 building", "step 2/3 linking"])
        // Exactly once: a chronology must never replay.
        #expect(host.subscriptions.drainStreamLines().isEmpty)
    }

    @Test("Emitting marks the host dirty so the line reaches a frame")
    func emittingMarksDirty() throws {
        var host = try FrameHost(app: PlainApp())
        _ = host.pump(size: Size(width: 20, height: 3))
        let clean = host.needsFrame
        #expect(clean == false)
        host.subscriptions.emit("something happened")
        let dirty = host.needsFrame
        #expect(dirty)
    }

    /// The whole point of the override: semantic text the grid never had.
    @Test("Declared lines replace derived rows for that frame")
    func declaredLinesWin() throws {
        let sink = Recorder()
        var renderer = StreamRenderer(sink: sink)
        try renderer.begin()
        try renderer.emit(["step 1/3 building"])

        let host = try FrameHost(app: PlainApp())
        var pump = HostPump(host: consume host, size: renderer.size)
        let produced = pump.advance()
        let advanced = try #require(produced)
        try renderer.present(advanced.frame)

        #expect(sink.lines == ["step 1/3 building"])
        #expect(sink.lines.contains("drawn text") == false)
    }

    @Test("With nothing declared, derivation still runs")
    func derivationIsTheDefault() throws {
        let sink = Recorder()
        var renderer = StreamRenderer(sink: sink)
        try renderer.begin()

        let host = try FrameHost(app: PlainApp())
        var pump = HostPump(host: consume host, size: renderer.size)
        let produced = pump.advance()
        let advanced = try #require(produced)
        try renderer.present(advanced.frame)

        #expect(sink.lines == ["drawn text"])
    }

    /// `runAdaptive` builds the runtime itself, so without this an author had
    /// no handle to complete or emit at all.
    @Test("An app is connected to its channel at launch")
    func appIsConnected() throws {
        let probe = ConnectionProbe()
        ConnectedApp.probe = probe
        _ = try FrameHost(app: ConnectedApp())
        #expect(probe.connected)
    }

    /// The `docs/backends/TUI.md` example, pinned: an outcome declared from
    /// `connect` must be the outcome the run ends with. `appIsConnected` only
    /// proves the hook fires; this proves the status it issues travels the
    /// whole path `runAdaptive` walks — `AppRuntime` → `run()` → `completion`
    /// — and ends an input-less stream run rather than leaving it waiting.
    /// `runAdaptive` itself is not called because it reads the real stdout
    /// and writes the message to the real stderr; `AppRuntime` is the unit.
    @Test("A completion declared from connect ends the run with that status")
    func completionFromConnectEndsTheRun() throws {
        let sink = Recorder()
        var runtime = try AppRuntime(
            app: FailsFromConnectApp(), renderer: StreamRenderer(sink: sink))

        try runtime.run()

        let recorded = runtime.completion
        let completion = try #require(recorded)
        #expect(completion == .failure(exitCode: .general, "2 targets failed"))
        #expect(completion.code == 1)
        #expect(completion.message == "2 targets failed")
        #expect(completion.isSuccess == false)
        // Completion was declared before the first frame, and the loop
        // checks completion only after presenting, so exactly one frame —
        // the one completion dirtied — must have reached the renderer.
        #expect(sink.lines == ["drawn text"])
    }

    private struct FailsFromConnectApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Panel() }
        }
        func connect(_ context: SubscriptionContext) {
            context.complete(.failure(exitCode: .general, "2 targets failed"))
        }
    }

    private final class ConnectionProbe {
        var connected = false
    }

    private struct ConnectedApp: App {
        nonisolated(unsafe) static var probe: ConnectionProbe?
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Panel() }
        }
        func connect(_ context: SubscriptionContext) {
            Self.probe?.connected = true
            context.emit("connected")
        }
    }
}
