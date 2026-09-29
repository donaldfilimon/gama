#if canImport(AppKit)
public import AppKit
package import GamaAppleUI
public import GamaCore
import GamaDraw

/// How a shell window presents its Gama surface.
public enum GamaShellPresentation: Hashable, Sendable {
    /// A painted cell grid in a `GamaHostView`, sized from each scene's
    /// initial cell size. The default.
    case cells
    /// Native AppKit controls in a `GamaNativeHostView` (ADR 0017), laid
    /// out in points; the scene's initial cell size is converted with the
    /// host's probed cell size.
    case native
}

/// AppKit application owner for scene-first Gama applications.
@MainActor
public enum GamaShell {
    /// Validates one app instance, configures `NSApplication`, and enters the
    /// AppKit event loop. Scene validation finishes before AppKit starts.
    public static func run<A: App>(
        _ appType: A.Type
    ) throws(SceneConfigurationError) {
        try run(appType, presentation: .cells)
    }

    /// Like ``run(_:)``, presenting every window with `presentation`.
    public static func run<A: App>(
        _ appType: A.Type,
        presentation: GamaShellPresentation
    ) throws(SceneConfigurationError) {
        let graph = try compileSceneGraph(A())
        let coordinator = GamaShellCoordinator(
            graph: graph, presentsWindows: true, presentation: presentation)
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        installMainMenu(on: application)
        application.delegate = coordinator
        application.run()
        withExtendedLifetime(coordinator) {}
    }

    private static func installMainMenu(on application: NSApplication) {
        application.mainMenu = makeMainMenu()
    }

    /// Builds the application and View menus. The View menu's text size
    /// items have no target, so AppKit sends them down the responder chain
    /// to the key window's delegate, its `GamaShellWindowController`, which
    /// is what makes them act on the key window's host only.
    package static func makeMainMenu() -> NSMenu {
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

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let commands: [(String, Selector, String)] = [
            ("Bigger", #selector(GamaShellWindowController.makeTextBigger(_:)), "+"),
            ("Smaller", #selector(GamaShellWindowController.makeTextSmaller(_:)), "-"),
            ("Actual Size", #selector(GamaShellWindowController.makeTextActualSize(_:)), "0"),
        ]
        for (title, action, key) in commands {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = .command
            viewMenu.addItem(item)
        }
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        return mainMenu
    }
}

/// The package surface the shell drives on either host view.
@MainActor
package protocol GamaShellHostView: NSView {
    /// Installs one validated scene surface.
    func install(surface: SceneSurface)
    /// Routes one event into the installed surface.
    func send(_ event: InputEvent)
    /// Cancels the installed surface's subscriptions.
    func tearDown()
    /// Runs after each native event has been handled.
    var afterEventDispatch: (@MainActor () -> Void)? { get set }
}

extension GamaHostView: GamaShellHostView {}
extension GamaNativeHostView: GamaShellHostView {}

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
    package let presentation: GamaShellPresentation
    package private(set) var controllers: [WindowInstanceID: GamaShellWindowController] = [:]
    private var instancesByLogicalKey: [ShellLogicalWindowKey: WindowInstanceID] = [:]
    private var nextInstanceRawValue: UInt64 = 1
    private var didLaunch = false
    private var didTerminate = false

    package init(
        graph: CompiledSceneGraph,
        presentsWindows: Bool,
        presentation: GamaShellPresentation = .cells
    ) {
        self.graph = graph
        self.presentsWindows = presentsWindows
        self.presentation = presentation
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
            coordinator: self,
            presentation: presentation
        )
        controller.host.afterEventDispatch = { [weak self] in
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
    /// The window's content view, whichever presentation it uses.
    package let host: any GamaShellHostView
    package weak var coordinator: GamaShellCoordinator?
    package var isClosingFromCoordinator = false

    /// The cell host, when the window presents cells.
    package var hostView: GamaHostView? { host as? GamaHostView }
    /// The native host, when the window presents native controls.
    package var nativeHostView: GamaNativeHostView? { host as? GamaNativeHostView }

    package init(
        surface: SceneSurface,
        configuration: WindowConfiguration,
        coordinator: GamaShellCoordinator,
        presentation: GamaShellPresentation = .cells
    ) {
        sceneID = surface.sceneID
        instanceID = surface.instanceID
        self.coordinator = coordinator

        let pointsPerCell: CGSize
        let host: any GamaShellHostView
        switch presentation {
        case .cells:
            host = GamaHostView(frame: .zero)
            pointsPerCell = CGSize(width: 9, height: 18)
        case .native:
            let native = GamaNativeHostView(frame: .zero)
            host = native
            pointsPerCell = native.layoutMetrics.cellSize
        }
        let width = max(320, CGFloat(configuration.initialCellSize.width) * pointsPerCell.width)
        let height = max(180, CGFloat(configuration.initialCellSize.height) * pointsPerCell.height)
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
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        host.install(surface: surface)
        window.contentView = host
        self.host = host
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GamaShellWindowController does not support archives")
    }

    package func deliver(_ event: LifecycleEvent) {
        host.send(.lifecycle(event))
    }

    package func tearDown() {
        host.tearDown()
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

    // MARK: Text size (View menu)
    //
    // The commands step the cell host's text size. A native-presentation
    // window has no cell host, so there each command does nothing.

    /// Points one Bigger or Smaller command moves the host's text size. The
    /// host clamps the result, so a step past either end stays at the end.
    package static let textSizeStep: CGFloat = 1
    /// The size Actual Size restores: the host's own default, read from the
    /// host rather than repeated here.
    package static let actualTextSize: CGFloat = GamaHostView.defaultFontPointSize

    /// View > Bigger: one step larger on this window's host.
    @objc package func makeTextBigger(_ sender: Any?) {
        hostView?.fontPointSize += Self.textSizeStep
    }

    /// View > Smaller: one step smaller on this window's host.
    @objc package func makeTextSmaller(_ sender: Any?) {
        hostView?.fontPointSize -= Self.textSizeStep
    }

    /// View > Actual Size: restores the default text size on this window's host.
    @objc package func makeTextActualSize(_ sender: Any?) {
        hostView?.fontPointSize = Self.actualTextSize
    }
}
#endif
