#if !os(Windows)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

import GamaCore
import GamaTUISignal

/// Process-global rescue for a terminal left in raw mode.
///
/// `RawModeSession.deinit` restores the terminal on every path Swift
/// controls — normal return, thrown error, early exit. It cannot help on the
/// paths Swift does *not* control: `SIGTERM` from a supervisor, `SIGHUP` when
/// the terminal goes away, or a `exit()` from library code. On those, the
/// process dies with the tty still in raw mode: no echo, no line editing, no
/// cursor. The user's shell is left unusable and has to be reset blind.
///
/// This type closes that gap with the only mechanism signals allow, which is
/// process-global state. That is a deliberate exception, not an oversight:
/// signal disposition *is* process-wide, so a per-host registry could not
/// work. It is confined to GamaTUI — `check-boundaries.sh` still forbids
/// process-global state in GamaCore, GamaPlugin, and GamaEmbed.
///
/// ## Async-signal-safety
///
/// Everything reachable from a handler here is on POSIX's async-signal-safe
/// list: `write`, `tcsetattr`, `sigaction`, and `raise`. In particular the
/// escape sequence is a ``StaticString``, whose bytes live in static storage,
/// so emitting it allocates nothing. No Swift runtime call, no `String`, no
/// array, and no lock is touched from handler context.
enum TerminalRescue {
    /// Termios captured at raw-mode entry, replayed by the handler.
    nonisolated(unsafe) private static var savedTermios = termios()
    /// The tty to restore, or -1 when nothing is armed.
    nonisolated(unsafe) private static var savedInputFD: Int32 = -1
    /// The tty to write the un-styling escape sequence to.
    nonisolated(unsafe) private static var savedOutputFD: Int32 = -1
    /// Whether `atexit` has been registered; registering twice would
    /// restore twice, which is harmless but noisy.
    nonisolated(unsafe) private static var atexitRegistered = false
    /// Dispositions displaced by ``arm()``, replayed by ``disarm()``.
    nonisolated(unsafe) private static var previousTerm = sigaction()
    nonisolated(unsafe) private static var previousHup = sigaction()
    nonisolated(unsafe) private static var previousInt = sigaction()
    nonisolated(unsafe) private static var previousQuit = sigaction()
    nonisolated(unsafe) private static var previousWinch = sigaction()
    /// Whether the `previous*` slots contain the host's dispositions rather
    /// than handlers installed by an earlier Gama arm.
    nonisolated(unsafe) private static var hasSavedDispositions = false

    /// Leave alt-screen, disable mouse reporting, reset SGR, show cursor.
    /// Static storage, so writing it from a signal handler is allocation-free.
    private static let restoreSequence: StaticString =
        "\u{1B}[?1006l\u{1B}[?1000l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l"

    /// Whether a rescue is currently installed.
    static var isActive: Bool { gama_tui_get_armed() != 0 }

    /// Records the terminal state to restore and installs the handlers.
    ///
    /// Called from `enterRawMode()` once raw mode is actually in effect, so
    /// the rescue is never armed for a terminal that was never modified.
    static func arm(inputFD: Int32, outputFD: Int32, original: termios) {
        savedTermios = original
        savedInputFD = inputFD
        savedOutputFD = outputFD
        gama_tui_set_armed(1)

        // Only the first arm captures dispositions; a nested arm must not
        // overwrite the host's saved handlers with Gama's own handlers.
        if !hasSavedDispositions {
            install(SIGTERM, saving: &previousTerm)
            install(SIGHUP, saving: &previousHup)
            // SIGINT and SIGQUIT are included for the case where raw mode
            // failed to clear ISIG, or a child restored default discipline.
            install(SIGINT, saving: &previousInt)
            install(SIGQUIT, saving: &previousQuit)
            installWinch(saving: &previousWinch)
            hasSavedDispositions = true
        }

        if !atexitRegistered {
            atexitRegistered = true
            atexit { TerminalRescue.restoreNow() }
        }
    }

