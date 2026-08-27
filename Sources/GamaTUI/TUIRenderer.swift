//  TUIRenderer.swift — GamaTUI
//  The concrete Renderer for terminals — POSIX and Windows Console alike
//  (Terminal.swift owns the platform split). Paints via the shared
//  CellPainter, then flushes the differential ANSI diff.

import GamaCore
import GamaDraw

/// The terminal `Renderer`: owns a `RawModeSession` and a double-buffered
/// `CellBuffer`, paints each laid-out frame through the shared
/// `CellPainter`, and writes only the differential ANSI update. One code
/// path drives POSIX and Windows Console terminals alike — `Terminal`
/// owns the platform split — and, like every backend, it only carries
/// events in and frames out; application semantics stay in GamaCore.
public final class TUIRenderer: Renderer {
    /// Terminal renderers fail with typed `TerminalError`s.
    public typealias Failure = TerminalError

    private var session: RawModeSession?
    private var buffer: CellBuffer
    private var began = false

    /// Creates a renderer that has not yet touched the terminal — call
    /// `begin()` to enter raw mode. `trueColor` selects 24-bit ANSI color
    /// output; pass `false` for terminals limited to the 256-color palette.
    public init(trueColor: Bool = true) {
        var b = CellBuffer(size: Size(width: 80, height: 24))
        b.trueColor = trueColor
        self.buffer = b
    }

    /// The live terminal size in character cells, or the 80×24 default
    /// before `begin()`.
    public var size: Size {
        session?.size() ?? Size(width: 80, height: 24)
    }

    /// Opens the raw-mode session and sizes the cell buffer to the live
    /// terminal. Idempotent — a second call before `end()` does nothing.
    public func begin() throws(TerminalError) {
        guard !began else { return }
        session = try RawModeSession(terminal: Terminal())
        buffer.resize(size)
        began = true
    }

    /// Closes the session, restoring the terminal. Idempotent — a no-op
    /// before `begin()` or after a previous `end()`.
    public func end() throws(TerminalError) {
        guard began else { return }
        try session?.close()
        session = nil
        began = false
    }

    /// Paints `root` into the back buffer — resizing it first if the
    /// terminal changed size — and writes the resulting ANSI diff, so only
    /// changed cells reach the terminal. Throws before `begin()`.
    public func present(_ root: LaidOutNode) throws(TerminalError) {
        guard began else { throw TerminalError("renderer has not begun") }
        let current = size
        if current != buffer.size { buffer.resize(current) }
        buffer.clearBack()
        CellPainter.paint(root, into: &buffer)
        let ansi = buffer.presentDiff()
        if !ansi.isEmpty { try session?.write(ansi) }
    }

    /// Waits up to `timeoutMillis` for the next `InputEvent`, synthesizing
    /// a `.resize` when the terminal size changed during the wait. Returns
    /// `nil` on an uneventful timeout; throws before `begin()`.
    public func nextEvent(timeoutMillis: Int) throws(TerminalError) -> InputEvent? {
        guard began else { throw TerminalError("renderer has not begun") }
        let before = buffer.size
        if let e = try session?.nextEvent(timeoutMillis: timeoutMillis) {
            return e
        }
        let now = size
        if now != before { return .resize(now) }
        return nil
    }
}
