/// Outcome of one canonical pump step.
///
/// Backends use ``followUp`` to decide whether to schedule another step
/// immediately: a pump can leave the host dirty when focus reconciliation
/// changes the tree, and dropping that frame strands the reconciled
/// highlight until the next unrelated event arrives.
public struct AdvanceOutcome: Hashable, Sendable {
    /// Whether this step produced a frame. `false` means the host was
    /// clean and nothing was laid out, painted, or emitted.
    public var produced: Bool
    /// Whether the host is *still* dirty after the step, so the backend
    /// should schedule another advance soon.
    public var followUp: Bool

    /// Creates an outcome from its two flags.
    public init(produced: Bool, followUp: Bool) {
        self.produced = produced
        self.followUp = followUp
    }

    /// The outcome of a step that found a clean host.
    public static let clean = AdvanceOutcome(produced: false, followUp: false)
}

/// One laid-out frame plus the follow-up signal that produced it.
public struct AdvancedFrame: Hashable, Sendable {
    /// The laid-out tree this step produced.
    public var frame: LaidOutNode
    /// Whether the host is still dirty after the step.
    public var followUp: Bool

    /// Pairs a laid-out frame with its follow-up signal.
    public init(frame: LaidOutNode, followUp: Bool) {
        self.frame = frame
        self.followUp = followUp
    }
}

/// The canonical frame pump: the single owner of resize policy, the dirty
/// gate, and pump ordering for every Gama backend.
///
/// Before this type each backend hand-rolled `resize → clear → paint →
/// emit`, and the four copies drifted: `.resize` took effect immediately on
/// Embed and WASM but only at the next pump on TUI and AppleUI, so handling
/// code saw two different sizes depending on the host it ran under.
/// ``HostPump`` settles that with **one eager resize policy** — a `.resize`
/// updates ``size`` and invalidates the host *before* the event is
/// forwarded, on every backend.
///
/// Emission stays per-backend. This type produces a ``LaidOutNode``;
/// GamaDraw adds the shared cell-buffer path on top, and each backend turns
/// that into ANSI, HTML, `DrawList` bytes, or CoreGraphics. No backend
/// forks layout, paint order, or the dirty gate again.
///
/// Noncopyable, like the ``FrameHost`` it consumes: a running pump is not a
/// value to be duplicated.
public struct HostPump: ~Copyable {
    /// The surface host this pump drives. Consumed at init and owned for
    /// the pump's lifetime.
    private var host: FrameHost

    /// Current drawable extent, in cells. Updated eagerly by `.resize`
    /// before the event reaches the host.
    public private(set) var size: Size

    /// Adopts `host` and starts pumping at `size`.
    ///
    /// The host is consumed: ownership moves into the pump, so there is no
    /// second reference through which the dirty gate could be bypassed.
    public init(host: consuming FrameHost, size: Size) {
        self.host = host
        self.size = size
    }

    /// Whether the host has pending work for the next ``advance()``.
    public var needsFrame: Bool { host.needsFrame }

    /// Whether the host has requested application shutdown.
    public var wantsQuit: Bool { host.wantsQuit }

    /// Routes one event through the shared policy.
    ///
    /// `.resize` is the only case this type interprets: it updates ``size``
    /// and marks the host dirty *before* forwarding, so any handling that
    /// runs as a consequence already observes the new extent. Every other
    /// event is forwarded untouched — interaction policy stays in
    /// ``FrameHost``.
    public mutating func handle(_ event: InputEvent) {
        if case .resize(let newSize) = event {
            size = newSize
            host.invalidate()
        }
        host.handle(event)
    }

    /// Marks the host dirty without an input event, for out-of-band model
    /// changes that did not arrive through ``handle(_:)``.
    public mutating func invalidate() { host.invalidate() }

    /// The canonical step: lay out one frame when the host is dirty.
    ///
    /// Returns `nil` when the host is clean — the caller emits nothing and
    /// does no work. Otherwise returns the laid-out tree together with a
    /// follow-up flag that is `true` when the pump left the host dirty
    /// (focus reconciliation), which is the WASM `requestFrame` rule
    /// generalized to every backend.
    public mutating func advance() -> AdvancedFrame? {
        guard host.needsFrame else { return nil }
        let laid = host.pump(size: size)
        return AdvancedFrame(frame: laid, followUp: host.needsFrame)
    }

    /// Delivers a lifecycle event to the host.
    ///
    /// A convenience over `handle(.lifecycle(event))` for the launch and
    /// termination edges every backend drives.
    public mutating func handleLifecycle(_ event: LifecycleEvent) {
        handle(.lifecycle(event))
    }

    /// Detaches every model observation registered on the host.
    public func cancelSubscriptions() { host.cancelSubscriptions() }

    /// Registers a model observation on the underlying host.
    public func observe<Value>(_ signal: Signal<Value>) { host.observe(signal) }
}
