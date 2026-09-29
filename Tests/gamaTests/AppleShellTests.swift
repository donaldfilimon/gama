#if canImport(AppKit)
import AppKit
import GamaAppleShell
import GamaAppleUI
import GamaCore
import Testing

private let shellDocumentKey = WindowGroupKey<Int>("shell-document")

private struct ShellTestApp: App {
    let events: Signal<[LifecycleEvent]>

    init() { events = Signal([]) }
    init(events: Signal<[LifecycleEvent]>) { self.events = events }

    var scenes: some Scene {
        WindowGroup(
            "Document",
            key: shellDocumentKey,
            role: .primary,
            initialValue: 1,
            initialCellSize: Size(width: 32, height: 8)
        ) { value in
            Text("document:\(value)")
        }
        Window(
            "Launch Tool",
            id: "launch-tool",
            launchBehavior: .openAtLaunch,
            initialCellSize: Size(width: 24, height: 6)
        ) {
            Text("launch tool")
        }
        Window("Inspector", id: "inspector") {
            Text("inspector")
        }
    }

    func handleLifecycle(_ event: LifecycleEvent) {
        events.update { $0.append(event) }
    }
}

@MainActor
@Suite("AppKit scene shell", .serialized)
struct AppleShellTests {
    private func makeCoordinator(
        events: Signal<[LifecycleEvent]>
    ) throws -> GamaShellCoordinator {
        GamaShellCoordinator(
            graph: try compileSceneGraph(ShellTestApp(events: events)),
            presentsWindows: false
        )
    }

    @Test("launch behavior opens exactly the configured scenes")
    func launchBehavior() throws {
        let events = Signal<[LifecycleEvent]>([])
        let coordinator = try makeCoordinator(events: events)
        coordinator.beginApplication()
        coordinator.beginApplication()

        #expect(coordinator.liveSceneIDs == ["shell-document", "launch-tool"])
        #expect(events.get().filter { $0 == .didLaunch }.count == 1)
        #expect(coordinator.controllers.count == 2)
    }

