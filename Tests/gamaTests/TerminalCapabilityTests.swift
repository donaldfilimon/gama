//  TerminalCapabilityTests.swift — capability detection driving the cell diff.

import GamaCore
import GamaDraw
import GamaTUI
import Testing

@Suite("Terminal capabilities and cell diff")
struct TerminalCapabilityTests {
    @Test("an empty environment is unknown and emits no color or mode sequences")
    func emptyEnvironmentStaysUnknown() {
        let caps = TerminalCapabilities.detect(environment: [:])
        #expect(caps == .unknown)
        #expect(caps.colorDepth == .unknown)
        #expect(caps.mouse == .unknown)

        let enable = TerminalModeSequences.enable(caps)
        #expect(!enable.contains("1049"))
        #expect(!enable.contains("1000"))
        #expect(!enable.contains("1006"))
        #expect(!enable.contains("2004"))
        #expect(!enable.contains("1004"))
        #expect(enable.contains("?25l"))
        #expect(!TerminalModeSequences.disable(caps).contains("1049"))

        var buffer = CellBuffer(size: Size(width: 4, height: 1))
        buffer.colorDepth = caps.colorDepth
        buffer.put("X", at: .zero, style: TextStyle(foreground: .red))
        var presenter = AnsiPresenter()
        let frame = presenter.present(&buffer)
        #expect(frame.contains("X"))
        #expect(!frame.contains("38;2"))
        #expect(!frame.contains("38;5"))
        #expect(!frame.contains("0;31"))
    }

    @Test("NO_COLOR forces monochrome even when true color is advertised")
    func noColorWins() {
        let caps = TerminalCapabilities.detect(
            environment: ["NO_COLOR": "", "COLORTERM": "truecolor", "TERM": "xterm-256color"]
        )
        #expect(caps.colorDepth == .monochrome)
        #expect(caps.mouse == .supported)
    }

    @Test("xterm-256color enables known modes and encodes 256 color")
    func xterm256EnablesKnownModes() {
        let caps = TerminalCapabilities.detect(environment: ["TERM": "xterm-256color"])
        #expect(caps.colorDepth == .ansi256)
        #expect(caps.mouse == .supported)
        #expect(caps.alternateScreen == .supported)
        #expect(caps.bracketedPaste == .supported)
        #expect(caps.focusReporting == .supported)
        #expect(caps.hyperlinks == .unknown)

        let enable = TerminalModeSequences.enable(caps)
        #expect(enable.contains("?1049h"))
        #expect(enable.contains("?1000h"))
        #expect(enable.contains("?1006h"))
        #expect(enable.contains("?2004h"))
        #expect(enable.contains("?1004h"))
        #expect(TerminalModeSequences.disable(caps).contains("?1049l"))

        var buffer = CellBuffer(size: Size(width: 4, height: 1))
        buffer.colorDepth = caps.colorDepth
        buffer.put("X", at: .zero, style: TextStyle(foreground: .red))
        var presenter = AnsiPresenter()
        let frame = presenter.present(&buffer)
        #expect(frame.contains("38;5;"))
        #expect(!frame.contains("38;2;"))
    }

    @Test("COLORTERM truecolor is encoded as 24-bit in the cell diff")
    func trueColorIsEncodedInTheDiff() {
        let caps = TerminalCapabilities.detect(
            environment: ["COLORTERM": "truecolor", "TERM": "xterm-256color"]
        )
        #expect(caps.colorDepth == .trueColor)
        var buffer = CellBuffer(size: Size(width: 4, height: 1))
        buffer.colorDepth = caps.colorDepth
        buffer.put("X", at: .zero, style: TextStyle(foreground: .red))
        var presenter = AnsiPresenter()
        let frame = presenter.present(&buffer)
        #expect(frame.contains("38;2;224;64;64"))
    }

    @Test("a dumb terminal enables nothing optional")
    func dumbTerminalEnablesNothing() {
        let caps = TerminalCapabilities.detect(environment: ["TERM": "dumb", "LANG": "C"])
        #expect(caps.colorDepth == .monochrome)
        #expect(caps.unicode == .unsupported)
        #expect(caps.mouse == .unsupported)
        #expect(caps.alternateScreen == .unsupported)
        #expect(caps.hyperlinks == .unsupported)
        let enable = TerminalModeSequences.enable(caps)
        #expect(!enable.contains("1049"))
        #expect(!enable.contains("1000"))
    }

    @Test("kitty with a UTF-8 locale reports hyperlinks and unicode, not a guessed palette")
    func kittyReportsHyperlinksWithoutGuessingColor() {
        let caps = TerminalCapabilities.detect(
            environment: ["TERM": "kitty", "LANG": "en_US.UTF-8"]
        )
        #expect(caps.hyperlinks == .supported)
        #expect(caps.unicode == .supported)
        #expect(caps.colorDepth == .unknown)
        #expect(caps.mouse == .supported)
    }

    @Test("screen does not gain focus reporting")
    func screenDoesNotGainFocusReporting() {
        let caps = TerminalCapabilities.detect(environment: ["TERM": "screen-256color"])
        #expect(caps.colorDepth == .ansi256)
        #expect(caps.focusReporting == .unknown)
        #expect(caps.mouse == .supported)
        #expect(!TerminalModeSequences.enable(caps).contains("1004"))
    }

    @Test("vt100 is 16-color and the diff does not emit a 256-color code")
    func vt100UsesAnsi16() {
        let caps = TerminalCapabilities.detect(environment: ["TERM": "vt100"])
        #expect(caps.colorDepth == .ansi16)
        #expect(caps.mouse == .unsupported)
        var buffer = CellBuffer(size: Size(width: 4, height: 1))
        buffer.colorDepth = caps.colorDepth
        buffer.put("X", at: .zero, style: TextStyle(foreground: .red))
        var presenter = AnsiPresenter()
        let frame = presenter.present(&buffer)
        #expect(frame.contains("0;31"))
        #expect(!frame.contains("38;"))
    }

    @Test("a second frame emits only the cell that changed")
    func secondFrameEmitsOnlyTheChangedCell() {
        var buffer = CellBuffer(size: Size(width: 5, height: 1))
        buffer.colorDepth = .monochrome
        buffer.put("A", at: Point(x: 0, y: 0), style: .plain)
        buffer.put("B", at: Point(x: 2, y: 0), style: .plain)
        var presenter = AnsiPresenter()
        let first = presenter.present(&buffer)
        #expect(first.contains("A"))
        #expect(first.contains("B"))

        buffer.clearBack()
        buffer.put("A", at: Point(x: 0, y: 0), style: .plain)
        buffer.put("C", at: Point(x: 2, y: 0), style: .plain)
        let second = presenter.present(&buffer)
        #expect(second.contains("C"))
        #expect(!second.contains("A"))
        #expect(!second.contains("B"))

        buffer.clearBack()
        buffer.put("A", at: Point(x: 0, y: 0), style: .plain)
        buffer.put("C", at: Point(x: 2, y: 0), style: .plain)
        #expect(presenter.present(&buffer).isEmpty)
    }

    @Test("current is stable for this process")
    func currentIsStable() {
        #expect(TerminalCapabilities.current() == TerminalCapabilities.current())
    }
}
