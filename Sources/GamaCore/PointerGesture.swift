//  PointerGesture.swift — GamaCore
//  The rich pointer model (ADR 0018). Backends translate platform input into
//  `PointerEvent`; `FrameHost` alone recognizes gestures from it, so capture,
//  thresholds, long press, and cancellation cannot fork per backend.
//  Stdlib-only and Embedded-safe.

/// One raw pointer sample from a backend, in grid cells.
///
/// Backends only translate: they report what the device did and when, and
/// ``FrameHost`` decides what it means. Feed it through
/// ``InputEvent/pointerEvent(_:)``.
public struct PointerEvent: Hashable, Sendable {
    /// What the device did.
    public enum Phase: Hashable, Sendable {
        /// A button or contact went down.
        case down
        /// The pointer moved; with a button held when a gesture is captured,
        /// otherwise it is treated as hover (mouse and pen only).
        case move
        /// The button or contact was released.
        case up
        /// The platform cancelled the contact (or the pointer left the
        /// surface): any captured gesture ends with
        /// ``PointerGesture/Phase/cancelled`` and hover clears.
        case cancel
        /// The pointer moved with nothing pressed.
        case hover
        /// A wheel or trackpad scroll; ``PointerEvent/scroll`` carries the delta.
        case scroll
        /// A sample with no movement, delivered by a host at
        /// ``FrameHost/pointerDeadlineMillis`` so a long press can fire.
        case stationary
    }

    /// The device that produced the sample.
    public enum Kind: Hashable, Sendable {
        /// A mouse or trackpad cursor.
        case mouse
        /// A finger on a touch surface.
        case touch
        /// A stylus.
        case pen
    }

    /// Keyboard modifiers held during the sample.
    public struct Modifiers: OptionSet, Hashable, Sendable {
        /// The raw bit set.
        public var rawValue: UInt8
        /// Creates a modifier set from raw bits.
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        /// Shift.
        public static let shift = Modifiers(rawValue: 1 << 0)
        /// Control.
        public static let control = Modifiers(rawValue: 1 << 1)
        /// Option (Alt).
        public static let option = Modifiers(rawValue: 1 << 2)
        /// Command (Windows key, Meta).
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// What the device did.
    public var phase: Phase
    /// Where, in grid cells relative to the surface origin.
    public var location: Point
    /// The device kind.
    public var kind: Kind
    /// The button: 0 primary, 1 secondary, 2 middle. Only the primary button
    /// activates a region that registered no pointer handler.
    public var button: Int
    /// Modifiers held during the sample.
    public var modifiers: Modifiers
    /// Scroll delta in cells (columns, lines) for ``Phase/scroll``; zero
    /// otherwise. Every backend uses one sign: positive `y` reveals the
    /// lines below (wheel toward the user, two-finger swipe up on a natural
    /// trackpad), positive `x` the columns to the right.
    public var scroll: Point
    /// Identity of the pointer or contact. One pointer is captured at a
    /// time; samples from any other identity are ignored while it is.
    public var pointerID: Int
    /// Monotonic milliseconds of the sample, or `nil` when the backend has no
    /// clock. A press without a timestamp gets no long-press deadline.
    public var timestampMillis: UInt64?

    /// Creates a sample. Everything but the phase and location defaults to a
    /// primary mouse pointer with no modifiers, no scroll, and no clock.
    public init(
        phase: Phase,
        location: Point,
        kind: Kind = .mouse,
        button: Int = 0,
        modifiers: Modifiers = [],
        scroll: Point = .zero,
        pointerID: Int = 0,
        timestampMillis: UInt64? = nil
    ) {
        self.phase = phase
        self.location = location
        self.kind = kind
        self.button = button
        self.modifiers = modifiers
        self.scroll = scroll
        self.pointerID = pointerID
        self.timestampMillis = timestampMillis
    }
}

/// The interaction family a host belongs to. A host supplies it when it
/// creates its ``FrameHost``; the host's ``pointerPolicy`` follows from it.
public enum InteractionIdiom: Hashable, Sendable {
    /// A phone: touch first, drag only after a long press.
    case phone
    /// A tablet: touch and pointer, larger drag slop.
    case pad
    /// A desktop: mouse, trackpad, and pen.
    case desktop
    /// A character terminal: no timing, so no long press.
    case terminal
    /// A spatial device. Follows ``pad`` until a vision host measures otherwise.
    case vision

