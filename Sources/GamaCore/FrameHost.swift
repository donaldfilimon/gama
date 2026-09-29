//  FrameHost.swift — GamaCore
//  The event-driven heart shared by every backend. Poll-style renderers
//  (TUI) wrap it in a blocking AppRuntime loop; retained-mode hosts
//  (AppKit/UIKit, DOM, C embed) call `pump`/`handle` directly from their
//  own event sources. One implementation of focus, actions, and dirty
//  tracking — identical behavior on every platform.

/// Stable identity of one application action, chosen by the application
/// rather than by the control's position in the tree.
///
/// ``FrameHost`` stores the control's closure under this value for the
/// current frame. Focus activation, a matching shortcut, and
/// ``FrameHost/perform(_:)`` call that same closure. The identity is
/// absent after a build that did not register it — the control is
/// disabled or not in the tree — and those paths then do nothing.
public struct ActionID: Hashable, Sendable {
    /// Application-supplied token. Equal tokens are the same action.
    public var rawValue: String

    /// Creates an identity from `rawValue`.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Keys the host already uses for quit and focus. They are not action
/// shortcuts; registration keeps the identity and drops the shortcut.
private func isReservedActionShortcut(_ key: Key) -> Bool {
    switch key {
    case .tab, .backTab, .up, .down, .left, .right, .ctrl("c"), .ctrl("q"):
        return true
    default:
        return false
    }
}

/// Action tables for one `FrameHost`. The store is confined to the host's
/// owning executor and is never shared across concurrent hosts.
private final class HostActionStore {
    var actions: [NodeID: () -> Void] = [:]
    var keyHandlers: [NodeID: (Key) -> Bool] = [:]
    var named: [ActionID: () -> Void] = [:]
    var shortcuts: [Key: ActionID] = [:]
    var regions: [NodeID: NativeRegionID] = [:]
    var controls: [NodeID: ControlDescriptor] = [:]

    func beginBuildPass() {
        actions.removeAll(keepingCapacity: true)
        keyHandlers.removeAll(keepingCapacity: true)
        named.removeAll(keepingCapacity: true)
        shortcuts.removeAll(keepingCapacity: true)
        regions.removeAll(keepingCapacity: true)
        controls.removeAll(keepingCapacity: true)
    }
    func register(_ id: NodeID, action: @escaping () -> Void) { actions[id] = action }
    func registerKey(_ id: NodeID, handler: @escaping (Key) -> Bool) {
        keyHandlers[id] = handler
    }
    func registerNamed(_ id: ActionID, shortcut: Key?, action: @escaping () -> Void) {
        named[id] = action
        if let shortcut, !isReservedActionShortcut(shortcut) {
            shortcuts[shortcut] = id
        }
    }
    func invoke(_ id: NodeID) { actions[id]?() }
    func hasAction(_ id: NodeID) -> Bool { actions[id] != nil }
    /// Whether `id` only displays state: a progress indicator with no
    /// action. Pointer hit-testing looks through it, so a press lands on
    /// the interactive node beneath (a progress bar inside a button label
    /// still presses the button).
    func isDisplayOnly(_ id: NodeID) -> Bool {
        guard actions[id] == nil, case .progress? = controls[id] else { return false }
        return true
    }
    func invokeKey(_ key: Key, for id: NodeID) -> Bool { keyHandlers[id]?(key) ?? false }
    func effect(for id: ActionID) -> (() -> Void)? { named[id] }
    func shortcutEffect(for key: Key) -> (() -> Void)? {
        guard let id = shortcuts[key] else { return nil }
        return named[id]
    }
    func registerRegion(_ id: NodeID, _ region: NativeRegionID) { regions[id] = region }
    func region(for id: NodeID) -> NativeRegionID? { regions[id] }
    func registerControl(_ id: NodeID, _ descriptor: ControlDescriptor) { controls[id] = descriptor }
}

/// The backend-independent heart of a running app. Each host owns focus,
/// the per-frame action and key-handler registries, model subscriptions,
/// the dirty flag, and frame production — one implementation of interaction
/// semantics shared by every backend. Poll-style renderers wrap it in
/// `AppRuntime`; retained-mode hosts (AppKit/UIKit, DOM, C embed) call
/// `pump(size:)` and `handle(_:)` from their own event sources. Out-of-band
/// changes reach it through bound `@Reactive` writes, `subscriptions`, or
/// an explicit `invalidate()`; there is no process-global registry to go
/// around it.
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
    /// Measurements this host lays out with; `.cell` unless a presentation
    /// host supplies its own (ADR 0017).
    private let metrics: LayoutMetrics

