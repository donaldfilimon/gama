import Darwin
import GamaCore

public enum TerminalError: Error {
    case notATTY
    case tcsetattrFailed
    case ioctlFailed
}

public final class Terminal: @unchecked Sendable {
    nonisolated(unsafe) static var sigwinchFlag = false
    var original: termios?
    var entered = false
    var parser = KeyParser()
    var lastSize: Size?

    public init() {}

    deinit {
        restore()
    }

    public func enterRawMode() throws {
        if isatty(STDIN_FILENO) == 0 { throw TerminalError.notATTY }
        var current = termios()
        if tcgetattr(STDIN_FILENO, &current) != 0 { throw TerminalError.tcsetattrFailed }
        original = current
        var raw = current
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        raw.c_oflag &= ~tcflag_t(OPOST)
        if tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0 { throw TerminalError.tcsetattrFailed }
        _ = fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK)
        signal(SIGWINCH, winchHandler)
        try write("\u{1b}[?1049h\u{1b}[?25l\u{1b}[?1000h\u{1b}[?1006h")
        entered = true
    }

    public func restore() {
        guard entered else { return }
        entered = false
        _ = try? write("\u{1b}[?1006l\u{1b}[?1000l\u{1b}[?25h\u{1b}[?1049l")
        if var original {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
        _ = fcntl(STDIN_FILENO, F_SETFL, 0)
    }

    public func size() throws -> Size {
        var ws = winsize()
        if ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) != 0 {
            throw TerminalError.ioctlFailed
        }
        return Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
    }

    public func write(_ string: String) throws {
        string.withCString { ptr in
            _ = Darwin.write(STDOUT_FILENO, ptr, strlen(ptr))
        }
    }

    public func pollEvent() throws -> Event? {
        if Self.sigwinchFlag {
            Self.sigwinchFlag = false
            if let s = try? size() { return .resize(s) }
        }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = buf.withUnsafeMutableBytes { raw in
            Darwin.read(STDIN_FILENO, raw.baseAddress, 256)
        }
        if n > 0 {
            let events = parser.push(Array(buf.prefix(Int(n))))
            return events.first
        }
        return nil
    }
}

func winchHandler(_ sig: Int32) {
    Terminal.sigwinchFlag = true
}