    /// The pointer recognition policy for this idiom.
    ///
    /// | Idiom | Drag threshold | Long press |
    /// |---|---|---|
    /// | desktop | 1 cell | 500 ms |
    /// | terminal | 1 cell | none |
    /// | pad, vision | 2 cells | 400 ms |
    /// | phone | 2 cells, only after a long press | 500 ms |
    public var pointerPolicy: PointerPolicy {
        switch self {
        case .desktop:
            return PointerPolicy(dragThreshold: 1, longPressMillis: 500, dragRequiresLongPress: false)
        case .terminal:
            return PointerPolicy(dragThreshold: 1, longPressMillis: nil, dragRequiresLongPress: false)
        case .pad, .vision:
            return PointerPolicy(dragThreshold: 2, longPressMillis: 400, dragRequiresLongPress: false)
        case .phone:
            return PointerPolicy(dragThreshold: 2, longPressMillis: 500, dragRequiresLongPress: true)
        }
    }
}

/// The thresholds ``FrameHost`` recognizes gestures with.
public struct PointerPolicy: Hashable, Sendable {
    /// Cells the pointer must travel from the press, on either axis, before
    /// a press becomes a drag.
    public var dragThreshold: Int
    /// How long a still press lasts before it becomes a long press, or `nil`
    /// when the idiom has none.
    public var longPressMillis: UInt64?
    /// When `true`, travelling ``dragThreshold`` before the long press
    /// cancels the gesture instead of dragging; only a long-pressed contact
    /// can drag.
    public var dragRequiresLongPress: Bool

    /// Creates a policy.
    public init(dragThreshold: Int, longPressMillis: UInt64?, dragRequiresLongPress: Bool) {
        self.dragThreshold = dragThreshold
        self.longPressMillis = longPressMillis
        self.dragRequiresLongPress = dragRequiresLongPress
    }
}

/// A recognized gesture, delivered to the handler a view registered with
/// ``BuildContext/registerPointerHandler``.
///
/// Every ``Phase/pressed`` is followed by exactly one terminal phase:
/// ``Phase/tap``, ``Phase/dragEnded``, or ``Phase/cancelled``.
public struct PointerGesture: Hashable, Sendable {
    /// The recognized phase.
    public enum Phase: Hashable, Sendable {
        /// A press landed on the region and captured the pointer.
        case pressed
        /// Released without travelling the drag threshold or long-pressing.
        case tap
        /// The captured pointer travelled the drag threshold.
        case dragBegan
        /// The dragging pointer moved.
        case dragMoved
        /// The dragging pointer was released.
        case dragEnded
        /// The gesture ended without a tap or a drop: an explicit cancel,
        /// Escape, the window resigning key or backgrounding, the region
        /// vanishing, or a release after a long press.
        case cancelled
        /// The press stayed still until the idiom's long-press deadline.
        case longPress
        /// The pointer moved over the region with nothing pressed.
        case hover
        /// A scroll over the region.
        case scroll
    }

    /// The recognized phase.
    public var phase: Phase
    /// Where the press started (the hover or scroll location for those phases).
    public var start: Point
    /// Where the pointer is now.
    public var location: Point
    /// `location - start`.
    public var translation: Point
    /// The device kind.
    public var kind: PointerEvent.Kind
    /// The button that pressed.
    public var button: Int
    /// Modifiers held during the latest sample.
    public var modifiers: PointerEvent.Modifiers
    /// Scroll delta for ``Phase/scroll``; zero otherwise.
    public var scroll: Point
    /// The topmost registered drop target under ``location`` during a drag
    /// phase; `nil` for every other phase or when there is none.
    public var dropTarget: NodeID?

    /// Creates a gesture. ``translation`` is derived from `start` and `location`.
    public init(
        phase: Phase,
        start: Point,
        location: Point,
        kind: PointerEvent.Kind = .mouse,
        button: Int = 0,
        modifiers: PointerEvent.Modifiers = [],
        scroll: Point = .zero,
        dropTarget: NodeID? = nil
    ) {
        self.phase = phase
        self.start = start
        self.location = location
        self.translation = location - start
        self.kind = kind
        self.button = button
        self.modifiers = modifiers
        self.scroll = scroll
        self.dropTarget = dropTarget
    }
}
