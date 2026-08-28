#if canImport(Darwin)
import Darwin
import GamaCore
@testable import GamaTUI
import Testing

private struct ResizePollContext {
    var terminal: Terminal
    let readyFD: Int32
    var receivedSize: Size?
    var failed = false
    var elapsedNanoseconds: UInt64 = 0
}

private func pollForDeliveredResize(
    _ rawContext: UnsafeMutableRawPointer
) -> UnsafeMutableRawPointer? {
    let context = rawContext.assumingMemoryBound(to: ResizePollContext.self)
    var unblocked = sigset_t()
    sigemptyset(&unblocked)
    sigaddset(&unblocked, SIGWINCH)
    pthread_sigmask(SIG_UNBLOCK, &unblocked, nil)

    var ready: UInt8 = 1
    _ = write(context.pointee.readyFD, &ready, 1)
    var start = timespec()
    var end = timespec()
    clock_gettime(CLOCK_MONOTONIC, &start)
    do {
        let event = try context.pointee.terminal.nextEvent(timeoutMillis: 5_000)
        if case .resize(let size)? = event {
            context.pointee.receivedSize = size
        } else {
            context.pointee.failed = true
        }
    } catch {
        context.pointee.failed = true
    }
    clock_gettime(CLOCK_MONOTONIC, &end)
    var seconds = end.tv_sec - start.tv_sec
    var nanoseconds = end.tv_nsec - start.tv_nsec
    if nanoseconds < 0 {
        seconds -= 1
        nanoseconds += 1_000_000_000
    }
    context.pointee.elapsedNanoseconds =
        UInt64(seconds) * 1_000_000_000 + UInt64(nanoseconds)
    return nil
}

/// Covers the process-global rescue that restores a terminal on the exit
/// paths Swift cannot see.
///
/// `RawModeSession.deinit` already handles every path the type system
/// controls; the gap is `SIGTERM`, `SIGHUP`, and `exit()`, where the process
/// dies with the tty still raw and the user's shell is left unusable. These
/// tests drive the rescue against a real PTY. The resize test sends a real
/// `SIGWINCH` to the thread blocked in `poll`, and the cleanup tests inspect
/// the process dispositions after the session closes.
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

        @Test("a clean close gives the host back every managed signal disposition")
        func cleanCloseRestoresHostDispositions() throws {
            let managedSignals = [SIGTERM, SIGHUP, SIGINT, SIGQUIT, SIGWINCH]
            var hostAction = sigaction()
            hostAction.__sigaction_u.__sa_handler = SIG_IGN
            sigemptyset(&hostAction.sa_mask)
            sigaddset(&hostAction.sa_mask, SIGUSR1)
            hostAction.sa_flags = Int32(SA_RESTART)

            let originalActions = UnsafeMutablePointer<sigaction>.allocate(
                capacity: managedSignals.count)
            originalActions.initialize(
                repeating: sigaction(), count: managedSignals.count)
            defer {
                for (index, signalNumber) in managedSignals.enumerated() {
                    sigaction(signalNumber, originalActions.advanced(by: index), nil)
                }
                originalActions.deinitialize(count: managedSignals.count)
                originalActions.deallocate()
            }
            for (index, signalNumber) in managedSignals.enumerated() {
                try #require(sigaction(
                    signalNumber,
                    &hostAction,
                    originalActions.advanced(by: index)
                ) == 0)
            }

            try withPTY { slave in
                var session = try RawModeSession(
                    terminal: Terminal(inputFD: slave, outputFD: slave))
                #expect(TerminalRescue.isActive)
                try session.close()
            }

            // C function pointers are not Equatable; compare bit patterns.
            let expected = unsafeBitCast(SIG_IGN, to: UInt.self)
            for signalNumber in managedSignals {
                var afterDisarm = sigaction()
                try #require(sigaction(signalNumber, nil, &afterDisarm) == 0)
                let restored = unsafeBitCast(
                    afterDisarm.__sigaction_u.__sa_handler, to: UInt.self)
                #expect(restored == expected, "signal \(signalNumber) was not restored")
                #expect(afterDisarm.sa_flags & Int32(SA_RESTART) != 0)
                #expect(sigismember(&afterDisarm.sa_mask, SIGUSR1) == 1)
            }
        }

        @Test("restoreNow puts termios back like the write-free signal path")
        func restoreNowRestoresTermios() throws {
            try withPTY { slave in
                var before = termios()
                try #require(tcgetattr(slave, &before) == 0)

                var session = try RawModeSession(
                    terminal: Terminal(inputFD: slave, outputFD: slave))
                var during = termios()
                try #require(tcgetattr(slave, &during) == 0)
                #expect(during.c_lflag & tcflag_t(ECHO | ICANON) == 0)

                // The full ordinary path and write-free SIGTERM/SIGHUP path share
                // this termios restoration. The session is deliberately NOT
                // closed first: this models the process dying while it is alive.
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

        @Test("SIGWINCH interrupts poll and becomes exactly one resize event")
        func windowChangeBecomesOneResize() throws {
            try withPTY { slave in
                var desiredSize = winsize(
                    ws_row: 31,
                    ws_col: 87,
                    ws_xpixel: 0,
                    ws_ypixel: 0
                )
                try #require(ioctl(slave, UInt(TIOCSWINSZ), &desiredSize) == 0)
                var session = try RawModeSession(
                    terminal: Terminal(inputFD: slave, outputFD: slave))

                let readyFDs = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
                readyFDs.initialize(repeating: -1, count: 2)
                try #require(pipe(readyFDs) == 0)
                defer {
                    close(readyFDs[0])
                    close(readyFDs[1])
                    readyFDs.deinitialize(count: 2)
                    readyFDs.deallocate()
                }

                let context = UnsafeMutablePointer<ResizePollContext>.allocate(
                    capacity: 1)
                context.initialize(to: ResizePollContext(
                    terminal: Terminal(inputFD: slave, outputFD: slave),
                    readyFD: readyFDs[1],
                    receivedSize: nil
                ))
                defer {
                    context.deinitialize(count: 1)
                    context.deallocate()
                }
                var signalThread: pthread_t?
                try #require(pthread_create(
                    &signalThread,
                    nil,
                    pollForDeliveredResize,
                    context
                ) == 0)
                var joinedSignalThread = false
                defer {
                    if let signalThread, !joinedSignalThread {
                        pthread_join(signalThread, nil)
                    }
                }

                var ready: UInt8 = 0
                try #require(read(readyFDs[0], &ready, 1) == 1)
                usleep(20_000)
                let deliveryTarget = try #require(signalThread)
                let deliveryResult = pthread_kill(deliveryTarget, SIGWINCH)
                #expect(deliveryResult == 0)
                if let signalThread {
                    pthread_join(signalThread, nil)
                    joinedSignalThread = true
                }

                #expect(!context.pointee.failed)
                #expect(context.pointee.receivedSize == Size(width: 87, height: 31))
                // A restarted five-second poll would finish near its timeout.
                // Returning well before that pins the intended EINTR path.
                #expect(context.pointee.elapsedNanoseconds < 2_000_000_000)

                // The latch is edge-triggered: one signal, one event. If it
                // stuck, the loop would rebuild every frame forever.
                let second = try session.nextEvent(timeoutMillis: 0)
                #expect(second == nil)
                try session.close()
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
