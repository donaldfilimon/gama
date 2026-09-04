//  Terminal.swift — GamaTUI
//  Platform terminal control:
//    · POSIX (macOS/Linux/BSD): termios raw mode + ANSI, decoded byte-wise
//    · Windows: Console API — VT output enabled, events via
//      ReadConsoleInputW (no ANSI input parsing needed)
//  Both speak the same ANSI dialect on output, so CellBuffer's diff
//  stream renders identically everywhere. Errors are typed
//  (`TerminalError`) end-to-end.

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Android)
    import Android
#elseif os(Windows)
    import WinSDK
#endif

public import GamaCore

/// The typed failure for every throwing GamaTUI operation — raw-mode entry
/// and exit, writes, and event polling all `throws(TerminalError)`, so a
/// terminal failure never surfaces as an untyped error.
public struct TerminalError: Error, Sendable {
    /// Human-readable description of the failing system or console call.
    public let message: String
    /// Creates an error carrying `message`.
    public init(_ message: String) { self.message = message }
}

/// Scoped raw-mode guard (Swift 6 noncopyable). Owning one *is* being in
/// raw mode; it cannot be duplicated, and `deinit` restores the terminal
/// even on early exits — the type system enforces cleanup.
public struct RawModeSession: ~Copyable {
    private var terminal: Terminal

    /// Consumes `terminal`, switches it into raw mode, and ties its
    /// restoration to this session's lifetime. Throws when raw mode cannot
    /// be entered (for example, when stdin is not a tty).
    public init(terminal: consuming Terminal) throws(TerminalError) {
        var t = terminal
        try t.enterRawMode()
        self.terminal = t
    }

    /// Runs `body` with mutable access to the owned terminal — the escape
    /// hatch for operations the session does not wrap itself.
    public mutating func withTerminal<T>(_ body: (inout Terminal) -> T) -> T {
        body(&terminal)
    }

    /// The current terminal size in character cells.
    public func size() -> Size { terminal.size() }
    /// Writes `string` — typically `CellBuffer`'s ANSI diff stream — to the
    /// raw terminal.
    public mutating func write(_ string: String) throws(TerminalError) { try terminal.write(string) }
    /// Waits up to `timeoutMillis` for one decoded `InputEvent`; `nil` on
    /// timeout.
    public mutating func nextEvent(timeoutMillis: Int) throws(TerminalError) -> InputEvent? {
        try terminal.nextEvent(timeoutMillis: timeoutMillis)
    }
    /// Restores the terminal deliberately, surfacing any restoration
    /// failure that `deinit`'s best-effort cleanup would swallow.
    public mutating func close() throws(TerminalError) { try terminal.exitRawModeChecked() }

    deinit {
        var t = terminal
        t.exitRawMode()
    }
}

#if !os(Windows)

// MARK: - POSIX implementation

/// POSIX terminal backend (macOS/Linux/BSD): termios raw mode on standard
/// input/output with byte-wise input decoding. Incoming bytes are buffered
/// and decoded incrementally — CSI and SS3 escape sequences, SGR mouse
/// reports, control characters, and multi-byte UTF-8 text all become
/// `InputEvent`s. Output is plain ANSI, so `CellBuffer`'s diff stream is
/// written verbatim.
public struct Terminal: ~Copyable {
    private let inputFD: Int32
    private let outputFD: Int32
    private var originalTermios = termios()
    private var isRaw = false
    private var pendingBytes: [UInt8] = []
    private let inputClock = ContinuousClock()
    private var loneEscapeStartedAt: ContinuousClock.Instant?
    /// Reused read buffer: one heap allocation for the session instead of
    /// one per nextEvent call.
    private var readBuffer = [UInt8](repeating: 0, count: 64)

    /// Creates a terminal bound to standard input and standard output.
    public init() {
        inputFD = STDIN_FILENO
        outputFD = STDOUT_FILENO
    }

    init(inputFD: Int32, outputFD: Int32) {
        self.inputFD = inputFD
        self.outputFD = outputFD
    }

    // MARK: Raw mode

