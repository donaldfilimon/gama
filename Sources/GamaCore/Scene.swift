//  Scene.swift — GamaCore
//  Declarative application surfaces and the package-private compilation
//  model shared by shell and single-surface backends.

/// Stable application-defined identity for a scene declaration.
public struct SceneID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The application-stable string that identifies the scene.
    public let rawValue: String

    /// Creates an identity from its raw string representation.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identity from an application-defined string.
    public init(_ rawValue: String) { self.rawValue = rawValue }
    /// Creates an identity from a string literal.
    public init(stringLiteral value: String) { self.rawValue = value }
}

/// Stable identity for a typed ``WindowGroup`` declaration.
public struct WindowGroupKey<Value: Hashable & Sendable>: Hashable, Sendable {
    /// The scene identity shared by the declaration and typed open commands.
    public let id: SceneID

    /// Creates a key for the group with the given scene identity.
    public init(_ id: SceneID) { self.id = id }
}

/// Runtime-generated identity for one live window or other surface.
public struct WindowInstanceID: RawRepresentable, Hashable, Sendable {
    /// The shell-generated numeric identity of the live surface.
    public let rawValue: UInt64

    /// Creates an instance identity from its raw numeric representation.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Whether a scene is the portable primary surface or an auxiliary surface.
public enum SceneRole: Hashable, Sendable {
    /// The single portable scene used by backends that own one surface.
    case primary
    /// A scene available in window-capable shells but not selected as primary.
    case auxiliary
}

/// Whether a shell should create a scene during application launch.
public enum SceneLaunchBehavior: Hashable, Sendable {
    /// The shell creates an instance when the application launches.
    case openAtLaunch
    /// The shell waits for an explicit window action before creating an instance.
    case onDemand
}

/// Native-window preferences expressed in Gama's cell coordinate system.
public struct WindowConfiguration: Hashable, Sendable {
    /// User-visible native-window title.
    public var title: String
    /// Initial drawable extent expressed in Gama cells.
    public var initialCellSize: Size
    /// Whether the owning shell should permit native resizing.
    public var isResizable: Bool

    /// Creates the native-window preferences for a scene.
    public init(
        title: String,
        initialCellSize: Size = Size(width: 100, height: 30),
        isResizable: Bool = true
    ) {
        self.title = title
        self.initialCellSize = initialCellSize
        self.isResizable = isResizable
    }
}

/// A declarative application surface. Gama's public scene vocabulary is
/// intentionally closed in practice to the types emitted by ``SceneBuilder``;
/// compilation stays package-private and never exposes erased payloads.
public protocol Scene {
    /// Internal builder hook. The collector's erased representation remains
    /// package-private; scene values only append their declarations.
    func _collectScenes(into collector: inout _SceneCollector) throws(
        SceneConfigurationError)
}

/// Opaque collector threaded through scene-builder output. Its storage and
/// compilation operations are package-private.
public struct _SceneCollector {
    package var descriptors: [CompiledSceneDescriptor] = []
    package init() {}
}

/// An empty scene-list element.
public struct EmptyScene: Scene {
    /// Creates an empty element, normally through an empty builder branch.
    public init() {}
    public func _collectScenes(into collector: inout _SceneCollector) {}
}

/// A fixed-arity scene list produced by ``SceneBuilder``.
public struct TupleScene<each S: Scene>: Scene {
    package let content: (repeat each S)

    package init(_ content: repeat each S) {
        self.content = (repeat each content)
    }

    public func _collectScenes(into collector: inout _SceneCollector) throws(
        SceneConfigurationError
    ) {
        for scene in repeat each content {
            try scene._collectScenes(into: &collector)
        }
    }
}

/// Either branch produced by conditional scene declarations.
public enum ConditionalScene<First: Scene, Second: Scene>: Scene {
    /// The scene list produced by the builder's first branch.
    case first(First)
    /// The scene list produced by the builder's second branch.
    case second(Second)

