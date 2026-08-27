#if canImport(Darwin)
import Darwin
import GamaCore
@testable import GamaTUI
import Testing

/// Nested under ``TerminalProcessGlobalTests``: `noncopyableRawModeSession…`
/// builds a `RawModeSession`, which arms and disarms the process-global
/// `TerminalRescue`. As a top-level suite it ran concurrently with the
/// rescue suite and the two disarmed each other's state.
extension TerminalProcessGlobalTests {
    @Suite("POSIX terminal")
    struct POSIXTerminalIntegrationTests {
        @Test("split escape and unicode sequences decode without data loss")
        func splitEscapeAndUnicodeSequencesDecodeWithoutDataLoss() {
            var terminal = Terminal(inputFD: STDIN_FILENO, outputFD: STDOUT_FILENO)
            terminal.feedForTesting([0x1B, UInt8(ascii: "[")])
            #expect(terminal.decodeForTesting() == nil)
            terminal.feedForTesting([UInt8(ascii: "A")])
            #expect(terminal.decodeForTesting() == .key(.up))

            terminal.feedForTesting([0xF0, 0x9F])
            #expect(terminal.decodeForTesting() == nil)
            terminal.feedForTesting([0x99, 0x82])
            #expect(terminal.decodeForTesting() == .key(.character("🙂")))
        }

        @Test("noncopyable raw-mode session restores PTY termios")
        func noncopyableRawModeSessionRestoresPTYTermios() throws {
            var master: Int32 = -1
            var slave: Int32 = -1
            #expect(openpty(&master, &slave, nil, nil, nil) == 0)
            defer {
                close(master)
                close(slave)
            }

            var before = termios()
            #expect(tcgetattr(slave, &before) == 0)
            var session = try RawModeSession(terminal: Terminal(inputFD: slave, outputFD: slave))
            var during = termios()
            #expect(tcgetattr(slave, &during) == 0)
            #expect(during.c_lflag & tcflag_t(ECHO | ICANON) == 0)
            try session.close()
            var after = termios()
            #expect(tcgetattr(slave, &after) == 0)
            let inputMask = tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
            #expect(after.c_iflag & inputMask == before.c_iflag & inputMask)
            #expect(after.c_oflag & tcflag_t(OPOST) == before.c_oflag & tcflag_t(OPOST))
            #expect(after.c_cflag & tcflag_t(CS8) == before.c_cflag & tcflag_t(CS8))
            let localMask = tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
            #expect(after.c_lflag & localMask == before.c_lflag & localMask)
        }
    }
}
#endif