    /// Switches the tty into raw mode (no echo, no line buffering, no
    /// signal keys), then enters the alternate screen, hides the cursor,
    /// clears, and enables SGR mouse reporting. The pre-raw termios state
    /// is saved for restoration. Throws when stdin is not a tty or the
    /// mode cannot be applied; a failed screen setup restores the terminal
    /// before rethrowing.
    public mutating func enterRawMode() throws(TerminalError) {
        guard unsafe tcgetattr(inputFD, &originalTermios) == 0 else {
            throw TerminalError("tcgetattr failed — stdin is not a tty")
        }
        var raw = originalTermios
        // cfmakeraw equivalent, spelled out for portability.
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            unsafe cc[Int(VMIN)] = 0
            unsafe cc[Int(VTIME)] = 0
        }
        guard unsafe tcsetattr(inputFD, TCSAFLUSH, &raw) == 0 else {
            throw TerminalError("tcsetattr failed")
        }
        isRaw = true
        // Arm the process-global rescue only now that raw mode is really in
        // effect, so a terminal that was never modified is never "restored".
        do {
            try TerminalRescue.arm(
                inputFD: inputFD, outputFD: outputFD, original: originalTermios)
        } catch {
            _ = unsafe tcsetattr(inputFD, TCSANOW, &originalTermios)
            isRaw = false
            throw error
        }
        // Alternate screen, hide cursor, clear.
        do {
            try write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J\u{1B}[H")
            try write("\u{1B}[?1000h\u{1B}[?1006h")
        } catch {
            exitRawMode()
            throw error
        }
    }

    /// Best-effort restoration — `exitRawModeChecked()` with the failure
    /// swallowed, safe to call from cleanup paths such as `deinit`.
    public mutating func exitRawMode() {
        try? exitRawModeChecked()
    }

    /// Leaves the alternate screen, disables mouse reporting, re-shows the
    /// cursor, and restores the saved termios with `TCSANOW` so cleanup
    /// cannot block on a stalled output queue. A no-op when not in raw
    /// mode; throws the first failure encountered after attempting every
    /// restoration step.
    public mutating func exitRawModeChecked() throws(TerminalError) {
        guard isRaw else { return }
        var firstError: TerminalError?
        do { try write("\u{1B}[?1006l\u{1B}[?1000l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l") }
        catch { firstError = error }
        // Restoration must not wait for an output queue (notably a PTY whose
        // reader has stopped after a crash); TCSANOW makes cleanup bounded.
        if unsafe tcsetattr(inputFD, TCSANOW, &originalTermios) != 0, firstError == nil {
            firstError = TerminalError("tcsetattr restoration failed")
        }
        isRaw = false
        // The session restored the terminal itself; the signal rescue has
        // nothing left to do and must not restore a second time.
        do { try TerminalRescue.disarm() }
        catch {
            if firstError == nil { firstError = error }
        }
        if let firstError { throw firstError }
    }

    // MARK: Size

    /// The window size in character cells via `TIOCGWINSZ`, falling back
    /// to 80×24 when the query fails or reports a degenerate size.
    public func size() -> Size {
        var ws = winsize()
        if unsafe ioctl(outputFD, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
        }
        return Size(width: 80, height: 24)
    }

    // MARK: Output