    public func _collectScenes(into collector: inout _SceneCollector) throws(
        SceneConfigurationError
    ) {
        switch self {
        case .first(let first): try first._collectScenes(into: &collector)
        case .second(let second): try second._collectScenes(into: &collector)
        }
    }
}

/// Result builder used by ``App/scenes``.
@resultBuilder
public enum SceneBuilder {
    /// Builds an empty scene list.
    public static func buildBlock() -> EmptyScene { EmptyScene() }
    /// Passes one scene declaration through without wrapping it.
    public static func buildBlock<S: Scene>(_ scene: S) -> S { scene }
    /// Collects multiple scene declarations in source order.
    public static func buildBlock<each S: Scene>(
        _ scene: repeat each S
    ) -> TupleScene<repeat each S> {
        TupleScene(repeat each scene)
    }
    /// Represents an `if` declaration whose scene may be absent.
    public static func buildOptional<S: Scene>(
        _ scene: S?
    ) -> ConditionalScene<S, EmptyScene> {
        scene.map(ConditionalScene.first) ?? .second(EmptyScene())
    }
    /// Builds the first branch of an `if`/`else` declaration.
    public static func buildEither<First: Scene, Second: Scene>(
        first: First
    ) -> ConditionalScene<First, Second> {
        .first(first)
    }
    /// Builds the second branch of an `if`/`else` declaration.
    public static func buildEither<First: Scene, Second: Scene>(
        second: Second
    ) -> ConditionalScene<First, Second> {
        .second(second)
    }
    /// Passes a scene expression into the builder.
    public static func buildExpression<S: Scene>(_ scene: S) -> S { scene }
}

/// A singleton window declaration. Reopening it focuses its existing live
/// instance rather than creating a duplicate.
public struct Window<Content: View>: Scene {
    /// Stable identity used to open or focus this singleton scene.
    public let id: SceneID
    /// Whether this scene is the application's primary or an auxiliary scene.
    public let role: SceneRole
    /// Whether a shell opens this scene during launch or on demand.
    public let launchBehavior: SceneLaunchBehavior
    /// Native-window preferences for shell-owned instances.
    public let configuration: WindowConfiguration
    package let content: () -> Content

    /// Declares a singleton scene and its view-building closure.
    public init(
        _ title: String,
        id: SceneID,
        role: SceneRole = .auxiliary,
        launchBehavior: SceneLaunchBehavior? = nil,
        initialCellSize: Size = Size(width: 100, height: 30),
        isResizable: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.role = role
        self.launchBehavior = launchBehavior
            ?? (role == .primary ? .openAtLaunch : .onDemand)
        self.configuration = WindowConfiguration(
            title: title,
            initialCellSize: initialCellSize,
            isResizable: isResizable
        )
        self.content = content
    }

    public func _collectScenes(into collector: inout _SceneCollector) {
        let content = content
        collector.descriptors.append(
            CompiledSceneDescriptor(
                id: id,
                role: role,
                launchBehavior: launchBehavior,
                configuration: configuration,
                payloadType: nil,
                initialPayload: nil,
                makeRender: { payload in
                    guard payload == nil else { return nil }
                    return { context in content().render(in: context) }
                }
            ))
    }
}

private enum InitialGroupValue<Value: Hashable & Sendable>: Sendable {
    case absent
    case value(Value)
}

/// A payload-addressed window declaration. A typed key prevents callers from
/// opening the group with a value of the wrong type.
public struct WindowGroup<Value: Hashable & Sendable, Content: View>: Scene {
    /// Typed identity used to open or focus a payload-addressed instance.
    public let key: WindowGroupKey<Value>
    /// Whether this group is the application's primary or an auxiliary scene.
    public let role: SceneRole
    /// Whether a shell opens an initial group value at launch or waits on demand.
    public let launchBehavior: SceneLaunchBehavior
    /// Native-window preferences shared by instances of this group.
    public let configuration: WindowConfiguration
    private let initial: InitialGroupValue<Value>
    package let content: (Value) -> Content

