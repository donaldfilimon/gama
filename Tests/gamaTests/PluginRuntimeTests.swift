import GamaCore
import GamaPlugin
import Testing

/// Records lifecycle strings across plugin value copies.
private final class LifecycleRecorder: @unchecked Sendable {
    var events: [String] = []
    func append(_ event: String) { events.append(event) }
}

/// Captures the context a probe was activated with, for handle checks.
private final class ContextBox: @unchecked Sendable {
    var context: PluginContext?
}

/// Records log lines per host, to prove service ownership isolation.
private final class LogRecorder: @unchecked Sendable {
    var lines: [(PluginID, String)] = []
    func sink(_ id: PluginID, _ line: String) { lines.append((id, line)) }
}

private struct ProbePlugin: GamaPluginProtocol {
    let manifest: PluginManifest
    let recorder: LifecycleRecorder
    let contextBox: ContextBox

    init(
        id: PluginID = "test.probe",
        abi: UInt32 = PluginManifest.currentABI,
        requires: [Capability] = [],
        optional: [Capability] = [],
        recorder: LifecycleRecorder = LifecycleRecorder(),
        contextBox: ContextBox = ContextBox()
    ) {
        self.manifest = PluginManifest(
            id: id,
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            abi: abi,
            requires: requires,
            optional: optional
        )
        self.recorder = recorder
        self.contextBox = contextBox
    }

    mutating func activate(in context: PluginContext) throws(PluginError) {
        contextBox.context = context
        recorder.append("activate:\(manifest.id.raw)")
    }

    mutating func deactivate() {
        recorder.append("deactivate:\(manifest.id.raw)")
    }
}

/// Observes one signal during activation, with an optional failure after the
/// observation has been registered to exercise rollback cleanup.
private struct ObservingPlugin: GamaPluginProtocol {
    let id: PluginID
    let signal: Signal<Int>
    let failAfterObserve: Bool

    var manifest: PluginManifest {
        PluginManifest(id: id, version: PluginVersion(major: 1, minor: 0, patch: 0))
    }

    mutating func activate(in context: PluginContext) throws(PluginError) {
        context.subscriptions.observe(signal)
        if failAfterObserve { throw .activationFailed(id) }
    }
}

private struct HostedApp: App {
    var scenes: some Scene {
        Window("Main", id: "main", role: .primary) { Text("main") }
    }
}

private func recordedServices(_ recorder: LogRecorder = LogRecorder()) -> HostServices {
    HostServices(
        log: { [recorder] id, line in recorder.sink(id, line) },
        clock: { 42 },
        filesystem: FilesystemProvider(
            read: { _, _ throws(PluginError) in [] },
            write: { _, _, _ throws(PluginError) in }
        )
    )
}