    /// Writes the UTF-8 bytes of `s`, resuming after `EINTR` and short
    /// writes until fully flushed.
    public func write(_ s: String) throws(TerminalError) {
        let bytes = Array(s.utf8)
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeBytes { buf -> Int in
                guard let base = buf.baseAddress else { return 0 }
                #if canImport(Darwin)
                    return unsafe Darwin.write(outputFD, base.advanced(by: off), buf.count - off)
                #elseif canImport(Glibc)
                    return unsafe Glibc.write(outputFD, base.advanced(by: off), buf.count - off)
                #elseif canImport(Musl)
                    return unsafe Musl.write(outputFD, base.advanced(by: off), buf.count - off)
                #elseif canImport(Android)
                    return unsafe Android.write(outputFD, base.advanced(by: off), buf.count - off)
                #endif
            }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { throw TerminalError("terminal write failed") }
            off += n
        }
    }

    // MARK: Input

    /// Block up to `timeoutMillis`; decode one event.
    public mutating func nextEvent(timeoutMillis: Int) throws(TerminalError) -> InputEvent? {
        // A delivered SIGWINCH outranks buffered input: the window already
        // changed, so decoding a keystroke against the old extent would lay
        // it out at a size that no longer exists. Draining the latch here
        // also means resize no longer waits for the poll timeout to expire,
        // which was the old "observed by polling the size after an event
        // timeout" behavior.
        if TerminalRescue.consumePendingResize() {
            return .resize(size())
        }
        if let event = decodeOne() { return event }
        let hasLoneEscape = pendingBytes.count == 1 && pendingBytes[0] == 0x1B
        if hasLoneEscape && loneEscapeGraceExpired() {
            pendingBytes.removeAll(keepingCapacity: true)
            loneEscapeStartedAt = nil
            return .key(.escape)
        }
        let hasPartialSequence = !pendingBytes.isEmpty
        do {
            var fds = pollfd(fd: inputFD, events: Int16(POLLIN), revents: 0)
            let wait = hasPartialSequence ? min(max(0, timeoutMillis), 25) : max(0, timeoutMillis)
            let r = unsafe poll(&fds, 1, Int32(wait))
            if r < 0 {
                if errno == EINTR {
                    // poll is not restartable on every supported libc even
                    // with SA_RESTART. Drain a SIGWINCH latch on this path so
                    // the same resize is not observed again on the next call.
                    if TerminalRescue.consumePendingResize() {
                        return .resize(size())
                    }
                    return nil
                }
                throw TerminalError("terminal poll failed")
            }
            // Some kernels restart poll despite the handler not requesting
            // SA_RESTART. Drain after every successful return as well, so a
            // SIGWINCH delivered during the wait cannot slip to the next
            // runtime iteration merely because poll eventually timed out or
            // input became ready.
            if TerminalRescue.consumePendingResize() {
                return .resize(size())
            }
            if r == 0 {
                if pendingBytes.count == 1 && pendingBytes[0] == 0x1B
                    && loneEscapeGraceExpired() {
                    pendingBytes.removeAll(keepingCapacity: true)
                    loneEscapeStartedAt = nil
                    return .key(.escape)
                }
                return nil
            }
            guard fds.revents & Int16(POLLIN) != 0 else {
                if fds.revents & Int16(POLLERR | POLLNVAL) != 0 {
                    throw TerminalError("terminal poll reported an input error")
                }
                return nil
            }
            let fd = inputFD
            let n = readBuffer.withUnsafeMutableBytes { raw in
                unsafe read(fd, raw.baseAddress, raw.count)
            }
            if n < 0, errno == EINTR { return nil }
            guard n > 0 else { throw TerminalError("terminal input reached EOF") }
            pendingBytes.append(contentsOf: readBuffer[0..<n])
        }
        return decodeOne()
    }

    private mutating func decodeOne() -> InputEvent? {
        guard let first = pendingBytes.first else { return nil }
        if first != 0x1B || pendingBytes.count > 1 {
            loneEscapeStartedAt = nil
        }

        // ESC sequences
        if first == 0x1B {
            if pendingBytes.count == 1 { return nil }
            if pendingBytes.count >= 2, pendingBytes[1] == UInt8(ascii: "[") {
                return decodeCSI()
            }
            if pendingBytes.count >= 2, pendingBytes[1] == UInt8(ascii: "O") {
                // SS3: F1–F4
                if pendingBytes.count >= 3 {
                    let c = pendingBytes[2]
                    pendingBytes.removeFirst(3)
                    switch c {
                    case UInt8(ascii: "P"): return .key(.function(1))
                    case UInt8(ascii: "Q"): return .key(.function(2))
                    case UInt8(ascii: "R"): return .key(.function(3))
                    case UInt8(ascii: "S"): return .key(.function(4))
                    default: return nil
                    }
                }
                return nil
            }
            pendingBytes.removeFirst()
            return .key(.escape)
        }

        // Control characters
        switch first {
        case 0x0D, 0x0A:
            pendingBytes.removeFirst()
            return .key(.enter)
        case 0x09:
            pendingBytes.removeFirst()
            return .key(.tab)
        case 0x7F, 0x08:
            pendingBytes.removeFirst()
            return .key(.backspace)
        case 0x01...0x1A:  // Ctrl-A ... Ctrl-Z
            pendingBytes.removeFirst()
            let letter = Character(UnicodeScalar(first + 0x60))
            return .key(.ctrl(letter))
        default:
            break
        }

        // UTF-8 character
        let len = utf8Length(first)
        guard pendingBytes.count >= len else {
            // Wait for continuation bytes on the next read.
            return nil
        }
        let scalarBytes = Array(pendingBytes.prefix(len))
        pendingBytes.removeFirst(len)
        var decoded = ""
        var decoder = UTF8()
        var iter = scalarBytes.makeIterator()
        while case .scalarValue(let v) = decoder.decode(&iter) {
            decoded.unicodeScalars.append(v)
        }
        guard let ch = decoded.first else { return nil }
        return .key(.character(ch))
    }

    /// A zero-timeout fairness poll must not turn a freshly buffered ESC into
    /// a standalone key before the rest of a CSI/SS3/mouse sequence arrives.
    private mutating func loneEscapeGraceExpired() -> Bool {
        let now = inputClock.now
        guard let startedAt = loneEscapeStartedAt else {
            loneEscapeStartedAt = now
            return false
        }
        return startedAt.duration(to: now) >= .milliseconds(25)
    }

    mutating func feedForTesting(_ bytes: [UInt8]) { pendingBytes.append(contentsOf: bytes) }
    mutating func decodeForTesting() -> InputEvent? { decodeOne() }

    private func utf8Length(_ b: UInt8) -> Int {
        if b < 0x80 { return 1 }
        if b < 0xE0 { return 2 }
        if b < 0xF0 { return 3 }
        return 4
    }

    private mutating func decodeCSI() -> InputEvent? {
        // pendingBytes = ESC [ ...params... final
        var i = 2
        while i < pendingBytes.count {
            let b = pendingBytes[i]
            if b >= 0x40 && b <= 0x7E { break }  // final byte
            i += 1
        }
        guard i < pendingBytes.count else { return nil }  // incomplete
        let final = pendingBytes[i]
        let params = String(decoding: pendingBytes[2..<i], as: UTF8.self)
        pendingBytes.removeFirst(i + 1)

        switch final {
        case UInt8(ascii: "A"): return .key(.up)
        case UInt8(ascii: "B"): return .key(.down)
        case UInt8(ascii: "C"): return .key(.right)
        case UInt8(ascii: "D"): return .key(.left)
        case UInt8(ascii: "H"): return .key(.home)
        case UInt8(ascii: "F"): return .key(.end)
        case UInt8(ascii: "Z"): return .key(.backTab)
        case UInt8(ascii: "~"):
            switch params {
            case "1", "7": return .key(.home)
            case "3": return .key(.delete)
            case "4", "8": return .key(.end)
            case "5": return .key(.pageUp)
            case "6": return .key(.pageDown)
            case "11": return .key(.function(1))
            case "12": return .key(.function(2))
            case "13": return .key(.function(3))
            case "14": return .key(.function(4))
            case "15": return .key(.function(5))
            case "17": return .key(.function(6))
            case "18": return .key(.function(7))
            case "19": return .key(.function(8))
            case "20": return .key(.function(9))
            case "21": return .key(.function(10))
            case "23": return .key(.function(11))
            case "24": return .key(.function(12))
            default: return nil
            }
        case UInt8(ascii: "M"), UInt8(ascii: "m"):
            // SGR mouse: ESC [ < btn ; col ; row (M=press, m=release)
            guard params.hasPrefix("<") else { return nil }
            let fields = params.dropFirst().split(separator: ";")
            guard fields.count == 3,
                let col = Int(fields[1]), let row = Int(fields[2])
            else { return nil }
            let pressed = final == UInt8(ascii: "M")
            return .pointer(Point(x: col - 1, y: row - 1), pressed: pressed)
        default:
            return nil
        }
    }
}