    /// Declares an on-demand group without an initial payload.
    public init(
        _ title: String,
        key: WindowGroupKey<Value>,
        role: SceneRole = .auxiliary,
        launchBehavior: SceneLaunchBehavior? = nil,
        initialCellSize: Size = Size(width: 100, height: 30),
        isResizable: Bool = true,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.key = key
        self.role = role
        self.launchBehavior = launchBehavior
            ?? (role == .primary ? .openAtLaunch : .onDemand)
        self.configuration = WindowConfiguration(
            title: title,
            initialCellSize: initialCellSize,
            isResizable: isResizable
        )
        self.initial = .absent
        self.content = content
    }

    /// Declares a group with the initial payload required for a primary or
    /// launch-at-start group.
    public init(
        _ title: String,
        key: WindowGroupKey<Value>,
        role: SceneRole = .auxiliary,
        launchBehavior: SceneLaunchBehavior? = nil,
        initialValue: Value,
        initialCellSize: Size = Size(width: 100, height: 30),
        isResizable: Bool = true,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.key = key
        self.role = role
        self.launchBehavior = launchBehavior
            ?? (role == .primary ? .openAtLaunch : .onDemand)
        self.configuration = WindowConfiguration(
            title: title,
            initialCellSize: initialCellSize,
            isResizable: isResizable
        )
        self.initial = .value(initialValue)
        self.content = content
    }

    public func _collectScenes(into collector: inout _SceneCollector) {
        let initialPayload: ScenePayload?
        switch initial {
        case .absent: initialPayload = nil
        case .value(let value): initialPayload = ScenePayload(value)
        }
        let content = content
        collector.descriptors.append(
            CompiledSceneDescriptor(
                id: key.id,
                role: role,
                launchBehavior: launchBehavior,
                configuration: configuration,
                payloadType: ObjectIdentifier(Value.self),
                initialPayload: initialPayload,
                makeRender: { payload in
                    guard let value = payload?.value(as: Value.self) else { return nil }
                    return { context in content(value).render(in: context) }
                }
            ))
    }
}

/// Validation failures discovered before any backend begins running.
public enum SceneConfigurationError: Error, Hashable, Sendable {
    /// The declaration contains no scene marked as primary.
    case noPrimaryScene
    /// More than one scene is primary; the associated IDs retain source order.
    case multiplePrimaryScenes([SceneID])
    /// Two static windows or groups use the same stable identity.
    case duplicateSceneID(SceneID)
    /// A primary or launch-at-start group has no initial payload.
    case missingInitialValue(SceneID)
    /// Package-private erasure received a payload of the wrong declared type.
    case internalTypeMismatch(SceneID?)
}

/// Portable lifecycle events delivered through ``InputEvent/lifecycle(_:)``.
public enum LifecycleEvent: Hashable, Sendable {
    /// The application finished its portable launch sequence.
    case didLaunch
    /// The application is about to become foreground-active.
    case willEnterForeground
    /// The application moved into the background.
    case didEnterBackground
    /// The application is about to terminate explicitly.
    case willTerminate
    /// A shell opened a live instance of the identified scene.
    case windowDidOpen(scene: SceneID, instance: WindowInstanceID)
    /// A host or user requested that the identified instance close.
    case windowCloseRequested(scene: SceneID, instance: WindowInstanceID)
    /// The identified instance finished closing.
    case windowDidClose(scene: SceneID, instance: WindowInstanceID)
    /// The identified instance became its shell's key window.
    case windowDidBecomeKey(scene: SceneID, instance: WindowInstanceID)
    /// The identified instance resigned key-window status.
    case windowDidResignKey(scene: SceneID, instance: WindowInstanceID)
}

extension LifecycleEvent {
    package var windowTarget: (scene: SceneID, instance: WindowInstanceID)? {
        switch self {
        case .windowDidOpen(let scene, let instance),
            .windowCloseRequested(let scene, let instance),
            .windowDidClose(let scene, let instance),
            .windowDidBecomeKey(let scene, let instance),
            .windowDidResignKey(let scene, let instance):
            return (scene, instance)
        case .didLaunch, .willEnterForeground, .didEnterBackground, .willTerminate:
            return nil
        }
    }
}

// MARK: - Window environment capability

private final class ScenePayloadBox<Value: Hashable & Sendable>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

package struct ScenePayload: @unchecked Sendable, Hashable {
    package let typeID: ObjectIdentifier
    private let hashCode: Int
    private let copyValue: @Sendable (UnsafeMutableRawPointer) -> Void
    private let equalsValue: @Sendable (ScenePayload) -> Bool

    package init<Value: Hashable & Sendable>(_ value: Value) {
        let box = ScenePayloadBox(value)
        var hasher = Hasher()
        value.hash(into: &hasher)
        self.typeID = ObjectIdentifier(Value.self)
        self.hashCode = hasher.finalize()
        self.copyValue = { output in
            output.assumingMemoryBound(to: Value.self).initialize(to: box.value)
        }
        self.equalsValue = { other in
            other.value(as: Value.self) == box.value
        }
    }

    package func value<Value: Hashable & Sendable>(as type: Value.Type) -> Value? {
        guard typeID == ObjectIdentifier(Value.self) else { return nil }
        let output = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        copyValue(UnsafeMutableRawPointer(output))
        let value = output.move()
        output.deallocate()
        return value
    }

    package static func == (lhs: ScenePayload, rhs: ScenePayload) -> Bool {
        lhs.typeID == rhs.typeID && lhs.equalsValue(rhs)
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(typeID)
        hasher.combine(hashCode)
    }
}

package enum WindowCommand: Sendable {
    case openWindow(SceneID)
    case openGroup(SceneID, ScenePayload)
    case dismiss(WindowInstanceID?)
}

/// Window operations supplied by a shell. Single-surface hosts use
/// ``unavailable``, whose operations return `false` without affecting render.
public struct WindowActions: Sendable {
    private let enqueue: @Sendable (WindowCommand) -> Bool

