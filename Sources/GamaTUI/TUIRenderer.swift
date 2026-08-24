//  TUIRenderer.swift — GamaTUI
//  The concrete Renderer for terminals — POSIX and Windows Console alike
//  (Terminal.swift owns the platform split). Paints via the shared
//  CellPainter, then flushes the differential ANSI diff.

import GamaCore
import GamaDraw

public final class TUIRenderer: Renderer {
    public typealias Failure = TerminalError

    private var session: RawModeSession?
    private var buffer: CellBuffer
    private var began = false

    public init(trueColor: Bool = true) {
        var b = CellBuffer(size: Size(width: 80, height: 24))
        b.trueColor = trueColor
        self.buffer = b
    }

    public var size: Size {
        session?.size() ?? Size(width: 80, height: 24)
    }

    public func begin() throws(TerminalError) {
        guard !began else { return }
        session = try RawModeSession(terminal: Terminal())
        buffer.resize(size)
        began = true
    }

    public func end() throws(TerminalError) {
        guard began else { return }
        try session?.close()
        session = nil
        began = false
    }

    public func present(_ root: LaidOutNode) throws(TerminalError) {
        guard began else { throw TerminalError("renderer has not begun") }
        let current = size
        if current != buffer.size { buffer.resize(current) }
        buffer.clearBack()
        CellPainter.paint(root, into: &buffer)
        let ansi = buffer.presentDiff()
        if !ansi.isEmpty { try session?.write(ansi) }
    }

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
