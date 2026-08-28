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
/// Handlers, restore bytes, `termios`, file descriptors, displaced
/// dispositions, and `sig_atomic_t` latches all live in `GamaTUISignal`.
/// Swift only enters the C lifecycle API from ordinary execution, so no Swift
/// runtime call, `String`, array, lazy/static initialization, or lock is
/// reachable from handler context.
enum TerminalRescue {
    /// Whether a rescue is currently installed.
    static var isActive: Bool { gama_tui_signal_is_armed() != 0 }

    /// Records the terminal state to restore and installs the handlers.
    ///
    /// Called from `enterRawMode()` once raw mode is actually in effect, so
    /// the rescue is never armed for a terminal that was never modified.
    static func arm(
        inputFD: Int32,
        outputFD: Int32,
        original: termios
    ) throws(TerminalError) {
        var original = original
        let result = gama_tui_signal_arm(inputFD, outputFD, &original)
        if result != 0 {
            throw TerminalError("terminal signal rescue setup failed (errno \(result))")
        }
    }

    /// Stops rescuing — the owning session restored the terminal itself.
    ///
    /// Clearing the armed flag first makes Gama's handlers no-ops for a signal
    /// already in flight. The host's original dispositions are then restored.
    static func disarm() throws(TerminalError) {
        let result = gama_tui_signal_disarm()
        if result != 0 {
            throw TerminalError("terminal signal rescue teardown failed (errno \(result))")
        }
    }

    /// Runs the full ordinary/`atexit` restoration, including presentation
    /// escape bytes. The C fatal-signal handler deliberately uses its write-free
    /// termios-only path so a full blocking output queue cannot trap it.
    static func restoreNow() {
        gama_tui_signal_restore_now()
    }

    /// True exactly once per delivered `SIGWINCH`.
    ///
    /// The handler only sets a flag — the smallest thing a handler may do —
    /// and the event loop turns that into a `.resize` on its next poll.
    static func consumePendingResize() -> Bool {
        gama_tui_signal_take_resize_pending() != 0
    }

    /// Test seam: pretend a `SIGWINCH` arrived, without signalling the
    /// process and disturbing a concurrently running test.
    static func simulateWindowChangeForTesting() {
        gama_tui_signal_mark_resize_pending()
    }
}

#endif