    /// Stops rescuing — the owning session restored the terminal itself.
    ///
    /// Clearing the armed flag first makes Gama's handlers no-ops for a signal
    /// already in flight. The host's original dispositions are then restored.
    static func disarm() {
        gama_tui_set_armed(0)
        savedInputFD = -1
        savedOutputFD = -1
        guard hasSavedDispositions else { return }
        hasSavedDispositions = false
        sigaction(SIGTERM, &previousTerm, nil)
        sigaction(SIGHUP, &previousHup, nil)
        sigaction(SIGINT, &previousInt, nil)
        sigaction(SIGQUIT, &previousQuit, nil)
        sigaction(SIGWINCH, &previousWinch, nil)
    }

    /// The restoration itself. Safe to call from a signal handler, from
    /// `atexit`, or directly.
    static func restoreNow() {
        guard gama_tui_get_armed() != 0 else { return }
        gama_tui_set_armed(0)
        let outputFD = savedOutputFD
        if outputFD >= 0 {
            restoreSequence.withUTF8Buffer { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                // Short write is possible on a slow tty; loop, but never
                // block forever on a dead reader — EAGAIN/EIO ends it.
                while offset < bytes.count {
                    let n = write(outputFD, base + offset, bytes.count - offset)
                    if n <= 0 { break }
                    offset += n
                }
            }
        }
        if savedInputFD >= 0 {
            // TCSANOW, not TCSAFLUSH: cleanup must not wait on an output
            // queue whose reader has already gone away.
            _ = tcsetattr(savedInputFD, TCSANOW, &savedTermios)
        }
    }

    /// True exactly once per delivered `SIGWINCH`.
    ///
    /// The handler only sets a flag — the smallest thing a handler may do —
    /// and the event loop turns that into a `.resize` on its next poll.
    static func consumePendingResize() -> Bool {
        gama_tui_take_resize_pending() != 0
    }

    /// Test seam: pretend a `SIGWINCH` arrived, without signalling the
    /// process and disturbing a concurrently running test.
    static func simulateWindowChangeForTesting() { gama_tui_set_resize_pending(1) }

    // MARK: - Handler installation

    private static func install(_ signalNumber: Int32, saving previous: inout sigaction) {
        var action = sigaction()
        // Re-raise with the default disposition so the process still dies of
        // the signal it was sent, and its exit status stays truthful for
        // whatever supervises it.
        let handler: @convention(c) (Int32) -> Void = { signalNumber in
            TerminalRescue.restoreNow()
            signal(signalNumber, SIG_DFL)
            raise(signalNumber)
        }
        #if canImport(Darwin)
        action.__sigaction_u.__sa_handler = handler
        #elseif canImport(Glibc)
        action.__sigaction_handler.sa_handler = handler
        #else
        // musl nests the union as `__sa_handler`.
        action.__sa_handler.sa_handler = handler
        #endif
        sigemptyset(&action.sa_mask)
        action.sa_flags = 0
        sigaction(signalNumber, &action, &previous)
    }

    private static func installWinch(saving previous: inout sigaction) {
        var action = sigaction()
        let handler: @convention(c) (Int32) -> Void = { _ in
            TerminalRescue.markResizePending()
        }
        #if canImport(Darwin)
        action.__sigaction_u.__sa_handler = handler
        #elseif canImport(Glibc)
        action.__sigaction_handler.sa_handler = handler
        #else
        action.__sa_handler.sa_handler = handler
        #endif
        sigemptyset(&action.sa_mask)
        // SA_RESTART so a pending read is resumed rather than failing with
        // EINTR every time the window changes.
        action.sa_flags = Int32(SA_RESTART)
        sigaction(SIGWINCH, &action, &previous)
    }

    /// Separate entry point because a C function pointer cannot capture,
    /// and assigning to a `static var` from the closure needs a named
    /// function to stay allocation-free.
    fileprivate static func markResizePending() { gama_tui_set_resize_pending(1) }
}

#endif