    @Test("logical keys focus existing instances and isolate distinct hosts")
    func identityAndHostIsolation() throws {
        let coordinator = try makeCoordinator(events: Signal([]))
        coordinator.beginApplication()

        let first = try #require(
            coordinator.openWindow(group: shellDocumentKey, value: 1)
        )
        let repeated = try #require(
            coordinator.openWindow(group: shellDocumentKey, value: 1)
        )
        let second = try #require(
            coordinator.openWindow(group: shellDocumentKey, value: 2)
        )
        #expect(first == repeated)
        #expect(first != second)

        let firstController = try #require(coordinator.controllers[first])
        let secondController = try #require(coordinator.controllers[second])
        #expect(firstController !== secondController)
        let firstHost = try #require(firstController.hostView)
        let secondHost = try #require(secondController.hostView)
        #expect(firstHost !== secondHost)
        #expect(firstHost.currentDrawList != secondHost.currentDrawList)

        let singleton = try #require(coordinator.openWindow("inspector"))
        #expect(coordinator.openWindow("inspector") == singleton)
    }

    @Test("typed commands fail closed and drain after dispatch")
    func commandStore() throws {
        let coordinator = try makeCoordinator(events: Signal([]))
        coordinator.beginApplication()
        let current = try #require(coordinator.liveInstanceIDs.first)

        #expect(
            coordinator.commandStore.enqueue(
                .openGroup("shell-document", ScenePayload(3)),
                currentInstance: current
            )
        )
        #expect(
            !coordinator.commandStore.enqueue(
                .openGroup("shell-document", ScenePayload("wrong")),
                currentInstance: current
            )
        )
        #expect(
            !coordinator.commandStore.enqueue(
                .openWindow("unknown"),
                currentInstance: current
            )
        )
        coordinator.drainWindowCommands()
        #expect(coordinator.openWindow(group: shellDocumentKey, value: 3) != nil)

        #expect(
            coordinator.commandStore.enqueue(
                .dismiss(nil),
                currentInstance: current
            )
        )
        coordinator.drainWindowCommands()
        #expect(coordinator.controllers[current] == nil)
    }

    @Test("native delegate events are addressed and close is not vetoable")
    func delegateLifecycle() throws {
        let events = Signal<[LifecycleEvent]>([])
        let coordinator = try makeCoordinator(events: events)
        coordinator.beginApplication()
        let instance = try #require(coordinator.liveInstanceIDs.first)
        let controller = try #require(coordinator.controllers[instance])
        let window = try #require(controller.window)
        let notification = Notification(name: NSWindow.didBecomeKeyNotification, object: window)

        controller.windowDidBecomeKey(notification)
        #expect(
            events.get().contains(
                .windowDidBecomeKey(scene: controller.sceneID, instance: instance)
            )
        )
        #expect(!controller.windowShouldClose(window))
        #expect(coordinator.controllers[instance] == nil)
        #expect(
            events.get().contains(
                .windowCloseRequested(scene: controller.sceneID, instance: instance)
            )
        )
        #expect(
            events.get().contains(
                .windowDidClose(scene: controller.sceneID, instance: instance)
            )
        )
    }

    @Test("last close keeps the app resident and Dock reopen restores primary")
    func finalCloseAndReopen() throws {
        let coordinator = try makeCoordinator(events: Signal([]))
        coordinator.beginApplication()
        for instance in coordinator.liveInstanceIDs {
            coordinator.requestClose(instance)
        }
        #expect(coordinator.controllers.isEmpty)
        #expect(!coordinator.applicationShouldTerminateAfterLastWindowClosed(.shared))

        #expect(coordinator.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        #expect(coordinator.liveSceneIDs == ["shell-document"])
        let reopened = try #require(coordinator.liveInstanceIDs.first)
        #expect(reopened.rawValue > 2)
        #expect(coordinator.openWindow(group: shellDocumentKey, value: 1) == reopened)
    }

    @Test("cell presentation stays the default content view")
    func defaultPresentation() throws {
        let coordinator = try makeCoordinator(events: Signal([]))
        coordinator.beginApplication()
        let instance = try #require(coordinator.liveInstanceIDs.first)
        let controller = try #require(coordinator.controllers[instance])
        let window = try #require(controller.window)
        #expect(window.contentView is GamaHostView)
        #expect(controller.nativeHostView == nil)
    }

    @Test("native presentation hosts each window in a GamaNativeHostView sized in points")
    func nativePresentation() throws {
        let coordinator = GamaShellCoordinator(
            graph: try compileSceneGraph(ShellTestApp(events: Signal([]))),
            presentsWindows: false,
            presentation: .native
        )
        coordinator.beginApplication()
        let instance = try #require(coordinator.liveInstanceIDs.first)
        let controller = try #require(coordinator.controllers[instance])
        let window = try #require(controller.window)
        let native = try #require(window.contentView as? GamaNativeHostView)
        #expect(controller.hostView == nil)
        #expect(controller.nativeHostView === native)
        // The primary scene asks for 32x8 cells; a native window converts
        // them with the host's probed cell size, keeping the shell's minimum.
        let cell = native.layoutMetrics.cellSize
        let content = try #require(window.contentView).bounds.size
        #expect(content.width == max(320, 32 * cell.width))
        #expect(content.height == max(180, 8 * cell.height))
        #expect(native.presentedTree.contains {
            if case .label("document:1") = $0.kind { return true }
            return false
        })

        // Lifecycle still reaches the surface through the native host.
        #expect(!controller.windowShouldClose(window))
        #expect(coordinator.controllers[instance] == nil)
    }

    @Test("explicit termination emits willTerminate exactly once")
    func terminationOnce() throws {
        let events = Signal<[LifecycleEvent]>([])
        let coordinator = try makeCoordinator(events: events)
        coordinator.beginApplication()
        let notification = Notification(name: NSApplication.willTerminateNotification)
        coordinator.applicationWillTerminate(notification)
        coordinator.applicationWillTerminate(notification)
        #expect(events.get().filter { $0 == .willTerminate }.count == 1)
    }
}
#endif
