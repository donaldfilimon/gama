import GamaCore
import GamaPlugin
import Testing

private struct ToolsPlugin: GamaPluginProtocol {
    let id: PluginID
    var role: SceneRole = .auxiliary

    var manifest: PluginManifest {
        PluginManifest(id: id, version: PluginVersion(major: 1, minor: 0, patch: 0))
    }

    mutating func activate(in context: PluginContext) throws(PluginError) {}

    func scenes(in context: PluginSceneContext) -> [PluginSceneContribution] {
        let id = id
        return [
            PluginSceneContribution(
                name: "tools",
                title: "\(id.raw) Tools",
                role: role,
                initialCellSize: Size(width: 30, height: 8)
            ) { _ in
                .text("tools:\(id.raw)", style: .plain)
            }
        ]
    }
}

private struct SceneHostApp: App {
    let runtime: PluginRuntime
    init() {
        runtime = PluginRuntime(
            grants: .denyAll, services: HostServices(),
            subscriptions: SubscriptionContext {})
    }
    init(runtime: PluginRuntime) { self.runtime = runtime }

    var scenes: some Scene {
        Window("Main", id: "main", role: .primary) { Text("main") }
        PluginScenes(runtime: runtime)
    }
}

private func makeRuntime() -> PluginRuntime {
    PluginRuntime(
        grants: .denyAll,
        services: HostServices(),
        subscriptions: SubscriptionContext {}
    )
}

@Suite("Plugin scene contributions")
struct PluginSceneTests {
    @Test("contributed scene IDs are namespaced per plugin and collision-free")
    func namespacedIDs() throws {
        let runtime = makeRuntime()
        try runtime.install(ToolsPlugin(id: "dev.a"))
        try runtime.install(ToolsPlugin(id: "dev.b"))
        #expect(runtime.contributedSceneIDs == ["plugin/dev.a/tools", "plugin/dev.b/tools"])

        let graph = try compileSceneGraph(SceneHostApp(runtime: runtime))
        #expect(
            graph.scenes.map(\.id) == [
                "main", "plugin/dev.a/tools", "plugin/dev.b/tools",
            ])
    }

    @Test("a primary-role contribution is rejected with a typed error at install")
    func primaryRoleRejected() {
        let runtime = makeRuntime()
        #expect(
            throws: PluginError.primarySceneContribution("dev.a", name: "tools")
        ) {
            try runtime.install(ToolsPlugin(id: "dev.a", role: .primary))
        }
        #expect(runtime.installed.isEmpty)
        #expect(runtime.contributedSceneIDs.isEmpty)
    }

    @Test("contributed scenes collect as on-demand auxiliary windows")
    func contributionConfiguration() throws {
        let runtime = makeRuntime()
        try runtime.install(ToolsPlugin(id: "dev.a"))
        let graph = try compileSceneGraph(SceneHostApp(runtime: runtime))
        let contributed = try #require(graph.scene(id: "plugin/dev.a/tools"))
        #expect(contributed.role == .auxiliary)
        #expect(contributed.launchBehavior == .onDemand)
        #expect(contributed.configuration.title == "dev.a Tools")
        #expect(contributed.configuration.initialCellSize == Size(width: 30, height: 8))
        #expect(graph.primary.id == "main")
    }

    @Test("opening a contributed SceneID builds the plugin payload under that host")
    func contributedSurfaceRenders() throws {
        let runtime = makeRuntime()
        try runtime.install(ToolsPlugin(id: "dev.a"))
        let graph = try compileSceneGraph(SceneHostApp(runtime: runtime))
        let contributed = try #require(graph.scene(id: "plugin/dev.a/tools"))
        let surface = try graph.makeSurface(
            scene: contributed,
            payload: nil,
            instanceID: WindowInstanceID(rawValue: 7)
        )
        var host = FrameHost(surface: surface)
        #expect(host.sceneID == "plugin/dev.a/tools")
        let laid = host.pump(size: Size(width: 30, height: 8))
        guard case .text(let text, _) = laid.node else {
            Issue.record("Contributed scene did not render its payload")
            return
        }
        #expect(text == "tools:dev.a")
    }

    @Test("a duplicate app scene ID against a contributed ID fails validation")
    func duplicateAgainstContributed() throws {
        struct CollidingApp: App {
            let runtime: PluginRuntime
            init() {
                runtime = PluginRuntime(
                    grants: .denyAll, services: HostServices(),
                    subscriptions: SubscriptionContext {})
            }
            init(runtime: PluginRuntime) { self.runtime = runtime }
            var scenes: some Scene {
                Window("Main", id: "main", role: .primary) { Text("main") }
                Window("Shadow", id: "plugin/dev.a/tools") { Text("shadow") }
                PluginScenes(runtime: runtime)
            }
        }
        let runtime = makeRuntime()
        try runtime.install(ToolsPlugin(id: "dev.a"))
        #expect(throws: SceneConfigurationError.duplicateSceneID("plugin/dev.a/tools")) {
            try compileSceneGraph(CollidingApp(runtime: runtime))
        }
    }
}

#if canImport(AppKit)
    import GamaAppleShell

    @MainActor
    @Suite("Plugin scenes in the AppKit shell", .serialized)
    struct PluginSceneShellTests {
        @Test("the shell opens a contributed scene like any Window declaration")
        func shellOpensContributedScene() throws {
            let runtime = PluginRuntime(
                grants: .denyAll,
                services: HostServices(),
                subscriptions: SubscriptionContext {}
            )
            try runtime.install(ToolsPlugin(id: "dev.a"))
            let graph = try compileSceneGraph(SceneHostApp(runtime: runtime))
            let coordinator = GamaShellCoordinator(graph: graph, presentsWindows: false)
            coordinator.beginApplication()
            #expect(coordinator.liveSceneIDs == ["main"])

            let instance = coordinator.openWindow("plugin/dev.a/tools")
            #expect(instance != nil)
            #expect(coordinator.liveSceneIDs == ["main", "plugin/dev.a/tools"])

            // Reopening focuses the singleton instead of duplicating it.
            let again = coordinator.openWindow("plugin/dev.a/tools")
            #expect(again == instance)
            #expect(coordinator.liveSceneIDs == ["main", "plugin/dev.a/tools"])

            coordinator.emitTerminationIfNeeded()
        }
    }
#endif
