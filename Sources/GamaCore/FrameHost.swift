//  FrameHost.swift — GamaCore
//  The event-driven heart shared by every backend. Poll-style renderers
//  (TUI) wrap it in a blocking AppRuntime loop; retained-mode hosts
//  (AppKit/UIKit, DOM, C embed) call `pump`/`handle` directly from their
//  own event sources. One implementation of focus, actions, and dirty
//  tracking — identical behavior on every platform.

/// Action tables for one `FrameHost`. The store is confined to the host's
/// owning executor and is never shared across concurrent hosts.
private final class HostActionStore {
    var actions: [NodeID: () -> Void] = [:]
    var keyHandlers: [NodeID: (Key) -> Bool] = [:]

    func beginBuildPass() {
        actions.removeAll(keepingCapacity: true)
        keyHandlers.removeAll(keepingCapacity: true)
    }
    func register(_ id: NodeID, action: @escaping () -> Void) { actions[id] = action }
    func registerKey(_ id: NodeID, handler: @escaping (Key) -> Bool) {
        keyHandlers[id] = handler
    }
    func invoke(_ id: NodeID) { actions[id]?() }
    func invokeKey(_ key: Key, for id: NodeID) -> Bool { keyHandlers[id]?(key) ?? false }
}

/// The backend-independent heart of a running app. Each host owns focus,
/// the per-frame action and key-handler registries, model subscriptions,
/// the dirty flag, and frame production — one implementation of interaction
/// semantics shared by every backend. Poll-style renderers wrap it in
/// `AppRuntime`; retained-mode hosts (AppKit/UIKit, DOM, C embed) call
/// `pump(size:)` and `handle(_:)` from their own event sources. Out-of-band
/// changes reach it only through `subscriptions` or an explicit
/// `invalidate()`; there is no process-global registry to go around it.
/// Noncopyable: the host owns live reference state (action tables, the
/// dirty signal, subscriptions); a copy would silently share all of it.
/// Single ownership is a compile-time guarantee.
public struct FrameHost: ~Copyable {
    /// Stable declaration identity for the scene rendered by this host.
    public let sceneID: SceneID
    /// Runtime identity of the one live surface owned by this host.
    public let windowInstanceID: WindowInstanceID
    private let renderScene: (BuildContext) -> RenderNode
    private let deliverLifecycle: (LifecycleEvent) -> Void
    private let windowContext: WindowContext

    /// Every interactive node — the pointer hit-test set.
    private var interactive: [InteractiveRegion] = []
    /// Keyboard-reachable subset, in tab order.
    private var focusables: [(id: NodeID, rect: Rect)] = []
    /// Focus is tracked by identity, not index, so it survives rebuilds
    /// that insert or remove unrelated nodes.
    private var focusedID: NodeID? = nil
    private let actions = HostActionStore()

    /// Duplicate interactive identities observed during the most recent frame.
    /// Backends can surface this as a development diagnostic without making a
    /// malformed application crash in production.
    public private(set) var duplicateIDs: [NodeID] = []
    /// Nodes whose `@Reactive` storage changed identity between the previous
    /// frame and this one — state that was reconstructed rather than
    /// preserved. Empty for a correctly bound tree; nonempty means a
    /// component's identity moved (a branch flip, a reordered `ForEach`, or
    /// a different component type at the same position) and its state was
    /// dropped. Surface it as a development diagnostic like `duplicateIDs`.
    public private(set) var transientStateIDs: [NodeID] = []

    private let dirty: Signal<Bool>
    private let stateStore: HostStateStore
    /// Explicit model observation lifetime owned by this host.
    public let subscriptions: SubscriptionContext
    /// Set when the host wants to stop (Ctrl-C on TUI; hosts may ignore).
    public private(set) var wantsQuit = false
    /// Last size applied by `pump(size:)` or a `.resize` event.
    public private(set) var lastSize: Size = .zero

    /// Creates a host born dirty — the first `needsFrame` check is true —
    /// whose `SubscriptionContext` funnels every observed signal change
    /// into that same dirty flag.
    public init<A: App>(app: A) throws(SceneConfigurationError) {
        let graph = try compileSceneGraph(app)
        let surface = try graph.makePrimarySurface()
        self.init(surface: surface)
    }

