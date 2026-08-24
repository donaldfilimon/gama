//  Runtime.swift — GamaCore
//  Backend-agnostic runtime: input events in, frames out. The runtime is
//  generic over its Renderer, so no existentials cross the hot path.
//  Errors are *typed* end-to-end (Swift 6 typed throws): a renderer
//  declares its Failure and AppRuntime.run() rethrows exactly that type
//  — `Never` for infallible renderers means callers need no `try` at all.

// MARK: - Events

public enum Key: Hashable, Sendable {
    case character(Character)
    case up, down, left, right
    case enter, escape, tab, backTab, backspace, delete
    case home, end, pageUp, pageDown
    case function(Int)
    case ctrl(Character)  // ctrl("c") etc.
}

public enum InputEvent: Hashable, Sendable {
    case key(Key)
    case resize(Size)
    case pointer(Point, pressed: Bool)
    case tick
}

// MARK: - Renderer protocol

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
    mutating func begin() throws(Failure)
    mutating func end() throws(Failure)
}

// MARK: - App

public protocol App: Sendable {
    associatedtype Content: View
    @ViewBuilder var content: Content { get }
    init()
}

// MARK: - Runtime

/// Blocking event loop for poll-style renderers (terminals). All frame,
/// focus, and action logic lives in `FrameHost`; this adds only the loop.
public struct AppRuntime<A: App, R: Renderer> {
    public var renderer: R
    public var frameTimeoutMillis: Int
    private var host: FrameHost<A>

    public init(app: A, renderer: R, frameTimeoutMillis: Int = 250) {
        self.host = FrameHost(app: app)
        self.renderer = renderer
        self.frameTimeoutMillis = frameTimeoutMillis
    }

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
