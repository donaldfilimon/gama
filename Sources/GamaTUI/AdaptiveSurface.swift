//  AdaptiveSurface.swift — GamaTUI
//  One binary, two presentations. A terminal wants raw mode, a
//  differential ANSI stream, and an input loop; a pipe, a file, or a CI
//  log wants plain lines, no termios, and no keyboard. The choice is made
//  once at startup from the descriptor, with explicit flags able to
//  override it, and the decision itself is a pure function so it can be
//  proven without allocating a pty.

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Android)
    import Android
#elseif canImport(WinSDK)
    import WinSDK
#endif

public import GamaCore
import GamaDraw

/// Whether this process's standard output is an interactive terminal.
///
/// Windows reaches this file without POSIX `isatty` or `STDOUT_FILENO` in
/// scope, and its console row is Blocked, so it reports `false` and takes
/// the descriptor-independent stream presentation rather than claiming an
/// interactive terminal it cannot drive.
private func stdoutIsTerminal() -> Bool {
    #if os(Windows)
        return false
    #else
        return isatty(STDOUT_FILENO) == 1
    #endif
}

/// Which presentation a terminal-family run should use.
public enum SurfaceMode: Hashable, Sendable {
    /// A real terminal: raw mode, differential ANSI, and an input loop.
    case interactive
    /// Not a terminal: plain lines, no termios state, and no input.
    case stream

    /// Forces the stream surface even on a terminal.
    public static let plainFlag = "--gama-plain"
    /// Forces the interactive surface even when redirected.
    public static let interactiveFlag = "--gama-tui"

    /// Chooses a mode from the descriptor and any explicit override.
    ///
    /// `isTerminal` is a parameter rather than an `isatty` call so the rule
    /// is testable without a pty. When both flags appear, the last one wins,
    /// which is the usual command-line convention and keeps the meaning
    /// independent of which flag an implementation checks first.
    public static func select(isTerminal: Bool, arguments: [String]) -> SurfaceMode {
        var mode: SurfaceMode = isTerminal ? .interactive : .stream
        for argument in arguments {
            if argument == plainFlag { mode = .stream }
            if argument == interactiveFlag { mode = .interactive }
        }
        return mode
    }

    /// Chooses a mode from this process's stdout and command line.
    public static func detect(arguments: [String] = CommandLine.arguments) -> SurfaceMode {
        select(isTerminal: stdoutIsTerminal(), arguments: arguments)
    }
}

/// Receives the lines a ``StreamRenderer`` produces.
///
/// A protocol rather than a hardcoded descriptor so the renderer's
/// behavior can be proven without writing to the process's real stdout.
public protocol StreamSink: AnyObject {
    /// Appends one line. Implementations add the line terminator.
    func write(_ line: String)
}

/// Writes lines to the process's standard output.
public final class StandardOutputSink: StreamSink {
    /// Creates a sink targeting file descriptor 1.
    public init() {}

    /// Writes `line` followed by a newline, resuming after `EINTR` and
    /// short writes until fully flushed.
    public func write(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                #if canImport(Darwin)
                    return unsafe Darwin.write(
                        STDOUT_FILENO, base.advanced(by: offset), buffer.count - offset)
                #elseif canImport(Glibc)
                    return unsafe Glibc.write(
                        STDOUT_FILENO, base.advanced(by: offset), buffer.count - offset)
                #elseif canImport(Musl)
                    return unsafe Musl.write(
                        STDOUT_FILENO, base.advanced(by: offset), buffer.count - offset)
                #elseif canImport(Android)
                    return unsafe Android.write(
                        STDOUT_FILENO, base.advanced(by: offset), buffer.count - offset)
                #else
                    // Windows has no write(2) here. Report zero rather than
                    // the byte count: claiming a successful write that never
                    // happened is worse than the guard below bailing out.
                    // The Windows console row is Blocked regardless.
                    return 0
                #endif
            }
            #if !os(Windows)
                // EINTR retry is POSIX-only; Windows has no `errno` here.
                if written < 0, errno == EINTR { continue }
            #endif
            guard written > 0 else { return }
            offset += written
        }
    }
}

/// The non-interactive `Renderer`: paints each frame through the shared
/// `CellPainter` and emits the rows that changed as plain lines.
///
/// It installs no termios state, registers no signal dispositions, and
/// reads no input, so it is safe in CI and in a pipe where there is no
/// terminal to corrupt and no disposition to restore. Its size is fixed
/// rather than queried, because a redirected descriptor has no extent.
public struct StreamRenderer: Renderer {
    /// Shares the terminal family's typed error.
    public typealias Failure = TerminalError

    private var buffer: CellBuffer
    private var presenter = StreamPresenter()
    private let sink: any StreamSink
    private var declaredLines: [String] = []

