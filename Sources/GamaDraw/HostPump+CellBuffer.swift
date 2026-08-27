import GamaCore

extension HostPump {
    /// The shared cell-buffer step: resize the buffer to match the pump,
    /// clear the back grid, paint the laid-out frame, then hand the painted
    /// buffer to `emit`.
    ///
    /// This is the whole of what the four backends used to duplicate. Each
    /// one kept its own copy of `resize → clearBack → paint → emit`, and
    /// each also kept its own buffer-resize fragment: GamaEmbed resized on
    /// the `.resize` event, GamaAppleUI compared `buffer.size` against the
    /// grid on every draw. Both collapse into the single check below, so a
    /// buffer can no longer be painted at a stale extent.
    ///
    /// `emit` borrows the painted buffer — it may read cells, diff, or
    /// serialize, but it cannot retain or mutate the buffer, so the pump
    /// keeps sole ownership of the grid between frames. Emission itself
    /// stays per-backend: ANSI diff, HTML, `DrawList` bytes, CoreGraphics.
    ///
    /// Returns `AdvanceOutcome.clean` without touching `buffer` when the
    /// host is clean, so an idle backend does no work.
    ///
    /// - Parameters:
    ///   - buffer: The backend's persistent grid, reused across frames.
    ///   - emit: Receives the painted buffer; its error type propagates.
    /// - Returns: Whether a frame was produced, and whether the host is
    ///   still dirty and needs another advance soon.
    public mutating func advance<E: Error>(
        into buffer: inout CellBuffer,
        emit: (borrowing CellBuffer) throws(E) -> Void
    ) throws(E) -> AdvanceOutcome {
        guard let advanced = advance() else { return .clean }
        buffer.resizeIfNeeded(size)
        buffer.clearBack()
        CellPainter.paint(advanced.frame, into: &buffer)
        try emit(buffer)
        return AdvanceOutcome(produced: true, followUp: advanced.followUp)
    }
}