#else

// MARK: - Windows Console implementation

/// Pure translation from Windows console input records to `InputEvent`s,
/// kept free of console handles so it can be exercised in isolation.
enum WindowsInputTranslator {
    static func key(virtualKey: UInt16, scalar: UInt16, controlState: UInt32) -> InputEvent? {
        let shift = controlState & 0x0010 != 0
        let ctrl = controlState & (0x0008 | 0x0004) != 0

        switch Int32(virtualKey) {
        case 0x25: return .key(.left)
        case 0x26: return .key(.up)
        case 0x27: return .key(.right)
        case 0x28: return .key(.down)
        case 0x0D: return .key(.enter)
        case 0x1B: return .key(.escape)
        case 0x09: return .key(shift ? .backTab : .tab)
        case 0x08: return .key(.backspace)
        case 0x2E: return .key(.delete)
        case 0x24: return .key(.home)
        case 0x23: return .key(.end)
        case 0x21: return .key(.pageUp)
        case 0x22: return .key(.pageDown)
        case 0x70...0x7B: return .key(.function(Int(virtualKey) - 0x70 + 1))
        default: break
        }

        guard scalar != 0, let unicode = Unicode.Scalar(UInt32(scalar)) else { return nil }
        let character = Character(unicode)
        if ctrl, character.isLetter {
            return .key(.ctrl(Character(character.lowercased())))
        }
        if scalar >= 0x01, scalar <= 0x1A, character != "\t", character != "\r" {
            return .key(.ctrl(Character(UnicodeScalar(UInt8(scalar) + 0x60))))
        }
        return .key(.character(character))
    }