    /// Every interactive node — the pointer hit-test set.
    private var interactive: [InteractiveRegion] = []
    /// Keyboard-reachable subset, in tab order.
    private var focusables: [(id: NodeID, rect: Rect)] = []
    /// Focus is tracked by identity, not index, so it survives rebuilds
    /// that insert or remove unrelated nodes.
    private var currentFocus: NodeID? = nil
    private let actions = HostActionStore()

    /// Duplicate interactive identities observed during the most recent frame.
    /// Backends can surface this as a development diagnostic without making a
    /// malformed application crash in production.
    public private(set) var duplicateIDs: [NodeID] = []
    /// Nodes with a reactive slot whose storage was replaced at the same
    /// key since the previous frame, such as a slot value-type change.
    /// New or removed keys and positional reorders that reuse the same
    /// storage are not reported. An empty list therefore does not prove
    /// that collection state follows the intended element identities.
    public private(set) var transientStateIDs: [NodeID] = []

    /// Native regions (ADR 0016) in the most recent frame, in visual order,
    /// with focus already reconciled. A presentation host places attached
    /// views on these frames; every other backend ignores them.
    public private(set) var nativeRegions: [NativeRegionFrame] = []
    /// Native region identities registered more than once in the most
    /// recent frame. The last registration wins in ``nativeRegions``.
    public private(set) var duplicateNativeRegionIDs: [NativeRegionID] = []

    /// Control descriptors (ADR 0017) the most recent build registered,
    /// keyed by the control's node. A node registered more than once keeps
    /// its last descriptor. A native presentation host reads this; every
    /// other backend ignores it.
    public var controls: [NodeID: ControlDescriptor] { actions.controls }

    private let dirty: Signal<Bool>
    private let stateStore: HostStateStore
    /// Explicit model observation lifetime owned by this host.
    public let subscriptions: SubscriptionContext
    /// Set when the host wants to stop (Ctrl-C on TUI; hosts may ignore).
    public private(set) var wantsQuit = false
    /// The outcome the application reported through ``subscriptions``, or
    /// `nil` while it is still running. Distinct from ``wantsQuit``, which
    /// records a user's request to stop rather than the work's own result.
    public var completion: CompletionStatus? { subscriptions.completion }
    /// Last size applied by `pump(size:)` or a `.resize` event.
    public private(set) var lastSize: Size = .zero

    /// Creates a host born dirty — the first `needsFrame` check is true —
    /// whose `SubscriptionContext` funnels every observed signal change
    /// into that same dirty flag.
    ///
    /// `metrics` decides what one layout unit is (ADR 0017). The default
    /// `.cell` makes a unit one cell, exactly as before metrics existed. A
    /// host with other metrics pumps sizes in its own layout units, while
    /// ``EnvironmentValues/surfaceSize`` stays in cells: the pump size
    /// divided per axis by `metrics.units(1, axis)`.
    public init<A: App>(app: A, metrics: LayoutMetrics = .cell) throws(SceneConfigurationError) {
        let graph = try compileSceneGraph(app)
        let surface = try graph.makePrimarySurface()
        self.init(surface: surface, metrics: metrics)
        app.connect(subscriptions)
    }

    package init(surface: SceneSurface, metrics: LayoutMetrics = .cell) {
        self.metrics = metrics
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

        var env = EnvironmentValues()
        env.focusedID = currentFocus
        env.windowContext = windowContext
        env.surfaceSize = cellSize(of: size)
        var laid = buildFrame(size: size, environment: env)

        // Reconcile focus with the new tree.
        if let id = currentFocus, !focusables.contains(where: { $0.id == id }) {
            currentFocus = focusables.first?.id
        }
        if currentFocus == nil { currentFocus = focusables.first?.id }
        if env.focusedID != currentFocus {
            // Rebuild once so the frame returned by this pump already
            // contains the reconciled focus highlight.
            env.focusedID = currentFocus
            laid = buildFrame(size: size, environment: env)
        }
        // Sweep once, after whichever build painted: the reconciliation
        // build's marks are the live set.
        stateStore.sweep()
        transientStateIDs = stateStore.transientIDs
        publishNativeRegions()
        return laid
    }