    package init(enqueue: @escaping @Sendable (WindowCommand) -> Bool) {
        self.enqueue = enqueue
    }

    /// Actions for a backend without window ownership; every operation returns
    /// `false` without changing render state.
    public static var unavailable: WindowActions {
        WindowActions { _ in false }
    }

    /// Requests that a singleton scene open, or focus its existing instance.
    /// - Returns: `true` when the current backend accepted the command.
    public func openWindow(_ id: SceneID) -> Bool {
        enqueue(.openWindow(id))
    }

    /// Requests that a typed group value open, or focus its existing instance.
    /// - Returns: `true` when the current backend accepted the command.
    public func openWindow<Value: Hashable & Sendable>(
        group: WindowGroupKey<Value>,
        value: Value
    ) -> Bool {
        enqueue(.openGroup(group.id, ScenePayload(value)))
    }

    /// Requests dismissal of an explicit instance, or the current instance
    /// when `instance` is `nil`.
    /// - Returns: `true` when the current backend accepted the command.
    public func dismissWindow(_ instance: WindowInstanceID? = nil) -> Bool {
        enqueue(.dismiss(instance))
    }
}

/// The current surface identity and its window operations.
public struct WindowContext: Sendable {
    /// Identity of the current live surface, or `nil` outside a live surface.
    public var instanceID: WindowInstanceID?
    /// Window operations supplied by the current backend.
    public var actions: WindowActions