    /// Creates a renderer writing to `sink`, laying out at `size`.
    ///
    /// The default 80×24 matches the terminal renderer's pre-`begin()`
    /// default, so a layout does not change shape merely because output was
    /// redirected.
    public init(
        sink: any StreamSink = StandardOutputSink(),
        size: Size = Size(width: 80, height: 24)
    ) {
        var b = CellBuffer(size: size)
        b.trueColor = false
        self.buffer = b
        self.sink = sink
    }

    /// The fixed layout extent. A redirected descriptor has no live size.
    public var size: Size { buffer.size }

    /// Acquires nothing. Present to make the no-termios contract explicit.
    public mutating func begin() throws(TerminalError) {}

    /// Releases nothing, because `begin()` acquired nothing.
    public mutating func end() throws(TerminalError) {}

    /// Records semantic lines the application declared for this frame. They
    /// replace derivation, because derivation cannot invent text the grid
    /// never held.
    public mutating func emit(_ lines: [String]) throws(TerminalError) {
        declaredLines.append(contentsOf: lines)
    }

    /// Writes the lines the application declared, or, when it declared none,
    /// one line per row whose painted content changed.
    ///
    /// The buffer is reconciled either way, so a frame that was overridden
    /// still advances the diff and a later derived frame reports changes
    /// against what was actually drawn rather than against a stale grid.
    public mutating func present(_ root: LaidOutNode) throws(TerminalError) {
        buffer.clearBack()
        CellPainter.paint(root, into: &buffer)
        let derived = presenter.present(&buffer)
        if declaredLines.isEmpty {
            for line in derived { sink.write(line) }
        } else {
            for line in declaredLines { sink.write(line) }
            declaredLines.removeAll(keepingCapacity: true)
        }
    }

    /// A redirected run has no input source, so the loop ends when this
    /// renderer goes clean instead of waiting for a key that cannot arrive.
    public var waitsForInput: Bool { false }

    /// Always `nil`: a redirected run takes no input, so the loop never
    /// waits on a keyboard that is not there.
    public mutating func nextEvent(timeoutMillis: Int) throws(TerminalError) -> InputEvent? {
        nil
    }
}

extension App {
    /// Runs this application on whichever terminal-family surface suits the
    /// process's stdout, and returns the outcome it reported.
    ///
    /// A terminal gets ``TUIRenderer``: raw mode, differential ANSI, and the
    /// input loop. A redirected descriptor gets ``StreamRenderer``: plain
    /// lines, no termios, and no input. `--gama-plain` and `--gama-tui`
    /// override the detection.
    ///
    /// The returned status is the application's own report, or
    /// `CompletionStatus.success` when the loop ended because the user
    /// quit. This does **not** terminate the process: exiting is the
    /// caller's decision, which also keeps the path testable.
    ///
    /// ```swift
    /// let status = try MyApp.runAdaptive()
    /// exit(status.code)
    /// ```
    public static func runAdaptive(
        arguments: [String] = CommandLine.arguments
    ) throws(AppLaunchError<TerminalError>) -> CompletionStatus {
        let mode = SurfaceMode.select(
            isTerminal: stdoutIsTerminal(),
            arguments: arguments
        )
        switch mode {
        case .interactive:
            return try runTerminalLoop(renderer: TUIRenderer())
        case .stream:
            return try runTerminalLoop(renderer: StreamRenderer())
        }
    }

    private static func runTerminalLoop<R: Renderer>(
        renderer: R
    ) throws(AppLaunchError<TerminalError>) -> CompletionStatus
    where R.Failure == TerminalError {
        let runtime: AppRuntime<Self, R>
        do {
            runtime = try AppRuntime(app: Self(), renderer: renderer)
        } catch {
            throw .sceneConfiguration(error)
        }
        var live = consume runtime
        do {
            try live.run()
        } catch {
            throw .renderer(error)
        }
        guard let status = live.completion else { return .success }
        if let message = status.message { writeStandardError(message) }
        return status
    }
}

/// Writes one line to standard error, used for a completion message so it
/// never contaminates the stream surface's stdout chronology.
func writeStandardError(_ message: String) {
    let bytes = Array((message + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
        let written = bytes.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            #if canImport(Darwin)
                return unsafe Darwin.write(
                    STDERR_FILENO, base.advanced(by: offset), buffer.count - offset)
            #elseif canImport(Glibc)
                return unsafe Glibc.write(
                    STDERR_FILENO, base.advanced(by: offset), buffer.count - offset)
            #elseif canImport(Musl)
                return unsafe Musl.write(
                    STDERR_FILENO, base.advanced(by: offset), buffer.count - offset)
            #elseif canImport(Android)
                return unsafe Android.write(
                    STDERR_FILENO, base.advanced(by: offset), buffer.count - offset)
            #else
                // See StandardOutputSink.write: report zero, never a
                // successful write that did not happen.
                return 0
            #endif
        }
        #if !os(Windows)
            if written < 0, errno == EINTR { continue }
        #endif
        guard written > 0 else { return }
        offset += written
    }
}
