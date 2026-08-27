import GamaCore
import Testing

@Suite("Scene graph")
struct SceneGraphTests {
    private struct OrderedApp: App {
        var scenes: some Scene {
            Window("Inspector", id: "inspector") { Text("inspector") }
            Window("Main", id: "main", role: .primary) { Text("main") }
            Window("Help", id: "help") { Text("help") }
        }
    }

    @Test("builder preserves declaration order and primary identity is explicit")
    func declarationOrderAndPrimaryIdentity() throws {
        let graph = try compileSceneGraph(OrderedApp())
        #expect(graph.scenes.map(\.id) == ["inspector", "main", "help"])
        #expect(graph.primary.id == "main")

        let surface = try graph.makePrimarySurface()
        guard case .text(let text, _) = surface.render(BuildContext()) else {
            Issue.record("Primary scene did not render its declared view")
            return
        }
        #expect(text == "main")
    }

    @Test("missing primary returns the exact error")
    func missingPrimary() {
        struct Missing: App {
            var scenes: some Scene {
                Window("Only", id: "only") { Text("only") }
            }
        }
        #expect(throws: SceneConfigurationError.noPrimaryScene) {
            try compileSceneGraph(Missing())
        }
    }

    @Test("multiple primary scenes report their declaration-order IDs")
    func multiplePrimary() {
        struct Multiple: App {
            var scenes: some Scene {
                Window("One", id: "one", role: .primary) { Text("one") }
                Window("Two", id: "two", role: .primary) { Text("two") }
            }
        }
        #expect(
            throws: SceneConfigurationError.multiplePrimaryScenes(["one", "two"])
        ) {
            try compileSceneGraph(Multiple())
        }
    }

    @Test("duplicate IDs are rejected across window kinds")
    func duplicateIDs() {
        struct Duplicate: App {
            var scenes: some Scene {
                Window("Main", id: "shared", role: .primary) { Text("main") }
                WindowGroup(
                    "Group",
                    key: WindowGroupKey<Int>("shared"),
                    initialValue: 1
                ) { Text("\($0)") }
            }
        }
        #expect(throws: SceneConfigurationError.duplicateSceneID("shared")) {
            try compileSceneGraph(Duplicate())
        }
    }

    @Test("primary group without an initial value fails validation")
    func primaryGroupRequiresInitialValue() {
        struct MissingInitial: App {
            var scenes: some Scene {
                WindowGroup(
                    "Main",
                    key: WindowGroupKey<Int>("main"),
                    role: .primary
                ) { Text("\($0)") }
            }
        }
        #expect(throws: SceneConfigurationError.missingInitialValue("main")) {
            try compileSceneGraph(MissingInitial())
        }
    }

    @Test("open-at-launch auxiliary group also requires an initial value")
    func launchGroupRequiresInitialValue() {
        struct MissingInitial: App {
            var scenes: some Scene {
                Window("Main", id: "main", role: .primary) { Text("main") }
                WindowGroup(
                    "Tools",
                    key: WindowGroupKey<String>("tools"),
                    launchBehavior: .openAtLaunch
                ) { Text($0) }
            }
        }
        #expect(throws: SceneConfigurationError.missingInitialValue("tools")) {
            try compileSceneGraph(MissingInitial())
        }
    }

    @Test("an explicit nil optional payload still counts as an initial value")
    func optionalInitialValue() throws {
        struct OptionalInitial: App {
            var scenes: some Scene {
                WindowGroup(
                    "Main",
                    key: WindowGroupKey<Int?>("main"),
                    role: .primary,
                    initialValue: nil
                ) { value in
                    Text(value.map(String.init) ?? "none")
                }
            }
        }
        let graph = try compileSceneGraph(OptionalInitial())
        let surface = try graph.makePrimarySurface()
        guard case .text(let text, _) = surface.render(BuildContext()) else {
            Issue.record("Optional payload scene did not render")
            return
        }
        #expect(text == "none")
    }

    @Test("role-derived launch defaults remain overridable")
    func launchDefaults() throws {
        struct Launches: App {
            var scenes: some Scene {
                Window("Main", id: "main", role: .primary) { Text("main") }
                Window("Aux", id: "aux") { Text("aux") }
                Window(
                    "Override",
                    id: "override",
                    launchBehavior: .openAtLaunch
                ) { Text("override") }
            }
        }
        let graph = try compileSceneGraph(Launches())
        #expect(graph.scenes.map(\.launchBehavior) == [.openAtLaunch, .onDemand, .openAtLaunch])
    }
}

