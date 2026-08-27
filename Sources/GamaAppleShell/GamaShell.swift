#if canImport(AppKit)
import AppKit
import GamaAppleUI
import GamaCore
import GamaDraw

/// AppKit application owner for scene-first Gama applications.
@MainActor
public enum GamaShell {
    /// Validates one app instance, configures `NSApplication`, and enters the
    /// AppKit event loop. Scene validation finishes before AppKit starts.
    public static func run<A: App>(
        _ appType: A.Type
    ) throws(SceneConfigurationError) {
        let graph = try compileSceneGraph(A())
        let coordinator = GamaShellCoordinator(graph: graph, presentsWindows: true)
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        installMainMenu(on: application)
        application.delegate = coordinator
        application.run()
        withExtendedLifetime(coordinator) {}
    }

    private static func installMainMenu(on application: NSApplication) {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Gama",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        application.mainMenu = mainMenu
    }
}

package enum ShellLogicalWindowKey: Hashable {
    case singleton(SceneID)
    case group(SceneID, ScenePayload)
}

/// `WindowActions` is Sendable because it may be captured by view actions,
/// while this queue is deliberately confined to the shell's MainActor event
/// dispatch. No process-global window registry is involved.
package final class ShellCommandStore: @unchecked Sendable {
    private let singletonIDs: Set<SceneID>
    private let groupTypes: [SceneID: ObjectIdentifier]
    private var commands: [WindowCommand] = []

    package init(scenes: [CompiledSceneDescriptor]) {
        var singletons: Set<SceneID> = []
        var groups: [SceneID: ObjectIdentifier] = [:]
        for scene in scenes {
            if let payloadType = scene.payloadType {
                groups[scene.id] = payloadType
            } else {
                singletons.insert(scene.id)
            }
        }
        singletonIDs = singletons
        groupTypes = groups
    }

    package func enqueue(
        _ command: WindowCommand,
        currentInstance: WindowInstanceID
    ) -> Bool {
        switch command {
        case .openWindow(let id):
            guard singletonIDs.contains(id) else { return false }
            commands.append(command)
        case .openGroup(let id, let payload):
            guard groupTypes[id] == payload.typeID else { return false }
            commands.append(command)
        case .dismiss(let instance):
            commands.append(.dismiss(instance ?? currentInstance))
        }
        return true
    }

    package func drain() -> [WindowCommand] {
        let drained = commands
        commands.removeAll(keepingCapacity: true)
        return drained
    }
}

