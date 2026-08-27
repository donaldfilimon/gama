//  Scene.swift — GamaCore
//  Declarative application surfaces and the package-private compilation
//  model shared by shell and single-surface backends.

/// Stable application-defined identity for a scene declaration.
public struct SceneID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

/// Stable identity for a typed ``WindowGroup`` declaration.
public struct WindowGroupKey<Value: Hashable & Sendable>: Hashable, Sendable {
    public let id: SceneID

    public init(_ id: SceneID) { self.id = id }
}

/// Runtime-generated identity for one live window or other surface.
public struct WindowInstanceID: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Whether a scene is the portable primary surface or an auxiliary surface.
public enum SceneRole: Hashable, Sendable {
    case primary
    case auxiliary
}

/// Whether a shell should create a scene during application launch.
public enum SceneLaunchBehavior: Hashable, Sendable {
    case openAtLaunch
    case onDemand
}

/// Native-window preferences expressed in Gama's cell coordinate system.
public struct WindowConfiguration: Hashable, Sendable {
    public var title: String
    public var initialCellSize: Size
    public var isResizable: Bool

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
public protocol Scene: Sendable {
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
    case first(First)
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
    public static func buildBlock() -> EmptyScene { EmptyScene() }
    public static func buildBlock<S: Scene>(_ scene: S) -> S { scene }
    public static func buildBlock<each S: Scene>(
        _ scene: repeat each S
    ) -> TupleScene<repeat each S> {
        TupleScene(repeat each scene)
    }
    public static func buildOptional<S: Scene>(
        _ scene: S?
    ) -> ConditionalScene<S, EmptyScene> {
        scene.map(ConditionalScene.first) ?? .second(EmptyScene())
    }
    public static func buildEither<First: Scene, Second: Scene>(
        first: First
    ) -> ConditionalScene<First, Second> {
        .first(first)
    }
    public static func buildEither<First: Scene, Second: Scene>(
        second: Second
    ) -> ConditionalScene<First, Second> {
        .second(second)
    }
    public static func buildExpression<S: Scene>(_ scene: S) -> S { scene }
}

/// A singleton window declaration. Reopening it focuses its existing live
/// instance rather than creating a duplicate.
public struct Window<Content: View>: Scene {
    public let id: SceneID
    public let role: SceneRole
    public let launchBehavior: SceneLaunchBehavior
    public let configuration: WindowConfiguration
    package let content: @Sendable () -> Content

    public init(
        _ title: String,
        id: SceneID,
        role: SceneRole = .auxiliary,
        launchBehavior: SceneLaunchBehavior? = nil,
        initialCellSize: Size = Size(width: 100, height: 30),
        isResizable: Bool = true,
        @ViewBuilder content: @escaping @Sendable () -> Content
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
    public let key: WindowGroupKey<Value>
    public let role: SceneRole
    public let launchBehavior: SceneLaunchBehavior
    public let configuration: WindowConfiguration
    private let initial: InitialGroupValue<Value>
    package let content: @Sendable (Value) -> Content

    public init(
        _ title: String,
        key: WindowGroupKey<Value>,
        role: SceneRole = .auxiliary,
        launchBehavior: SceneLaunchBehavior? = nil,
        initialCellSize: Size = Size(width: 100, height: 30),
        isResizable: Bool = true,
        @ViewBuilder content: @escaping @Sendable (Value) -> Content
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

    public init(
        _ title: String,
        key: WindowGroupKey<Value>,
        role: SceneRole = .auxiliary,
        launchBehavior: SceneLaunchBehavior? = nil,
        initialValue: Value,
        initialCellSize: Size = Size(width: 100, height: 30),
        isResizable: Bool = true,
        @ViewBuilder content: @escaping @Sendable (Value) -> Content
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
    case noPrimaryScene
    case multiplePrimaryScenes([SceneID])
    case duplicateSceneID(SceneID)
    case missingInitialValue(SceneID)
    case internalTypeMismatch(SceneID?)
}

/// Portable lifecycle events delivered through ``InputEvent/lifecycle(_:)``.
public enum LifecycleEvent: Hashable, Sendable {
    case didLaunch
    case willEnterForeground
    case didEnterBackground
    case willTerminate
    case windowDidOpen(scene: SceneID, instance: WindowInstanceID)
    case windowCloseRequested(scene: SceneID, instance: WindowInstanceID)
    case windowDidClose(scene: SceneID, instance: WindowInstanceID)
    case windowDidBecomeKey(scene: SceneID, instance: WindowInstanceID)
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

    public static var unavailable: WindowActions {
        WindowActions { _ in false }
    }

    public func openWindow(_ id: SceneID) -> Bool {
        enqueue(.openWindow(id))
    }

    public func openWindow<Value: Hashable & Sendable>(
        group: WindowGroupKey<Value>,
        value: Value
    ) -> Bool {
        enqueue(.openGroup(group.id, ScenePayload(value)))
    }

    public func dismissWindow(_ instance: WindowInstanceID? = nil) -> Bool {
        enqueue(.dismiss(instance))
    }
}

/// The current surface identity and its window operations.
public struct WindowContext: Sendable {
    public var instanceID: WindowInstanceID?
    public var actions: WindowActions

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
    public typealias Body = Never_
    public var body: Never_ { Never_() }
    private let content: @Sendable (WindowContext) -> Content

    public init(@ViewBuilder content: @escaping @Sendable (WindowContext) -> Content) {
        self.content = content
    }

    public func render(in context: BuildContext) -> RenderNode {
        content(context.environment.windowContext).render(in: context.child(0))
    }
}

// MARK: - Package-private scene compilation

package struct CompiledSceneDescriptor: @unchecked Sendable {
    package let id: SceneID
    package let role: SceneRole
    package let launchBehavior: SceneLaunchBehavior
    package let configuration: WindowConfiguration
    package let payloadType: ObjectIdentifier?
    package let initialPayload: ScenePayload?
    package let makeRender: @Sendable (ScenePayload?) -> (@Sendable (BuildContext) -> RenderNode)?

    package var isGroup: Bool { payloadType != nil }
}

package struct CompiledSceneGraph: @unchecked Sendable {
    package let scenes: [CompiledSceneDescriptor]
    package let primaryIndex: Int
    package let handleLifecycle: @Sendable (LifecycleEvent) -> Void

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

package struct SceneSurface: @unchecked Sendable {
    package let sceneID: SceneID
    package let instanceID: WindowInstanceID
    package let windowContext: WindowContext
    package let render: @Sendable (BuildContext) -> RenderNode
    package let handleLifecycle: @Sendable (LifecycleEvent) -> Void
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
