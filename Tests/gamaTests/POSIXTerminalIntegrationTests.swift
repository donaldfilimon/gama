#if canImport(Darwin)
import Darwin
import XCTest

@testable import GamaTUI
import GamaCore

final class POSIXTerminalIntegrationTests: XCTestCase {
    func testSplitEscapeAndUnicodeSequencesDecodeWithoutDataLoss() {
        var terminal = Terminal(inputFD: STDIN_FILENO, outputFD: STDOUT_FILENO)
        terminal.feedForTesting([0x1B, UInt8(ascii: "[")])
        XCTAssertNil(terminal.decodeForTesting())
        terminal.feedForTesting([UInt8(ascii: "A")])
        XCTAssertEqual(terminal.decodeForTesting(), .key(.up))

        terminal.feedForTesting([0xF0, 0x9F])
        XCTAssertNil(terminal.decodeForTesting())
        terminal.feedForTesting([0x99, 0x82])
        XCTAssertEqual(terminal.decodeForTesting(), .key(.character("🙂")))
    }

    func testNoncopyableRawModeSessionRestoresPTYTermios() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        XCTAssertEqual(openpty(&master, &slave, nil, nil, nil), 0)
        defer {
            close(master)
            close(slave)
        }

        var before = termios()
        XCTAssertEqual(tcgetattr(slave, &before), 0)
        var session = try RawModeSession(terminal: Terminal(inputFD: slave, outputFD: slave))
        var during = termios()
        XCTAssertEqual(tcgetattr(slave, &during), 0)
        XCTAssertEqual(during.c_lflag & tcflag_t(ECHO | ICANON), 0)
        try session.close()
        var after = termios()
        XCTAssertEqual(tcgetattr(slave, &after), 0)
        let inputMask = tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        XCTAssertEqual(after.c_iflag & inputMask, before.c_iflag & inputMask)
        XCTAssertEqual(after.c_oflag & tcflag_t(OPOST), before.c_oflag & tcflag_t(OPOST))
        XCTAssertEqual(after.c_cflag & tcflag_t(CS8), before.c_cflag & tcflag_t(CS8))
        let localMask = tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        XCTAssertEqual(after.c_lflag & localMask, before.c_lflag & localMask)
    }
}
#endif