    package init(surface: SceneSurface) {
        self.sceneID = surface.sceneID
        self.windowInstanceID = surface.instanceID
        self.renderScene = surface.render
        self.deliverLifecycle = surface.handleLifecycle
        self.windowContext = surface.windowContext
        let dirty = Signal(true)
        self.dirty = dirty
        self.subscriptions = SubscriptionContext { dirty.set(true) }
        self.stateStore = HostStateStore { dirty.set(true) }
    }

    /// Number of live `@Reactive` signals this host stores. Tests use it to
    /// prove eviction returns the store to its baseline.
    package var reactiveStateCount: Int { stateStore.count }

    /// True when state changed since the last `pump`.
    public var needsFrame: Bool { dirty.get() }

    /// Marks the host dirty so the next `needsFrame` check requests a
    /// frame — the explicit out-of-band path for changes no observed
    /// signal carries.
    public func invalidate() { dirty.set(true) }

    /// Observe a model signal for this host. Duplicate connections are
    /// coalesced and all observers can be cancelled as one host-owned lifetime.
    public func observe<Value>(_ signal: Signal<Value>) {
        subscriptions.observe(signal)
    }

    /// Detaches every model observation registered through `observe(_:)`.
    /// The context itself stays usable — later `observe` calls re-attach —
    /// so a backend can tear down and rebuild its model wiring.
    public func cancelSubscriptions() { subscriptions.cancelAll() }

    /// Build + lay out one frame at `size`, reconciling focus.
    /// Pure with respect to the renderer: callers paint the result.
    public mutating func pump(size: Size) -> LaidOutNode {
        lastSize = size
        dirty.set(false)

        actions.beginBuildPass()
        stateStore.beginBuildPass()
        var env = EnvironmentValues()
        env.focusedID = focusedID
        env.windowContext = windowContext
        let actionStore = actions
        var ctx = BuildContext(
            id: .root,
            inheritedStyle: .plain,
            environment: env,
            registerAction: { id, action in actionStore.register(id, action: action) },
            registerKeyHandler: { id, handler in actionStore.registerKey(id, handler: handler) }
        )
        ctx.stateStore = stateStore
        let ir = renderScene(ctx)
        var laid = LayoutEngine.layout(ir, in: Rect(origin: .zero, size: size))

        interactive.removeAll(keepingCapacity: true)
        laid.collectInteractive(into: &interactive)
        validateIdentities()
        focusables = interactive.compactMap { $0.isFocusable ? (id: $0.id, rect: $0.frame) : nil }

        // Reconcile focus with the new tree.
        if let id = focusedID, !focusables.contains(where: { $0.id == id }) {
            focusedID = focusables.first?.id
        }
        if focusedID == nil { focusedID = focusables.first?.id }
        if env.focusedID != focusedID {
            // Rebuild once so the frame returned by this pump already
            // contains the reconciled focus highlight.
            actions.beginBuildPass()
            stateStore.beginBuildPass()
            env.focusedID = focusedID
            var focusedContext = BuildContext(
                id: .root,
                inheritedStyle: .plain,
                environment: env,
                registerAction: { id, action in actionStore.register(id, action: action) },
                registerKeyHandler: { id, handler in actionStore.registerKey(id, handler: handler) }
            )
            focusedContext.stateStore = stateStore
            let focusedIR = renderScene(focusedContext)
            laid = LayoutEngine.layout(focusedIR, in: Rect(origin: .zero, size: size))
            interactive.removeAll(keepingCapacity: true)
            laid.collectInteractive(into: &interactive)
            validateIdentities()
            focusables = interactive.compactMap { $0.isFocusable ? (id: $0.id, rect: $0.frame) : nil }
        }
        // Sweep once, after whichever build painted: the reconciliation
        // build's marks are the live set.
        stateStore.sweep()
        transientStateIDs = stateStore.transientIDs
        return laid
    }

    private var focusedIndex: Int? {
        guard let id = focusedID else { return nil }
        return focusables.firstIndex { $0.id == id }
    }

    private mutating func validateIdentities() {
        var seen: Set<NodeID> = []
        var duplicates: Set<NodeID> = []
        for item in interactive where !seen.insert(item.id).inserted {
            duplicates.insert(item.id)
        }
        duplicateIDs = interactive.compactMap { item in
            duplicates.remove(item.id) == nil ? nil : item.id
        }
    }