    /// Creates a fixed-key window environment value.
    public init(
        instanceID: WindowInstanceID? = nil,
        actions: WindowActions = .unavailable
    ) {
        self.instanceID = instanceID
        self.actions = actions
    }
}

/// Reads the fixed-key window context while building ordinary view content.
public struct WindowContextReader<Content: View>: View {
    /// Terminates body recursion because this primitive renders directly.
    public typealias Body = Never_
    /// Unused primitive body required by ``View``.
    public var body: Never_ { Never_() }
    private let content: (WindowContext) -> Content

    /// Creates a reader whose closure receives the current window context.
    public init(@ViewBuilder content: @escaping (WindowContext) -> Content) {
        self.content = content
    }

    /// Builds the reader's content with the window context from the environment.
    public func render(in context: BuildContext) -> RenderNode {
        content(context.environment.windowContext).render(in: context.child(0))
    }
}

// MARK: - Package-private scene compilation

package struct CompiledSceneDescriptor {
    package let id: SceneID
    package let role: SceneRole
    package let launchBehavior: SceneLaunchBehavior
    package let configuration: WindowConfiguration
    package let payloadType: ObjectIdentifier?
    package let initialPayload: ScenePayload?
    package let makeRender: (ScenePayload?) -> ((BuildContext) -> RenderNode)?

    package var isGroup: Bool { payloadType != nil }
}

package struct CompiledSceneGraph {
    package let scenes: [CompiledSceneDescriptor]
    package let primaryIndex: Int
    package let handleLifecycle: (LifecycleEvent) -> Void

    package var primary: CompiledSceneDescriptor { scenes[primaryIndex] }

    package func scene(id: SceneID) -> CompiledSceneDescriptor? {
        scenes.first { $0.id == id }
    }

    package func makeSurface(
        scene: CompiledSceneDescriptor,
        payload: ScenePayload?,
        instanceID: WindowInstanceID,
        actions: WindowActions = .unavailable
    ) throws(SceneConfigurationError) -> SceneSurface {
        guard let render = scene.makeRender(payload) else {
            throw .internalTypeMismatch(scene.id)
        }
        return SceneSurface(
            sceneID: scene.id,
            instanceID: instanceID,
            windowContext: WindowContext(instanceID: instanceID, actions: actions),
            render: render,
            handleLifecycle: handleLifecycle
        )
    }

    package func makePrimarySurface(
        instanceID: WindowInstanceID = WindowInstanceID(rawValue: 1),
        actions: WindowActions = .unavailable
    ) throws(SceneConfigurationError) -> SceneSurface {
        try makeSurface(
            scene: primary,
            payload: primary.initialPayload,
            instanceID: instanceID,
            actions: actions
        )
    }
}

package struct SceneSurface {
    package let sceneID: SceneID
    package let instanceID: WindowInstanceID
    package let windowContext: WindowContext
    package let render: (BuildContext) -> RenderNode
    package let handleLifecycle: (LifecycleEvent) -> Void
}

package func compileSceneGraph<A: App>(_ app: A) throws(
    SceneConfigurationError
) -> CompiledSceneGraph {
    var collector = _SceneCollector()
    try app.scenes._collectScenes(into: &collector)
    let descriptors = collector.descriptors

    var seen: Set<SceneID> = []
    var primaryIndices: [Int] = []
    for (index, scene) in descriptors.enumerated() {
        guard seen.insert(scene.id).inserted else {
            throw .duplicateSceneID(scene.id)
        }
        if scene.role == .primary { primaryIndices.append(index) }
        if scene.isGroup,
            (scene.role == .primary || scene.launchBehavior == .openAtLaunch),
            scene.initialPayload == nil
        {
            throw .missingInitialValue(scene.id)
        }
    }

    guard !primaryIndices.isEmpty else { throw .noPrimaryScene }
    guard primaryIndices.count == 1 else {
        throw .multiplePrimaryScenes(primaryIndices.map { descriptors[$0].id })
    }

    return CompiledSceneGraph(
        scenes: descriptors,
        primaryIndex: primaryIndices[0],
        handleLifecycle: { event in app.handleLifecycle(event) }
    )
}
