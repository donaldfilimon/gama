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
    /// A portable application or surface lifecycle transition.
    case lifecycle(LifecycleEvent)
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

/// The application root: a value whose scene graph declares every surface.
/// The shell creates one app value, while each live surface owns an
/// independent ``FrameHost``.
public protocol App {
    /// Concrete scene-list type produced by the application's scene builder.
    associatedtype Scenes: Scene
    /// Declarative scene graph evaluated once when the application launches.
    @SceneBuilder var scenes: Scenes { get }
    /// Apps are constructed with no arguments, which is what lets
    /// `main(renderer:)` instantiate one on the caller's behalf.
    init()
    /// Receives application-level events once and addressed window events for
    /// their affected surface. Reference-backed models may mutate here.
    func handleLifecycle(_ event: LifecycleEvent)
}

extension App {
    /// Default lifecycle handler for applications that do not observe lifecycle events.
    public func handleLifecycle(_ event: LifecycleEvent) {}
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
    private var pump: HostPump

    /// Wraps `app` in a fresh ``HostPump`` and pairs it with `renderer`.
    /// Nothing runs until `run()` is called.
    public init(
        app: A,
        renderer: R,
        frameTimeoutMillis: Int = 250
    ) throws(SceneConfigurationError) {
        self.pump = HostPump(host: try FrameHost(app: app), size: renderer.size)
        self.renderer = renderer
        self.frameTimeoutMillis = frameTimeoutMillis
    }

    /// Invalidates this runtime whenever `signal` changes, for model updates
    /// that arrive outside the renderer's input callbacks.
    public func observe<Value>(_ signal: Signal<Value>) {
        pump.observe(signal)
    }

    /// Blocks in a present/handle loop until the host requests quit
    /// (Ctrl-C / Ctrl-Q by default). Frames are produced only while the
    /// host is dirty; idle iterations just wait on `nextEvent`. Rethrows
    /// exactly the renderer's `Failure`, and always attempts `end()` on
    /// the way out, discarding its error.
    public mutating func run() throws(R.Failure) {
        try renderer.begin()
        pump.handleLifecycle(.didLaunch)
        // `begin()` may have taken the terminal and changed the drawable
        // extent. Re-sync through the pump so the first frame is laid out
        // at the real size, under the same eager policy as every later
        // resize rather than a special case.
        if renderer.size != pump.size {
            pump.handle(.resize(renderer.size))
        }
        defer {
            pump.handleLifecycle(.willTerminate)
            try? renderer.end()
        }

        // `size` is the current drawable extent, but a renderer is not
        // required to emit `.resize`. Track the last extent observed directly
        // so a silent resize is still reflected in layout. Do not compare to
        // `pump.size`: an explicit resize event may legitimately be newer than
        // a renderer whose `size` property has not caught up yet.
        var lastObservedRendererSize = renderer.size
        while !pump.wantsQuit {
            var inputTimeoutMillis = frameTimeoutMillis
            if renderer.size != lastObservedRendererSize {
                lastObservedRendererSize = renderer.size
                pump.handle(.resize(renderer.size))
            }
            if let advanced = pump.advance() {
                try renderer.present(advanced.frame)
                if advanced.followUp {
                    // A follow-up frame stays ahead of any blocking wait, but
                    // a zero-timeout poll still gives quit and resize input a
                    // chance to break a continuously invalidating render loop.
                    inputTimeoutMillis = 0
                }
            }
            if let event = try renderer.nextEvent(timeoutMillis: inputTimeoutMillis) {
                if case .resize(let size) = event, renderer.size == size {
                    // Avoid presenting the same resize twice when a renderer
                    // updates `size` and emits its explicit event together.
                    lastObservedRendererSize = size
                }
                pump.handle(event)
            }
        }
    }
}

extension App {
    /// Convenience entry: `MyApp.main(renderer:)` from any backend.
    public static func main<R: Renderer>(
        renderer: R
    ) throws(AppLaunchError<R.Failure>) {
        let runtime: AppRuntime<Self, R>
        do {
            runtime = try AppRuntime(app: Self(), renderer: renderer)
        } catch {
            throw .sceneConfiguration(error)
        }
        do {
            var runtime = consume runtime
            try runtime.run()
        } catch {
            throw .renderer(error)
        }
    }
}

/// Typed error from the convenience launch path, preserving the distinction
/// between scene validation and the renderer's declared failure.
public enum AppLaunchError<RendererFailure: Error>: Error {
    /// Scene validation failed before the renderer began.
    case sceneConfiguration(SceneConfigurationError)
    /// The renderer failed after successful scene initialization.
    case renderer(RendererFailure)
}