private final class CommandRecorder: @unchecked Sendable {
    var commands: [WindowCommand] = []
}

@Suite("Window actions and host isolation")
struct WindowActionTests {
    @Test("typed group command preserves key and payload type")
    func typedGroupCommand() {
        let recorder = CommandRecorder()
        let actions = WindowActions { command in
            recorder.commands.append(command)
            return true
        }
        let key = WindowGroupKey<Int>("documents")
        #expect(actions.openWindow(group: key, value: 42))
        guard case .openGroup(let id, let payload) = recorder.commands.first else {
            Issue.record("Expected a typed group command")
            return
        }
        #expect(id == "documents")
        #expect(payload.value(as: Int.self) == 42)
        #expect(payload.value(as: String.self) == nil)
    }

    @Test("unsupported actions fail closed")
    func unavailableActions() {
        let actions = WindowActions.unavailable
        #expect(!actions.openWindow("inspector"))
        #expect(
            !actions.openWindow(group: WindowGroupKey<Int>("documents"), value: 1)
        )
        #expect(!actions.dismissWindow())
    }

    @Test("window context reader receives the fixed-key environment value")
    func contextReader() {
        var environment = EnvironmentValues()
        environment.windowContext = WindowContext(
            instanceID: WindowInstanceID(rawValue: 27)
        )
        let rendered = WindowContextReader { context in
            Text("instance:\(context.instanceID?.rawValue ?? 0)")
        }.render(in: BuildContext(environment: environment))
        guard case .text(let text, _) = rendered else {
            Issue.record("WindowContextReader did not render its content")
            return
        }
        #expect(text == "instance:27")
    }

    @Test("one compiled app shares model but not host-local state")
    func sharedModelIndependentHosts() throws {
        struct SharedApp: App {
            let model: Signal<Int>
            init() { model = Signal(0) }
            init(model: Signal<Int>) { self.model = model }

            var scenes: some Scene {
                WindowGroup(
                    "Document",
                    key: WindowGroupKey<Int>("document"),
                    role: .primary,
                    initialValue: 0
                ) { value in
                    Button("\(value):\(model.get())") { model.update { $0 += 1 } }
                }
            }
        }

        let model = Signal(0)
        let graph = try compileSceneGraph(SharedApp(model: model))
        let descriptor = graph.primary
        let leftSurface = try graph.makeSurface(
            scene: descriptor,
            payload: ScenePayload(1),
            instanceID: WindowInstanceID(rawValue: 10)
        )
        let rightSurface = try graph.makeSurface(
            scene: descriptor,
            payload: ScenePayload(2),
            instanceID: WindowInstanceID(rawValue: 11)
        )
        var left = FrameHost(surface: leftSurface)
        var right = FrameHost(surface: rightSurface)
        left.observe(model)
        right.observe(model)
        _ = left.pump(size: Size(width: 20, height: 2))
        _ = right.pump(size: Size(width: 20, height: 2))

        left.handle(.key(.enter))
        #expect(model.get() == 1)
        let dirtyAfterSharedChange = (left.needsFrame, right.needsFrame)
        #expect(dirtyAfterSharedChange.0)
        #expect(dirtyAfterSharedChange.1)
        #expect(left.windowInstanceID != right.windowInstanceID)

        _ = left.pump(size: Size(width: 20, height: 2))
        _ = right.pump(size: Size(width: 20, height: 2))
        left.cancelSubscriptions()
        model.set(2)
        let dirtyAfterCancel = (left.needsFrame, right.needsFrame)
        #expect(!dirtyAfterCancel.0)
        #expect(dirtyAfterCancel.1)
    }

    @Test("addressed lifecycle events dirty only their matching host")
    func addressedLifecycleIsolation() throws {
        struct AddressedApp: App {
            let events: Signal<[LifecycleEvent]>
            init() { events = Signal([]) }
            init(events: Signal<[LifecycleEvent]>) { self.events = events }

            var scenes: some Scene {
                Window("Main", id: "main", role: .primary) { Text("main") }
                Window("Inspector", id: "inspector") { Text("inspector") }
            }

            func handleLifecycle(_ event: LifecycleEvent) {
                events.update { $0.append(event) }
            }
        }

        let events = Signal<[LifecycleEvent]>([])
        let graph = try compileSceneGraph(AddressedApp(events: events))
        let mainSurface = try graph.makeSurface(
            scene: graph.primary,
            payload: nil,
            instanceID: WindowInstanceID(rawValue: 10)
        )
        let inspectorSurface = try graph.makeSurface(
            scene: graph.scenes[1],
            payload: nil,
            instanceID: WindowInstanceID(rawValue: 11)
        )
        var main = FrameHost(surface: mainSurface)
        var inspector = FrameHost(surface: inspectorSurface)
        _ = main.pump(size: Size(width: 20, height: 2))
        _ = inspector.pump(size: Size(width: 20, height: 2))

        let event = LifecycleEvent.windowDidBecomeKey(
            scene: "main",
            instance: WindowInstanceID(rawValue: 10)
        )
        inspector.handle(.lifecycle(event))
        let inspectorDirtyAfterForeignEvent = inspector.needsFrame
        #expect(!inspectorDirtyAfterForeignEvent)
        #expect(events.get().isEmpty)

        main.handle(.lifecycle(event))
        let mainDirtyAfterOwnEvent = main.needsFrame
        let inspectorDirtyAfterOwnEvent = inspector.needsFrame
        #expect(mainDirtyAfterOwnEvent)
        #expect(!inspectorDirtyAfterOwnEvent)
        #expect(events.get() == [event])
    }
}