    /// `size` in layout units converted to whole cells per axis, the unit
    /// ``EnvironmentValues/surfaceSize`` is authored in. The divisor is at
    /// least 1, so a degenerate metrics value cannot trap; with `.cell` this
    /// is the identity.
    private func cellSize(of size: Size) -> Size {
        let perColumn = max(1, metrics.units(1, .horizontal))
        let perRow = max(1, metrics.units(1, .vertical))
        return Size(width: size.width / perColumn, height: size.height / perRow)
    }

    /// Rebuilds the tree and its interaction tables with one consistent
    /// context. State eviction belongs to `pump`, after its final build.
    private mutating func buildFrame(size: Size, environment: EnvironmentValues) -> LaidOutNode {
        actions.beginBuildPass()
        stateStore.beginBuildPass()
        let actionStore = actions
        var context = BuildContext(
            environment: environment,
            registerAction: { id, action in actionStore.register(id, action: action) },
            registerKeyHandler: { id, handler in actionStore.registerKey(id, handler: handler) },
            registerNamedAction: { id, shortcut, action in
                actionStore.registerNamed(id, shortcut: shortcut, action: action)
            },
            registerNativeRegion: { id, region in actionStore.registerRegion(id, region) },
            registerControl: { id, descriptor in actionStore.registerControl(id, descriptor) }
        )
        context.stateStore = stateStore
        let root = renderScene(context)
        // After the build, so the lookup sees this build's control table: a
        // registered control measures through `descriptorSize` first and
        // falls back to the base `controlSize`.
        var frameMetrics = metrics
        let baseControlSize = metrics.controlSize
        let descriptorSize = metrics.descriptorSize
        frameMetrics.controlSize = { id, proposal in
            if let descriptor = actionStore.controls[id], let size = descriptorSize(descriptor, proposal) {
                return size
            }
            return baseControlSize(id, proposal)
        }
        let frame = LayoutEngine.layout(root, in: Rect(origin: .zero, size: size), metrics: frameMetrics)
        interactive.removeAll(keepingCapacity: true)
        frame.collectInteractive(into: &interactive)
        validateIdentities()
        focusables = interactive.compactMap { $0.isFocusable ? (id: $0.id, rect: $0.frame) : nil }
        return frame
    }

    /// Joins the latest build's region registrations with its interactive
    /// frames. Keeps the last registration of a repeated identity, at its
    /// own visual position, and records the identity as a duplicate.
    private mutating func publishNativeRegions() {
        let all: [NativeRegionFrame] = interactive.compactMap { item in
            actions.region(for: item.id).map {
                NativeRegionFrame(id: $0, node: item.id, frame: item.frame, isFocused: item.id == currentFocus)
            }
        }
        var seen: Set<NativeRegionID> = []
        var kept: [NativeRegionFrame] = []
        for entry in all.reversed() where seen.insert(entry.id).inserted {
            kept.append(entry)
        }
        nativeRegions = Array(kept.reversed())
        var counted: [NativeRegionID: Int] = [:]
        for entry in all { counted[entry.id, default: 0] += 1 }
        var reported: Set<NativeRegionID> = []
        duplicateNativeRegionIDs = all.compactMap { entry in
            (counted[entry.id, default: 0] > 1 && reported.insert(entry.id).inserted) ? entry.id : nil
        }
    }

