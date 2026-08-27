#if canImport(Darwin)
import Darwin
import GamaCore
@testable import GamaTUI
import Testing

/// Covers the process-global rescue that restores a terminal on the exit
/// paths Swift cannot see.
///
/// `RawModeSession.deinit` already handles every path the type system
/// controls; the gap is `SIGTERM`, `SIGHUP`, and `exit()`, where the process
/// dies with the tty still raw and the user's shell is left unusable. These
/// tests drive the rescue against a real PTY rather than asserting on
/// bookkeeping alone — `restoreNow()` is exactly what the signal handler
/// calls, so exercising it directly proves the restoration itself.
///
/// The suite is serialized: the rescue is process-global by necessity
/// (signal disposition is process-wide), so two of these running
/// concurrently would arm and disarm each other's state.
///
/// `.serialized` only orders tests *within* one suite, so this suite is
/// nested under ``TerminalProcessGlobalTests`` alongside every other suite
/// that builds a `RawModeSession`. Two top-level suites would otherwise run
/// concurrently and disarm each other — the `isActive` flag is a single
/// process-wide `sig_atomic_t`, not per-session state.
/// Parent suite for everything that touches the process-global terminal
/// rescue. `.serialized` propagates to nested suites, so no two PTY suites
/// can arm and disarm the shared `sig_atomic_t` concurrently.
@Suite("Terminal (process-global rescue)", .serialized)
struct TerminalProcessGlobalTests {}

extension TerminalProcessGlobalTests {
    @Suite("Terminal rescue", .serialized)
    struct TerminalRescueTests {
        /// Runs `body` with a fresh PTY pair, always closing both ends.
        private func withPTY(_ body: (Int32) throws -> Void) throws {
            var master: Int32 = -1
            var slave: Int32 = -1
            try #require(openpty(&master, &slave, nil, nil, nil) == 0)
            defer {
                close(master)
                close(slave)
            }
            try body(slave)
        }

        @Test("entering raw mode arms the rescue and a clean close disarms it")
        func rawModeArmsAndCleanCloseDisarms() throws {
            try withPTY { slave in
                var session = try RawModeSession(
                    terminal: Terminal(inputFD: slave, outputFD: slave))
                #expect(TerminalRescue.isActive)
                try session.close()
                // A session that restored the terminal itself must leave nothing
                // for the handler to redo — otherwise a later SIGTERM would
                // rewrite escape codes into an already-restored shell.
                #expect(!TerminalRescue.isActive)
            }
        }

        @Test("restoreNow puts termios back, which is what the signal path does")
        func restoreNowRestoresTermios() throws {
            try withPTY { slave in
                var before = termios()
                try #require(tcgetattr(slave, &before) == 0)

                var session = try RawModeSession(
                    terminal: Terminal(inputFD: slave, outputFD: slave))
                var during = termios()
                try #require(tcgetattr(slave, &during) == 0)
                #expect(during.c_lflag & tcflag_t(ECHO | ICANON) == 0)

                // Exactly what the SIGTERM/SIGHUP handler invokes. The session is
                // deliberately NOT closed first: this models the process dying
                // with the session still alive.
                TerminalRescue.restoreNow()

                var after = termios()
                try #require(tcgetattr(slave, &after) == 0)
                let localMask = tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
                #expect(after.c_lflag & localMask == before.c_lflag & localMask)
                #expect(!TerminalRescue.isActive)

                // Keep the session's own teardown from running against a PTY we
                // already restored; it is a no-op either way but this keeps the
                // test's intent explicit.
                try? session.close()
            }
        }

        @Test("restoreNow is idempotent, so handler and atexit cannot double-restore")
        func restoreIsIdempotent() throws {
            try withPTY { slave in
                var session = try RawModeSession(
                    terminal: Terminal(inputFD: slave, outputFD: slave))
                TerminalRescue.restoreNow()
                #expect(!TerminalRescue.isActive)
                // A signal can arrive while atexit handlers already run; the
                // second call must do nothing rather than write escape bytes
                // into a shell that has moved on.
                TerminalRescue.restoreNow()
                #expect(!TerminalRescue.isActive)
                try? session.close()
            }
        }

        @Test("a delivered window change becomes exactly one resize event")
        func windowChangeBecomesOneResize() throws {
            try withPTY { slave in
                var terminal = Terminal(inputFD: slave, outputFD: slave)
                _ = TerminalRescue.consumePendingResize()  // start from a clean latch

                TerminalRescue.simulateWindowChangeForTesting()
                let event = try terminal.nextEvent(timeoutMillis: 0)

                guard case .resize(let size)? = event else {
                    Issue.record("expected a resize event, got \(String(describing: event))")
                    return
                }
                #expect(size.width > 0)
                #expect(size.height > 0)

                // The latch is edge-triggered: one signal, one event. If it
                // stuck, the loop would rebuild every frame forever.
                let second = try terminal.nextEvent(timeoutMillis: 0)
                #expect(second == nil)
            }
        }

        @Test("the resize latch drains only once per signal")
        func resizeLatchDrainsOnce() {
            _ = TerminalRescue.consumePendingResize()
            TerminalRescue.simulateWindowChangeForTesting()
            #expect(TerminalRescue.consumePendingResize())
            #expect(!TerminalRescue.consumePendingResize())
        }
    }
}
#endif