@MainActor
package final class GamaShellCoordinator: NSObject, NSApplicationDelegate {
    package let graph: CompiledSceneGraph
    package let commandStore: ShellCommandStore
    package let presentsWindows: Bool
    package private(set) var controllers: [WindowInstanceID: GamaShellWindowController] = [:]
    private var instancesByLogicalKey: [ShellLogicalWindowKey: WindowInstanceID] = [:]
    private var nextInstanceRawValue: UInt64 = 1
    private var didLaunch = false
    private var didTerminate = false

    package init(graph: CompiledSceneGraph, presentsWindows: Bool) {
        self.graph = graph
        self.presentsWindows = presentsWindows
        self.commandStore = ShellCommandStore(scenes: graph.scenes)
        super.init()
    }

    package var liveInstanceIDs: [WindowInstanceID] {
        controllers.keys.sorted { $0.rawValue < $1.rawValue }
    }

    package var liveSceneIDs: [SceneID] {
        liveInstanceIDs.compactMap { controllers[$0]?.sceneID }
    }

    package func beginApplication() {
        guard !didLaunch else { return }
        didLaunch = true
        graph.handleLifecycle(.didLaunch)
        for scene in graph.scenes where scene.launchBehavior == .openAtLaunch {
            _ = open(scene: scene, payload: scene.initialPayload)
        }
    }

    package func openWindow(_ id: SceneID) -> WindowInstanceID? {
        guard let scene = graph.scene(id: id), !scene.isGroup else { return nil }
        return open(scene: scene, payload: nil)
    }

    package func openWindow<Value: Hashable & Sendable>(
        group key: WindowGroupKey<Value>,
        value: Value
    ) -> WindowInstanceID? {
        guard let scene = graph.scene(id: key.id),
            scene.payloadType == ObjectIdentifier(Value.self)
        else { return nil }
        return open(scene: scene, payload: ScenePayload(value))
    }

    package func drainWindowCommands() {
        for command in commandStore.drain() {
            switch command {
            case .openWindow(let id):
                _ = openWindow(id)
            case .openGroup(let id, let payload):
                guard let scene = graph.scene(id: id),
                    scene.payloadType == payload.typeID
                else { continue }
                _ = open(scene: scene, payload: payload)
            case .dismiss(let instance):
                guard let instance else { continue }
                requestClose(instance)
            }
        }
    }

    package func requestClose(_ instance: WindowInstanceID) {
        guard let controller = controllers[instance] else { return }
        controller.deliver(
            .windowCloseRequested(scene: controller.sceneID, instance: instance)
        )
        controller.tearDown()
        controller.isClosingFromCoordinator = true
        controller.window?.close()
        if controllers[instance] != nil {
            finishClose(instance)
        }
    }

    package func finishClose(_ instance: WindowInstanceID) {
        guard let controller = controllers.removeValue(forKey: instance) else { return }
        instancesByLogicalKey = instancesByLogicalKey.filter { $0.value != instance }
        graph.handleLifecycle(
            .windowDidClose(scene: controller.sceneID, instance: instance)
        )
    }

    package func reopenPrimaryIfNeeded() {
        guard controllers.isEmpty else { return }
        _ = open(scene: graph.primary, payload: graph.primary.initialPayload)
    }

    package func emitTerminationIfNeeded() {
        guard !didTerminate else { return }
        didTerminate = true
        graph.handleLifecycle(.willTerminate)
        for controller in controllers.values {
            controller.tearDown()
        }
    }

    private func open(
        scene: CompiledSceneDescriptor,
        payload: ScenePayload?
    ) -> WindowInstanceID? {
        let logicalKey: ShellLogicalWindowKey
        if scene.isGroup {
            guard let payload, payload.typeID == scene.payloadType else { return nil }
            logicalKey = .group(scene.id, payload)
        } else {
            guard payload == nil else { return nil }
            logicalKey = .singleton(scene.id)
        }

        if let existing = instancesByLogicalKey[logicalKey],
            let controller = controllers[existing]
        {
            if presentsWindows {
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
            }
            return existing
        }

        let instance = allocateInstanceID()
        let store = commandStore
        let actions = WindowActions { command in
            store.enqueue(command, currentInstance: instance)
        }
        guard let surface = try? graph.makeSurface(
            scene: scene,
            payload: payload,
            instanceID: instance,
            actions: actions
        ) else { return nil }

        let controller = GamaShellWindowController(
            surface: surface,
            configuration: scene.configuration,
            coordinator: self
        )
        controller.hostView.afterEventDispatch = { [weak self] in
            self?.drainWindowCommands()
        }
        controllers[instance] = controller
        instancesByLogicalKey[logicalKey] = instance
        controller.deliver(.windowDidOpen(scene: scene.id, instance: instance))
        if presentsWindows {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        return instance
    }

    private func allocateInstanceID() -> WindowInstanceID {
        let result = WindowInstanceID(rawValue: nextInstanceRawValue)
        nextInstanceRawValue &+= 1
        if nextInstanceRawValue == 0 { nextInstanceRawValue = 1 }
        return result
    }

    package func applicationDidFinishLaunching(_ notification: Notification) {
        beginApplication()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    package func applicationWillBecomeActive(_ notification: Notification) {
        graph.handleLifecycle(.willEnterForeground)
    }

    package func applicationDidResignActive(_ notification: Notification) {
        graph.handleLifecycle(.didEnterBackground)
    }

    package func applicationWillTerminate(_ notification: Notification) {
        emitTerminationIfNeeded()
    }

    package func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    package func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        reopenPrimaryIfNeeded()
        return true
    }
}

@MainActor
package final class GamaShellWindowController: NSWindowController, NSWindowDelegate {
    package let sceneID: SceneID
    package let instanceID: WindowInstanceID
    package let hostView: GamaHostView
    package weak var coordinator: GamaShellCoordinator?
    package var isClosingFromCoordinator = false

    package init(
        surface: SceneSurface,
        configuration: WindowConfiguration,
        coordinator: GamaShellCoordinator
    ) {
        sceneID = surface.sceneID
        instanceID = surface.instanceID
        self.coordinator = coordinator

        let width = max(320, CGFloat(configuration.initialCellSize.width) * 9)
        let height = max(180, CGFloat(configuration.initialCellSize.height) * 18)
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if configuration.isResizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = configuration.title
        window.isReleasedWhenClosed = false
        hostView = GamaHostView(frame: window.contentView?.bounds ?? .zero)
        hostView.autoresizingMask = [.width, .height]
        hostView.install(surface: surface)
        window.contentView = hostView
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GamaShellWindowController does not support archives")
    }

    package func deliver(_ event: LifecycleEvent) {
        hostView.send(.lifecycle(event))
    }

    package func tearDown() {
        hostView.tearDown()
    }

    package func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingFromCoordinator { return true }
        coordinator?.requestClose(instanceID)
        return false
    }

    package func windowWillClose(_ notification: Notification) {
        coordinator?.finishClose(instanceID)
    }

    package func windowDidBecomeKey(_ notification: Notification) {
        deliver(.windowDidBecomeKey(scene: sceneID, instance: instanceID))
    }

    package func windowDidResignKey(_ notification: Notification) {
        deliver(.windowDidResignKey(scene: sceneID, instance: instanceID))
    }
}
#endif
