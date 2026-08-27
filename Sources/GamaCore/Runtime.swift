//  Runtime.swift — GamaCore
//  Backend-agnostic runtime: input events in, frames out. The runtime is
//  generic over its Renderer, so no existentials cross the hot path.
//  Errors are *typed* end-to-end (Swift 6 typed throws): a renderer
//  declares its Failure and AppRuntime.run() rethrows exactly that type
//  — `Never` for infallible renderers means callers need no `try` at all.

// MARK: - Events

/// Decoded keyboard input in one backend-neutral vocabulary. Each backend
/// translates its native events (escape sequences, VT codes, platform key
/// events) into these values, so `FrameHost` and per-node key handlers
/// never see raw bytes.
public enum Key: Hashable, Sendable {
    /// A printable input as a full grapheme cluster, not a lone scalar.
    case character(Character)
    /// The up arrow key.
    case up
    /// The down arrow key.
    case down
    /// The left arrow key.
    case left
    /// The right arrow key.
    case right
    /// Return/Enter.
    case enter
    /// Escape (delivered after the escape-sequence timeout on terminals).
    case escape
    /// Tab — forward focus traversal.
    case tab
    /// Shift-Tab — reverse focus traversal.
    case backTab
    /// Backspace (delete backward).
    case backspace
    /// Forward delete.
    case delete
    /// Home.
    case home
    /// End.
    case end
    /// Page Up.
    case pageUp
    /// Page Down.
    case pageDown
    /// A function key by number — `function(1)` is F1.
    case function(Int)
    /// A control chord: the letter held with Ctrl.
    case ctrl(Character)  // ctrl("c") etc.
}

/// One normalized event fed to `FrameHost.handle(_:)`. Every backend maps
/// its platform input onto this shared set, which is what keeps interaction
/// semantics (focus, activation, quit) identical across backends.
public enum InputEvent: Hashable, Sendable {
    /// A decoded keystroke.
    case key(Key)
    /// The drawable area changed; the host marks itself dirty so the next
    /// pump lays out at the new size.
    case resize(Size)
    /// Pointer (mouse or touch) state at a cell position. Only presses
    /// (`pressed: true`) hit-test and activate; releases are accepted but
    /// trigger nothing in the host today.
    case pointer(Point, pressed: Bool)
    /// A timer pulse a backend may emit to wake its loop; the host itself
    /// takes no action on it.
    case tick
}

// MARK: - Renderer protocol

/// What a backend supplies to drive an app: a drawable size, a way to
/// present one laid-out frame, and a (possibly blocking) source of input
/// events. The runtime is generic over the concrete conformer, so frame
/// and event calls dispatch directly — no existentials on the hot path.
public protocol Renderer {
    /// The one error type this backend can produce. Defaults to `Never`
    /// so pure in-memory renderers stay `try`-free at call sites.
    associatedtype Failure: Error = Never

    /// Current drawable size in cells (TUI) or layout units (GUI).
    var size: Size { get }
    /// Present one laid-out frame.
    mutating func present(_ root: LaidOutNode) throws(Failure)
    /// Block up to `timeoutMillis` for the next event; nil on timeout.
    mutating func nextEvent(timeoutMillis: Int) throws(Failure) -> InputEvent?
    /// Acquire the presentation surface. `AppRuntime.run()` calls this
    /// once, before the first frame.
    mutating func begin() throws(Failure)
    /// Release whatever `begin()` acquired. `run()` invokes this from a
    /// `defer` on every exit path, discarding any error it throws.
    mutating func end() throws(Failure)
}

// MARK: - App

/// The application root: a value whose `content` describes the entire view
/// tree, rebuilt from current state on every frame pump. `Sendable` because
/// hosts may live on a backend-owned executor.
public protocol App: Sendable {
    /// The concrete root view type `content` produces.
    associatedtype Content: View
    /// The root of the view tree; evaluated afresh each pump so it always
    /// reflects current model state.
    @ViewBuilder var content: Content { get }
    /// Apps are constructed with no arguments, which is what lets
    /// `main(renderer:)` instantiate one on the caller's behalf.
    init()
}

// MARK: - Runtime

/// Blocking event loop for poll-style renderers (terminals). All frame,
/// focus, and action logic lives in `FrameHost`; this adds only the loop.
/// Noncopyable, like the host it owns: a running loop is not a value.
public struct AppRuntime<A: App, R: Renderer>: ~Copyable {
    /// The backend that presents frames and delivers events; owned by
    /// value for the lifetime of the loop.
    public var renderer: R
    /// Longest wait, per loop iteration, for the next input event. It is
    /// also the worst-case latency for out-of-band invalidations to become
    /// a frame: on timeout the loop re-checks `needsFrame`.
    public var frameTimeoutMillis: Int
    private var host: FrameHost<A>

    /// Wraps `app` in a fresh `FrameHost` and pairs it with `renderer`.
    /// Nothing runs until `run()` is called.
    public init(app: A, renderer: R, frameTimeoutMillis: Int = 250) {
        self.host = FrameHost(app: app)
        self.renderer = renderer
        self.frameTimeoutMillis = frameTimeoutMillis
    }

    /// Blocks in a present/handle loop until the host requests quit
    /// (Ctrl-C / Ctrl-Q by default). Frames are produced only while the
    /// host is dirty; idle iterations just wait on `nextEvent`. Rethrows
    /// exactly the renderer's `Failure`, and always attempts `end()` on
    /// the way out, discarding its error.
    public mutating func run() throws(R.Failure) {
        try renderer.begin()
        defer { try? renderer.end() }

        while !host.wantsQuit {
            if host.needsFrame {
                let laid = host.pump(size: renderer.size)
                try renderer.present(laid)
            }
            if let event = try renderer.nextEvent(timeoutMillis: frameTimeoutMillis) {
                host.handle(event)
            }
        }
    }
}

extension App {
    /// Convenience entry: `MyApp.main(renderer:)` from any backend.
    public static func main<R: Renderer>(renderer: R) throws(R.Failure) {
        var runtime = AppRuntime(app: Self(), renderer: renderer)
        try runtime.run()
    }
}
