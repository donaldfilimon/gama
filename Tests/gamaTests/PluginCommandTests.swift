import GamaCore
import GamaPlugin
import Testing

private final class CommandLogRecorder: @unchecked Sendable {
    var lines: [(PluginID, String)] = []
    func sink(_ id: PluginID, _ line: String) { lines.append((id, line)) }
}

private struct CommandPlugin: GamaPluginProtocol {
    let id: PluginID
    let commandNames: [String]
    var invalidatesOnRun = false

    var manifest: PluginManifest {
        PluginManifest(
            id: id,
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            requires: [.log]
        )
    }

    mutating func activate(in context: PluginContext) throws(PluginError) {}

    func commands() -> [PluginCommand] {
        let invalidates = invalidatesOnRun
        return commandNames.map { name in
            PluginCommand(id: CommandID(name), title: name) { context in
                context.log?.log("ran:\(name)")
                if invalidates { context.invalidate() }
            }
        }
    }
}

private struct CommandHostApp: App {
    var scenes: some Scene {
        Window("Main", id: "main", role: .primary) { Text("main") }
    }
}

private func makeRuntime(
    recorder: CommandLogRecorder,
    plugins: [PluginID],
    subscriptions: SubscriptionContext = SubscriptionContext {}
) -> PluginRuntime {
    PluginRuntime(
        grants: CapabilityGrants(
            table: Dictionary(uniqueKeysWithValues: plugins.map { ($0, Set([.log])) })),
        services: HostServices(log: { [recorder] id, line in recorder.sink(id, line) }),
        subscriptions: subscriptions
    )
}

@Suite("Plugin commands")
struct PluginCommandTests {
    @Test("registration order is deterministic: install order, then declaration order")
    func deterministicOrder() throws {
        let recorder = CommandLogRecorder()
        let runtime = makeRuntime(recorder: recorder, plugins: ["dev.a", "dev.b"])
        try runtime.install(CommandPlugin(id: "dev.a", commandNames: ["first", "second"]))
        try runtime.install(CommandPlugin(id: "dev.b", commandNames: ["third"]))

        let commands = runtime.commands
        #expect(commands.map(\.id) == ["first", "second", "third"])
        #expect(commands.map(\.plugin) == ["dev.a", "dev.a", "dev.b"])
        #expect(commands.map(\.title) == ["first", "second", "third"])
    }

    @Test("dispatch reaches the owning plugin's context")
    func dispatchReachesOwner() throws {
        let recorder = CommandLogRecorder()
        let runtime = makeRuntime(recorder: recorder, plugins: ["dev.a", "dev.b"])
        try runtime.install(CommandPlugin(id: "dev.a", commandNames: ["alpha"]))
        try runtime.install(CommandPlugin(id: "dev.b", commandNames: ["beta"]))

        let beta = try #require(runtime.commands.last)
        beta.perform()
        #expect(recorder.lines.count == 1)
        #expect(recorder.lines.first?.0 == "dev.b")
        #expect(recorder.lines.first?.1 == "ran:beta")
    }

    @Test("a command firing invalidate() dirties exactly its own host")
    func commandInvalidatesOneHost() throws {
        var hostA = try FrameHost(app: CommandHostApp())
        var hostB = try FrameHost(app: CommandHostApp())
        let recorder = CommandLogRecorder()
        let runtimeA = makeRuntime(
            recorder: recorder, plugins: ["dev.a"], subscriptions: hostA.subscriptions)
        try runtimeA.install(
            CommandPlugin(id: "dev.a", commandNames: ["refresh"], invalidatesOnRun: true))

        _ = hostA.pump(size: Size(width: 20, height: 2))
        _ = hostB.pump(size: Size(width: 20, height: 2))
        let cleanBefore = (hostA.needsFrame, hostB.needsFrame)
        #expect(!cleanBefore.0)
        #expect(!cleanBefore.1)

        try #require(runtimeA.commands.first).perform()
        let dirtyAfter = (hostA.needsFrame, hostB.needsFrame)
        #expect(dirtyAfter.0)
        #expect(!dirtyAfter.1)
    }
}