    static func pointer(
        x: Int16, y: Int16, buttonState: UInt32, eventFlags: UInt32
    ) -> InputEvent? {
        guard eventFlags == 0 else { return nil }
        return .pointer(Point(x: Int(x), y: Int(y)), pressed: buttonState & 0x0001 != 0)
    }
}

/// Windows Console backend: output goes through the console with virtual
/// terminal processing enabled, so `CellBuffer`'s ANSI diff stream is
/// written verbatim; input arrives as structured records via
/// `ReadConsoleInputW`, so no ANSI input parsing is needed. Presents the
/// same public surface as the POSIX implementation.
///
/// `@safe`: the two console `HANDLE`s are unsafe raw-pointer storage, but
/// every operation on them is confined to this type and spelled `unsafe`
/// at its site, so the public surface is as safe as the POSIX one.
@safe public struct Terminal: ~Copyable {
    private var hIn: HANDLE = unsafe INVALID_HANDLE_VALUE
    private var hOut: HANDLE = unsafe INVALID_HANDLE_VALUE
    private var savedInMode: DWORD = 0
    private var savedOutMode: DWORD = 0
    private var savedCP: UINT = 0
    private var isRaw = false

    // Console mode flags (WinCon.h)
    private static let ENABLE_PROCESSED_INPUT: DWORD = 0x0001
    private static let ENABLE_LINE_INPUT: DWORD = 0x0002
    private static let ENABLE_ECHO_INPUT: DWORD = 0x0004
    private static let ENABLE_WINDOW_INPUT: DWORD = 0x0008
    private static let ENABLE_MOUSE_INPUT: DWORD = 0x0010
    private static let ENABLE_QUICK_EDIT_MODE: DWORD = 0x0040
    private static let ENABLE_EXTENDED_FLAGS: DWORD = 0x0080
    private static let ENABLE_PROCESSED_OUTPUT: DWORD = 0x0001
    private static let ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004

    /// Creates a terminal; the console handles are acquired lazily in
    /// `enterRawMode()`.
    public init() {}

    // MARK: Raw mode