@Suite("Plugin runtime: manifest, grants, lifecycle")
struct PluginRuntimeTests {
    @Test("deny-by-default: denyAll refuses a nonempty requires and activates nothing")
    func denyByDefault() {
        let recorder = LifecycleRecorder()
        let runtime = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        #expect(throws: PluginError.missingRequiredCapability("test.probe", .log)) {
            try runtime.install(ProbePlugin(requires: [.log], recorder: recorder))
        }
        #expect(runtime.installed.isEmpty)
        #expect(recorder.events.isEmpty)
    }

    @Test("all-or-nothing: one missing required capability activates nothing; fixed grants succeed")
    func allOrNothing() throws {
        let recorder = LifecycleRecorder()
        let missingScope = Capability.filesystem(.read(pathPrefix: "/a"))
        let partial = CapabilityGrants(table: ["test.probe": [.log, .clock]])
        let denied = PluginRuntime(
            grants: partial,
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        let probe = ProbePlugin(
            requires: [.log, .clock, missingScope],
            recorder: recorder
        )
        #expect(throws: PluginError.missingRequiredCapability("test.probe", missingScope)) {
            try denied.install(probe)
        }
        #expect(denied.installed.isEmpty)
        #expect(recorder.events.isEmpty)

        let fixed = PluginRuntime(
            grants: CapabilityGrants(table: ["test.probe": [.log, .clock, missingScope]]),
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        try fixed.install(probe)
        #expect(fixed.installed == ["test.probe"])
        #expect(recorder.events == ["activate:test.probe"])
    }

    @Test("optional filtering: granted optionals get handles, ungranted stay nil")
    func optionalFiltering() throws {
        let contextBox = ContextBox()
        let runtime = PluginRuntime(
            grants: CapabilityGrants(table: ["test.probe": [.log, .clock]]),
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        try runtime.install(
            ProbePlugin(
                requires: [.log],
                optional: [.clock, .filesystem(.read(pathPrefix: "/a"))],
                contextBox: contextBox
            ))
        let context = try #require(contextBox.context)
        #expect(context.log != nil)
        #expect(context.clock != nil)
        #expect(context.filesystem == nil)
    }

    @Test("exact-match scoping: a /a grant does not satisfy an /a/b request")
    func exactMatchScoping() {
        let runtime = PluginRuntime(
            grants: CapabilityGrants(
                table: ["test.probe": [.filesystem(.read(pathPrefix: "/a"))]]),
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        let requested = Capability.filesystem(.read(pathPrefix: "/a/b"))
        #expect(throws: PluginError.missingRequiredCapability("test.probe", requested)) {
            try runtime.install(ProbePlugin(requires: [requested]))
        }
    }

    @Test("duplicate identities are rejected")
    func duplicates() throws {
        let runtime = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        try runtime.install(ProbePlugin())
        #expect(throws: PluginError.duplicate("test.probe")) {
            try runtime.install(ProbePlugin())
        }
        #expect(runtime.installed == ["test.probe"])
    }

    @Test("foreign ABI numbers are rejected before anything else runs")
    func abiMismatch() {
        let recorder = LifecycleRecorder()
        let runtime = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        #expect(throws: PluginError.abiMismatch(expected: 1, found: 2)) {
            try runtime.install(ProbePlugin(abi: 2, recorder: recorder))
        }
        #expect(recorder.events.isEmpty)
    }

    @Test("required capability without a backing service fails closed")
    func serviceUnavailable() {
        let runtime = PluginRuntime(
            grants: CapabilityGrants(table: ["test.probe": [.clock]]),
            services: HostServices(),
            subscriptions: SubscriptionContext {}
        )
        #expect(throws: PluginError.serviceUnavailable("test.probe", .clock)) {
            try runtime.install(ProbePlugin(requires: [.clock]))
        }
    }

    @Test("two runtimes never share services: log lines stay with their owner")
    func ownershipIsolation() throws {
        let recorderA = LogRecorder()
        let recorderB = LogRecorder()
        let contextBox = ContextBox()
        let runtimeA = PluginRuntime(
            grants: CapabilityGrants(table: ["test.probe": [.log]]),
            services: recordedServices(recorderA),
            subscriptions: SubscriptionContext {}
        )
        let runtimeB = PluginRuntime(
            grants: CapabilityGrants(table: ["test.probe": [.log]]),
            services: recordedServices(recorderB),
            subscriptions: SubscriptionContext {}
        )
        try runtimeA.install(ProbePlugin(requires: [.log], contextBox: contextBox))
        try runtimeB.install(ProbePlugin(requires: [.log]))

        let context = try #require(contextBox.context)
        context.log?.log("hello from A")
        #expect(recorderA.lines.count == 1)
        #expect(recorderA.lines.first?.0 == "test.probe")
        #expect(recorderA.lines.first?.1 == "hello from A")
        #expect(recorderB.lines.isEmpty)
    }

    @Test("dropping a runtime deactivates its plugins, mirroring SubscriptionContext")
    func deinitDeactivates() throws {
        let recorder = LifecycleRecorder()
        var runtime: PluginRuntime? = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        try runtime?.install(ProbePlugin(recorder: recorder))
        #expect(recorder.events == ["activate:test.probe"])
        runtime = nil
        #expect(recorder.events == ["activate:test.probe", "deactivate:test.probe"])
    }

    @Test("uninstall deactivates and releases exactly the named plugin")
    func uninstall() throws {
        let recorder = LifecycleRecorder()
        let runtime = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: SubscriptionContext {}
        )
        try runtime.install(ProbePlugin(id: "test.a", recorder: recorder))
        try runtime.install(ProbePlugin(id: "test.b", recorder: recorder))
        runtime.uninstall("test.a")
        #expect(runtime.installed == ["test.b"])
        #expect(recorder.events == ["activate:test.a", "activate:test.b", "deactivate:test.a"])
    }

    @Test("successful install and uninstall each invalidate the owning host")
    func lifecycleChangesInvalidateHost() throws {
        var host = try FrameHost(app: HostedApp())
        let runtime = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: host.subscriptions
        )
        _ = host.pump(size: Size(width: 20, height: 2))
        let cleanAfterInitialPump = host.needsFrame
        #expect(!cleanAfterInitialPump)

        try runtime.install(ProbePlugin())
        let dirtyAfterInstall = host.needsFrame
        #expect(dirtyAfterInstall)
        _ = host.pump(size: Size(width: 20, height: 2))
        let cleanAfterInstallPump = host.needsFrame
        #expect(!cleanAfterInstallPump)

        runtime.uninstall("test.probe")
        let dirtyAfterUninstall = host.needsFrame
        #expect(dirtyAfterUninstall)
    }

    @Test("uninstall cancels only that plugin's observations")
    func uninstallCancelsPluginObservations() throws {
        var host = try FrameHost(app: HostedApp())
        let hostSignal = Signal(0)
        let pluginSignal = Signal(0)
        host.observe(hostSignal)
        let runtime = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: host.subscriptions
        )
        _ = host.pump(size: Size(width: 20, height: 2))
        try runtime.install(
            ObservingPlugin(id: "test.observe", signal: pluginSignal, failAfterObserve: false))
        _ = host.pump(size: Size(width: 20, height: 2))

        pluginSignal.set(1)
        let dirtyAfterPluginSignal = host.needsFrame
        #expect(dirtyAfterPluginSignal)
        _ = host.pump(size: Size(width: 20, height: 2))
        runtime.uninstall("test.observe")
        _ = host.pump(size: Size(width: 20, height: 2))

        pluginSignal.set(2)
        let cleanAfterUninstalledSignal = host.needsFrame
        #expect(!cleanAfterUninstalledSignal)
        hostSignal.set(1)
        let dirtyAfterHostSignal = host.needsFrame
        #expect(dirtyAfterHostSignal)
    }

    @Test("failed activation cancels observations and leaves the host clean")
    func failedActivationCancelsObservations() throws {
        var host = try FrameHost(app: HostedApp())
        let signal = Signal(0)
        let runtime = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: host.subscriptions
        )
        _ = host.pump(size: Size(width: 20, height: 2))

        #expect(throws: PluginError.activationFailed("test.fail")) {
            try runtime.install(
                ObservingPlugin(id: "test.fail", signal: signal, failAfterObserve: true))
        }
        #expect(runtime.installed.isEmpty)
        let cleanAfterFailedActivation = host.needsFrame
        #expect(!cleanAfterFailedActivation)
        signal.set(1)
        let cleanAfterRolledBackSignal = host.needsFrame
        #expect(!cleanAfterRolledBackSignal)
    }

    @Test("plugin invalidation dirties exactly the host its runtime was built with")
    func invalidationTargetsOneHost() throws {
        var hostA = try FrameHost(app: HostedApp())
        var hostB = try FrameHost(app: HostedApp())
        let contextBox = ContextBox()
        let runtimeA = PluginRuntime(
            grants: .denyAll,
            services: recordedServices(),
            subscriptions: hostA.subscriptions
        )
        try runtimeA.install(ProbePlugin(contextBox: contextBox))

        _ = hostA.pump(size: Size(width: 20, height: 2))
        _ = hostB.pump(size: Size(width: 20, height: 2))
        let cleanBefore = (hostA.needsFrame, hostB.needsFrame)
        #expect(!cleanBefore.0)
        #expect(!cleanBefore.1)

        let context = try #require(contextBox.context)
        context.invalidate()
        let dirtyAfter = (hostA.needsFrame, hostB.needsFrame)
        #expect(dirtyAfter.0)
        #expect(!dirtyAfter.1)
    }
}
