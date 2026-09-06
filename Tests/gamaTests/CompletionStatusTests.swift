import Testing

@testable import GamaCore

/// A retained UI is state over time; a process is an event with an outcome.
/// These pin the completion contract that lets a non-interactive run know
/// when it is finished and what to exit with.
///
/// `FrameHost` is `~Copyable` and the `#expect` macro expands to generic
/// helpers constrained to `Copyable`, so every assertion binds the property
/// to a local `let` first — the shape the repo already uses for
/// `needsFrame`.
@Suite("Completion status")
struct CompletionStatusTests {
    private struct PlainApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Text("hello") }
        }
    }

    @Test("A host with no completion reports nil")
    func absentByDefault() throws {
        let host = try FrameHost(app: PlainApp())
        let completion = host.completion
        #expect(completion == nil)
    }

    @Test("Completing records the status")
    func recordsStatus() throws {
        let host = try FrameHost(app: PlainApp())
        host.subscriptions.complete(.success)
        let completion = host.completion
        #expect(completion == .success)
    }

    @Test("Failure carries its code and message")
    func failureCarriesCodeAndMessage() throws {
        let host = try FrameHost(app: PlainApp())
        host.subscriptions.complete(.failure(code: 3, "3 targets failed"))
        let recorded = host.completion
        let completion = try #require(recorded)
        #expect(completion.code == 3)
        #expect(completion.message == "3 targets failed")
        #expect(completion.isSuccess == false)
    }

    /// A late success must not be able to mask an earlier failure, so the
    /// first status wins and later calls are ignored rather than replacing it.
    @Test("A second completion does not overwrite the first")
    func firstCompletionWins() throws {
        let host = try FrameHost(app: PlainApp())
        host.subscriptions.complete(.failure(code: 1, "first"))
        host.subscriptions.complete(.success)
        let recorded = host.completion
        let completion = try #require(recorded)
        #expect(completion.code == 1)
        #expect(completion.message == "first")
    }

    /// Completion travels the existing dirty path, so a backend observes it
    /// through the frame loop it already runs and needs no new notification.
    @Test("Completing marks the host dirty")
    func completingMarksDirty() throws {
        var host = try FrameHost(app: PlainApp())
        _ = host.pump(size: Size(width: 10, height: 3))
        let cleanAfterPump = host.needsFrame
        #expect(cleanAfterPump == false)

        host.subscriptions.complete(.success)
        let dirtyAfterCompletion = host.needsFrame
        #expect(dirtyAfterCompletion)
    }

    @Test("Success is code zero with no message")
    func successShape() {
        #expect(CompletionStatus.success.code == 0)
        #expect(CompletionStatus.success.message == nil)
        #expect(CompletionStatus.success.isSuccess)
    }
}