    /// Acquires the standard console handles, enables virtual terminal
    /// processing on output, switches input to raw key/mouse/resize events
    /// (no line buffering or echo), selects the UTF-8 output code page, and
    /// enters the alternate screen with the cursor hidden. The prior modes
    /// and code page are saved for restoration. Throws when no console is
    /// attached or a mode cannot be set, undoing any partial setup first.
    public mutating func enterRawMode() throws(TerminalError) {
        unsafe hIn = GetStdHandle(STD_INPUT_HANDLE)
        unsafe hOut = GetStdHandle(STD_OUTPUT_HANDLE)
        guard unsafe hIn != INVALID_HANDLE_VALUE, unsafe hOut != INVALID_HANDLE_VALUE else {
            throw TerminalError("GetStdHandle failed")
        }
        guard unsafe GetConsoleMode(hIn, &savedInMode), unsafe GetConsoleMode(hOut, &savedOutMode)
        else {
            throw TerminalError("GetConsoleMode failed — not a console")
        }

        // Output: VT sequences on, so CellBuffer's ANSI diff renders natively.
        let outMode =
            savedOutMode
            | Self.ENABLE_PROCESSED_OUTPUT
            | Self.ENABLE_VIRTUAL_TERMINAL_PROCESSING
        guard unsafe SetConsoleMode(hOut, outMode) else {
            throw TerminalError("SetConsoleMode(out) failed — Windows 10 1511+ required for VT")
        }

        // Input: raw keys + mouse + resize events; no line buffering/echo.
        var inMode = savedInMode
        inMode &= ~(Self.ENABLE_LINE_INPUT | Self.ENABLE_ECHO_INPUT
            | Self.ENABLE_PROCESSED_INPUT | Self.ENABLE_QUICK_EDIT_MODE)
        inMode |= Self.ENABLE_MOUSE_INPUT | Self.ENABLE_WINDOW_INPUT | Self.ENABLE_EXTENDED_FLAGS
        guard unsafe SetConsoleMode(hIn, inMode) else {
            throw TerminalError("SetConsoleMode(in) failed")
        }

        // UTF-8 byte stream out.
        savedCP = GetConsoleOutputCP()
        guard SetConsoleOutputCP(65001) else {
            _ = unsafe SetConsoleMode(hIn, savedInMode)
            _ = unsafe SetConsoleMode(hOut, savedOutMode)
            throw TerminalError("SetConsoleOutputCP(CP_UTF8) failed")
        }

        isRaw = true
        do { try write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J\u{1B}[H") }
        catch {
            exitRawMode()
            throw error
        }
    }

    /// Best-effort restoration — `exitRawModeChecked()` with the failure
    /// swallowed, safe to call from cleanup paths.
    public mutating func exitRawMode() {
        try? exitRawModeChecked()
    }

    /// Leaves the alternate screen, re-shows the cursor, and restores the
    /// saved console modes and output code page. A no-op when not in raw
    /// mode; attempts every restoration step and throws if any failed.
    public mutating func exitRawModeChecked() throws(TerminalError) {
        guard isRaw else { return }
        var failed = false
        do { try write("\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l") } catch { failed = true }
        if unsafe !SetConsoleMode(hIn, savedInMode) { failed = true }
        if unsafe !SetConsoleMode(hOut, savedOutMode) { failed = true }
        if savedCP != 0, !SetConsoleOutputCP(savedCP) { failed = true }
        isRaw = false
        if failed { throw TerminalError("Windows console restoration failed") }
    }

    // MARK: Size

    /// The visible console window size in character cells, falling back to
    /// 80×24 when the query fails or reports a degenerate size.
    public func size() -> Size {
        var info = CONSOLE_SCREEN_BUFFER_INFO()
        if unsafe GetConsoleScreenBufferInfo(hOut, &info) {
            let w = Int(info.srWindow.Right - info.srWindow.Left) + 1
            let h = Int(info.srWindow.Bottom - info.srWindow.Top) + 1
            if w > 0, h > 0 { return Size(width: w, height: h) }
        }
        return Size(width: 80, height: 24)
    }

    // MARK: Output

    /// Writes the UTF-8 bytes of `s` to the console, resuming after short
    /// writes until fully flushed.
    public func write(_ s: String) throws(TerminalError) {
        let bytes = Array(s.utf8)
        var written: DWORD = 0
        var off = 0
        while off < bytes.count {
            let ok = bytes.withUnsafeBytes { buf -> Bool in
                guard let base = buf.baseAddress else { return false }
                return unsafe WriteFile(
                    hOut,
                    base.advanced(by: off),
                    DWORD(buf.count - off),
                    &written,
                    nil)
            }
            guard ok, written > 0 else { throw TerminalError("WriteFile(console) failed") }
            off += Int(written)
        }
    }

    // MARK: Input

    /// Waits up to `timeoutMillis` for one console input record and
    /// translates it — key-down records to key events, mouse button
    /// records to pointer events, buffer-size changes to `.resize`.
    /// Returns `nil` on timeout or for records with no `InputEvent`
    /// mapping.
    public mutating func nextEvent(timeoutMillis: Int) throws(TerminalError) -> InputEvent? {
        let wait = unsafe WaitForSingleObject(hIn, DWORD(max(0, timeoutMillis)))
        if wait == WAIT_TIMEOUT { return nil }
        guard wait == WAIT_OBJECT_0 else { throw TerminalError("WaitForSingleObject(console) failed") }

        var record = INPUT_RECORD()
        var count: DWORD = 0
        guard unsafe ReadConsoleInputW(hIn, &record, 1, &count), count == 1 else {
            throw TerminalError("ReadConsoleInputW failed")
        }

        switch Int32(record.EventType) {
        case KEY_EVENT:
            let k = record.Event.KeyEvent
            guard k.bKeyDown.boolValue else { return nil }
            return translate(key: k)

        case MOUSE_EVENT:
            let m = record.Event.MouseEvent
            return WindowsInputTranslator.pointer(
                x: m.dwMousePosition.X, y: m.dwMousePosition.Y,
                buttonState: m.dwButtonState, eventFlags: m.dwEventFlags)

        case WINDOW_BUFFER_SIZE_EVENT:
            return .resize(size())

        default:
            return nil
        }
    }

    private func translate(key k: KEY_EVENT_RECORD) -> InputEvent? {
        WindowsInputTranslator.key(
            virtualKey: k.wVirtualKeyCode,
            scalar: k.uChar.UnicodeChar,
            controlState: k.dwControlKeyState)
    }
}

#endif