    private var focusedIndex: Int? {
        guard let id = currentFocus else { return nil }
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

    /// Invokes the closure registered for `id` during the latest build.
    ///
    /// Focus activation and a matching shortcut call that same closure.
    /// An identity the latest build did not register — the control is
    /// disabled, not in the tree, or the host has not pumped — does nothing
    /// and does not mark the host dirty. A hit rebinds per-surface state,
    /// runs the closure, and marks the host dirty, the same bookkeeping
    /// ``handle(_:)`` uses for activation.
    public func perform(_ id: ActionID) {
        guard let effect = actions.effect(for: id) else { return }
        stateStore.activate()
        effect()
        dirty.set(true)
    }

    /// The node that holds keyboard focus after the most recent frame or
    /// focus change, or `nil` when nothing is focusable.
    public var focusedID: NodeID? { currentFocus }

    /// Activates the interactive node `id` directly, the way a pointer
    /// press on it does but without hit-testing: a native presentation host
    /// (ADR 0017) calls it when a platform control fires.
    ///
    /// A focusable target takes focus; then per-surface state is rebound,
    /// the node's action runs, and the host is marked dirty. Unlike a
    /// pointer press, which marks the host dirty whenever it hits an
    /// interactive node, a node the latest build registered no action for
    /// (disabled, not in the tree, or never actionable) is a no-op that
    /// does not mark the host dirty.
    public mutating func activate(_ id: NodeID) {
        guard actions.hasAction(id) else { return }
        if focusables.contains(where: { $0.id == id }) { currentFocus = id }
        stateStore.activate()
        actions.invoke(id)
        dirty.set(true)
    }

    /// Writes `text` through the binding of the text field `id`, for a
    /// native host whose platform editor changed (ADR 0017).
    ///
    /// Per-surface state is rebound first, exactly as before an action
    /// runs, so a component instance rendered by more than one host writes
    /// this host's `@Reactive` storage. Then the host is marked dirty. A
    /// node the latest build registered no
    /// ``ControlDescriptor/textField(placeholder:text:isEnabled:setText:)``
    /// for is a no-op that does not mark the host dirty.
    public mutating func setText(_ id: NodeID, _ text: String) {
        guard case .textField(_, _, _, let write)? = actions.controls[id] else { return }
        stateStore.activate()
        write(text)
        dirty.set(true)
    }

    /// Moves keyboard focus to the focusable node `id` and marks the host
    /// dirty, for a native host whose platform focus changed.
    ///
    /// A node that already has focus, is not focusable, or is not in the
    /// latest frame changes nothing and does not mark the host dirty, so a
    /// host that echoes Gama's own focus change back cannot loop.
    public mutating func focus(_ id: NodeID) {
        guard id != currentFocus, focusables.contains(where: { $0.id == id }) else { return }
        currentFocus = id
        dirty.set(true)
    }

    /// Routes one input event through the shared interaction policy:
    /// Ctrl-C/Ctrl-Q set `wantsQuit`; Tab and Shift-Tab cycle focus in tab
    /// order; arrow keys move focus spatially; Enter and Space are offered
    /// to the focused node's key handler and activate that node when the
    /// handler declines. Every other key is offered to the focused handler
    /// first, and a declared action shortcut runs only when that handler
    /// declines, so a text field keeps the characters it consumes. Enter
    /// and Space are not shortcuts. A pointer press hit-tests the topmost
    /// interactive node that is not display-only (a progress indicator is
    /// looked through), focusing it only when focusable, and invokes its
    /// action; a resize just marks the host dirty. Whenever an event
    /// changes state, the dirty flag is set so the next `pump` re-renders.
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

        case .key(let key) where key == .up || key == .down || key == .left || key == .right:
            var handled = false
            if let id = currentFocus {
                stateStore.activate()
                if actions.invokeKey(key, for: id) {
                    dirty.set(true)
                    handled = true
                }
            }
            if !handled {
                switch key {
                case .up: moveFocusSpatially(dx: 0, dy: -1)
                case .down: moveFocusSpatially(dx: 0, dy: 1)
                case .left: moveFocusSpatially(dx: -1, dy: 0)
                case .right: moveFocusSpatially(dx: 1, dy: 0)
                default: break
                }
            }

        case .key(let key) where key == .enter || key == .character(" "):
            if let id = currentFocus {
                stateStore.activate()
                // First refusal to the focused node's key handler: an editor
                // has to be able to type a space, and Enter has to be able to
                // mean "newline" rather than "activate". Activation is the
                // fallback for a node that declines the key — a `Button`
                // registers no handler at all, so it still activates.
                if !actions.invokeKey(key, for: id) {
                    actions.invoke(id)
                }
                dirty.set(true)
            }

        case .pointer(let p, pressed: true):
            // Hit-test the full interactive set (topmost wins), not just
            // the focusable subset — non-focusable targets stay clickable.
            // Display-only nodes (progress) are looked through, so the
            // press reaches the node beneath them.
            if let hit = interactive.last(where: { $0.frame.contains(p) && !actions.isDisplayOnly($0.id) }) {
                if hit.isFocusable { currentFocus = hit.id }
                stateStore.activate()
                actions.invoke(hit.id)
                dirty.set(true)
            }

        case .gamepad(let button, pressed: true):
            // Re-enter with the equivalent keystroke rather than repeating
            // the focus and activation logic: a controller must reach the
            // same operation the keyboard does, by construction.
            if let key = button.semanticKey { handle(.key(key)) }

        case .resize(let size):
            lastSize = size
            dirty.set(true)

        case .key(let key):
            stateStore.activate()
            if let id = currentFocus, actions.invokeKey(key, for: id) {
                dirty.set(true)
            } else if let effect = actions.shortcutEffect(for: key) {
                effect()
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
        currentFocus = focusables[next].id
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
            currentFocus = focusables[best.index].id
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