    /// Routes one input event through the shared interaction policy:
    /// Ctrl-C/Ctrl-Q set `wantsQuit`; Tab and Shift-Tab cycle focus in tab
    /// order; arrow keys move focus spatially; Enter or Space activates the
    /// focused node; a pointer press hit-tests the topmost interactive node
    /// (focusing it only when focusable) and invokes its action; a resize
    /// just marks the host dirty; any other key is offered to the focused
    /// node's key handler. Whenever an event changes state, the dirty flag
    /// is set so the next `pump` re-renders.
    public mutating func handle(_ event: InputEvent) {
        switch event {
        case .key(.ctrl("c")), .key(.ctrl("q")):
            deliverLifecycle(
                .windowCloseRequested(scene: sceneID, instance: windowInstanceID))
            wantsQuit = true

        case .lifecycle(let lifecycle):
            if let target = lifecycle.windowTarget,
                (target.scene != sceneID || target.instance != windowInstanceID)
            {
                break
            }
            deliverLifecycle(lifecycle)
            dirty.set(true)

        case .key(.tab):
            moveFocus(by: 1)
        case .key(.backTab):
            moveFocus(by: -1)

        case .key(.up):
            moveFocusSpatially(dx: 0, dy: -1)
        case .key(.down):
            moveFocusSpatially(dx: 0, dy: 1)
        case .key(.left):
            moveFocusSpatially(dx: -1, dy: 0)
        case .key(.right):
            moveFocusSpatially(dx: 1, dy: 0)

        case .key(.enter), .key(.character(" ")):
            if let id = focusedID {
                stateStore.activate()
                actions.invoke(id)
                dirty.set(true)
            }

        case .pointer(let p, pressed: true):
            // Hit-test the full interactive set (topmost wins), not just
            // the focusable subset — non-focusable targets stay clickable.
            if let hit = interactive.last(where: { $0.frame.contains(p) }) {
                if hit.isFocusable { focusedID = hit.id }
                stateStore.activate()
                actions.invoke(hit.id)
                dirty.set(true)
            }

        case .resize(let size):
            lastSize = size
            dirty.set(true)

        case .key(let key):
            stateStore.activate()
            if let id = focusedID, actions.invokeKey(key, for: id) {
                dirty.set(true)
            }

        default:
            break
        }
    }

    private mutating func moveFocus(by delta: Int) {
        guard !focusables.isEmpty else { return }
        let n = focusables.count
        let current = focusedIndex ?? (delta > 0 ? -1 : 0)
        let next = ((current + delta) % n + n) % n
        focusedID = focusables[next].id
        dirty.set(true)
    }

    /// Arrow-key navigation: nearest focusable whose center lies in the
    /// pressed direction; falls back to tab order when none qualifies.
    private mutating func moveFocusSpatially(dx: Int, dy: Int) {
        guard let i = focusedIndex, focusables.count > 1 else {
            moveFocus(by: (dx + dy) >= 0 ? 1 : -1)
            return
        }
        let from = center(of: focusables[i].rect)
        var best: (index: Int, score: Int)? = nil
        for (j, item) in focusables.enumerated() where j != i {
            let to = center(of: item.rect)
            let vx = to.x - from.x
            let vy = to.y - from.y
            let along = dx * vx + dy * vy
            guard along > 0 else { continue }
            let ortho = dx != 0 ? abs(vy) : abs(vx)
            let score = along + ortho * 2
            if let currentBest = best, score >= currentBest.score { continue }
            best = (j, score)
        }
        if let best {
            focusedID = focusables[best.index].id
            dirty.set(true)
        } else {
            moveFocus(by: (dx + dy) >= 0 ? 1 : -1)
        }
    }

    private func center(of r: Rect) -> Point {
        Point(x: midpoint(r.minX, r.maxX), y: midpoint(r.minY, r.maxY))
    }

    private func midpoint(_ lower: Int, _ upper: Int) -> Int {
        let (sum, overflow) = lower.addingReportingOverflow(upper)
        if !overflow { return sum / 2 }
        return lower / 2 + upper / 2 + (lower % 2 + upper % 2) / 2
    }
}