@Suite("Lifecycle")
struct LifecycleTests {
    private struct ScriptedRenderer: Renderer {
        var size = Size(width: 20, height: 2)
        private var deliveredClose = false

        mutating func present(_ root: LaidOutNode) {}
        mutating func begin() {}
        mutating func end() {}
        mutating func nextEvent(timeoutMillis: Int) -> InputEvent? {
            guard !deliveredClose else { return nil }
            deliveredClose = true
            return .key(.ctrl("q"))
        }
    }

    private struct RuntimeLifecycleApp: App {
        let events: Signal<[LifecycleEvent]>
        init() { events = Signal([]) }
        init(events: Signal<[LifecycleEvent]>) { self.events = events }
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Text("main") }
        }
        func handleLifecycle(_ event: LifecycleEvent) {
            events.update { $0.append(event) }
        }
    }

    @Test("runtime emits launch and termination once around TUI close")
    func runtimeLifecycle() throws {
        let events = Signal<[LifecycleEvent]>([])
        var runtime = try AppRuntime(
            app: RuntimeLifecycleApp(events: events),
            renderer: ScriptedRenderer()
        )
        runtime.run()
        #expect(events.get().count == 3)
        #expect(events.get().first == .didLaunch)
        #expect(events.get().last == .willTerminate)
        guard case .windowCloseRequested(scene: "main", instance: _) = events.get()[1] else {
            Issue.record("Runtime did not synthesize the primary close request")
            return
        }
    }

    @Test("TUI close chord emits addressed close request and quits")
    func closeChord() throws {
        struct LifecycleApp: App {
            let events: Signal<[LifecycleEvent]>
            init() { events = Signal([]) }
            init(events: Signal<[LifecycleEvent]>) { self.events = events }
            var scenes: some Scene {
                Window("Main", id: "main", role: .primary) { Text("main") }
            }
            func handleLifecycle(_ event: LifecycleEvent) {
                events.update { $0.append(event) }
            }
        }

        let events = Signal<[LifecycleEvent]>([])
        var host = try FrameHost(app: LifecycleApp(events: events))
        host.handle(.key(.ctrl("c")))
        let wantsQuit = host.wantsQuit
        #expect(wantsQuit)
        #expect(
            events.get() == [
                .windowCloseRequested(
                    scene: "main",
                    instance: WindowInstanceID(rawValue: 1)
                )
            ]
        )
    }
}
