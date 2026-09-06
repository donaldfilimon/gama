//  StreamPresenter.swift — GamaDraw
//  A terminal consumes a differential ANSI stream; a pipe, a file, or a CI
//  log consumes a chronology. Both reconcile the same front/back buffers,
//  so the difference is only in what the reconciliation emits. Naming that
//  shared step lets a backend select a consumer without forking the
//  drawing layer.
//
//  Deliberately scoped to CellBuffer. A broader abstraction spanning the
//  DrawList-consuming backends (AppleUI, WASM, Embed) is not asserted here:
//  those differ in input type, output type, and whether they are
//  differential or wholesale, and whether one shape fits them is an open
//  question rather than an implementation detail.

import GamaCore

/// Reconciles a ``CellBuffer``'s pending frame into text for one kind of
/// consumer, then swaps the buffers.
///
/// Conforming types own no buffer of their own; the buffer is passed
/// `inout` so a backend can hold one grid and choose its presenter at
/// startup.
public protocol CellPresenter {
    /// The text this presenter produces for one reconciled frame.
    associatedtype Output

    /// Reconciles `buffer`'s back frame against its front frame, emits the
    /// result for this consumer, and swaps the buffers.
    mutating func present(_ buffer: inout CellBuffer) -> Output
}

/// Presents to a terminal as the minimal escape sequence reconciling the
/// frame, which is the behavior ``CellBuffer/presentDiff()`` has always
/// had. This type adds no behavior; it only gives that path a name in the
/// ``CellPresenter`` family so a backend can hold either presenter.
public struct AnsiPresenter: CellPresenter {
    /// Creates a presenter. It holds no state; the buffer owns the frames.
    public init() {}

    /// Returns the escape sequence reconciling front to back.
    public mutating func present(_ buffer: inout CellBuffer) -> String {
        buffer.presentDiff()
    }
}

/// Presents to a consumer that is not a terminal: emits the text of rows
/// whose content changed, and nothing for rows that did not.
///
/// The output is a chronology, not a snapshot. Repeating the whole frame
/// each time would be correct and unreadable, so an unchanged row produces
/// no line at all. Two consequences follow and are deliberate:
///
/// - A row that empties produces no blank line, because an empty line
///   carries no information to a log reader.
/// - Content that never reaches the cell grid cannot appear here. This
///   derivation cannot invent what was never drawn, which is why an author
///   who needs semantic output declares it rather than relying on this.
public struct StreamPresenter: CellPresenter {
    /// Creates a presenter that has not yet seen a frame.
    public init() {}

    /// Returns one line per row whose content changed since the last call.
    public mutating func present(_ buffer: inout CellBuffer) -> [String] {
        var lines: [String] = []
        for y in 0..<buffer.size.height where buffer.rowChanged(y) {
            let text = buffer.rowText(y)
            if !text.isEmpty { lines.append(text) }
        }
        _ = buffer.presentDiff()
        return lines
    }
}
