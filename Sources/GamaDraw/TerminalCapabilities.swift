//  TerminalCapabilities.swift — GamaDraw
//  What a terminal is known to support. Detection is a pure function of
//  an environment dictionary so the portable draw layer never reads the
//  process environment. Unknown is not support: setup and color encoding
//  act only on `.supported` and a known color depth.

/// Whether a terminal feature is known to work.
///
/// ``unknown`` is the absence of evidence. Callers must not enable a
/// feature, emit its protocol, or advertise it while the value is
/// ``unknown`` or ``unsupported``.
public enum CapabilitySupport: String, Hashable, Sendable {
    /// The environment identifies a terminal that implements the feature.
    case supported
    /// The environment identifies a terminal that does not implement it.
    case unsupported
    /// No evidence either way. This is not ``supported``.
    case unknown
}

/// How much color the terminal is known to display.
///
/// ``unknown`` and ``monochrome`` both emit no color codes. A missing
/// `TERM` stays ``unknown`` rather than being promoted to a palette.
public enum TerminalColorDepth: String, Hashable, Sendable {
    /// No color codes. Also used when `NO_COLOR` is set or `TERM` is `dumb`.
    case monochrome
    /// The classic 16-color SGR palette.
    case ansi16
    /// The xterm 256-color palette.
    case ansi256
    /// 24-bit color, evidenced by `COLORTERM` or a `-direct` terminal name.
    case trueColor
    /// No evidence of a palette. Color codes are omitted.
    case unknown
}

/// Capability report for one terminal environment.
///
/// The draw layer consumes ``colorDepth`` when it encodes a cell diff.
/// The terminal backend consumes the feature flags when it enters raw
/// mode. Neither path treats ``CapabilitySupport/unknown`` as available.
public struct TerminalCapabilities: Hashable, Sendable {
    /// Palette the diff may encode. ``unknown`` omits color codes.
    public var colorDepth: TerminalColorDepth
    /// Whether the locale and terminal claim UTF-8. This does not strip
    /// graphemes from the cell grid; it only records the claim.
    public var unicode: CapabilitySupport
    /// SGR mouse tracking (`1000` / `1006`).
    public var mouse: CapabilitySupport
    /// Alternate screen buffer (`1049`).
    public var alternateScreen: CapabilitySupport
    /// Bracketed paste (`2004`).
    public var bracketedPaste: CapabilitySupport
    /// Focus in/out reporting (`1004`).
    public var focusReporting: CapabilitySupport
    /// OSC 8 hyperlinks. Detection does not emit hyperlinks; the cell
    /// diff has no link field.
    public var hyperlinks: CapabilitySupport

    /// Creates a report from already-decided flags.
    public init(
        colorDepth: TerminalColorDepth,
        unicode: CapabilitySupport,
        mouse: CapabilitySupport,
        alternateScreen: CapabilitySupport,
        bracketedPaste: CapabilitySupport,
        focusReporting: CapabilitySupport,
        hyperlinks: CapabilitySupport
    ) {
        self.colorDepth = colorDepth
        self.unicode = unicode
        self.mouse = mouse
        self.alternateScreen = alternateScreen
        self.bracketedPaste = bracketedPaste
        self.focusReporting = focusReporting
        self.hyperlinks = hyperlinks
    }

    /// Every feature ``unknown``, including color. The value used when the
    /// environment was not consulted.
    public static let unknown = TerminalCapabilities(
        colorDepth: .unknown,
        unicode: .unknown,
        mouse: .unknown,
        alternateScreen: .unknown,
        bracketedPaste: .unknown,
        focusReporting: .unknown,
        hyperlinks: .unknown
    )

    /// Detects capabilities from terminal environment variables.
    ///
    /// Reads `TERM`, `COLORTERM`, `NO_COLOR`, `LC_ALL`, `LC_CTYPE`, and
    /// `LANG` from `environment`. A missing key is not evidence. `NO_COLOR`,
    /// when present, forces ``TerminalColorDepth/monochrome`` even if
    /// `COLORTERM` asks for true color. An unrecognized `TERM` leaves
    /// mouse, the alternate screen, paste, focus, and hyperlinks
    /// ``unknown``, and the raw-mode sequences for those features are
    /// then empty.
    public static func detect(environment: [String: String]) -> TerminalCapabilities {
        let term = (environment["TERM"] ?? "").lowercased()
        let colorTerm = (environment["COLORTERM"] ?? "").lowercased()
        let noColor = environment["NO_COLOR"] != nil
        return TerminalCapabilities(
            colorDepth: colorDepth(term: term, colorTerm: colorTerm, noColor: noColor),
            unicode: unicode(term: term, environment: environment),
            mouse: mouse(term: term),
            alternateScreen: alternateScreen(term: term),
            bracketedPaste: bracketedPaste(term: term),
            focusReporting: focusReporting(term: term),
            hyperlinks: hyperlinks(term: term)
        )
    }

    private static func colorDepth(
        term: String, colorTerm: String, noColor: Bool
    ) -> TerminalColorDepth {
        if noColor || term == "dumb" { return .monochrome }
        if colorTerm == "truecolor" || colorTerm == "24bit" || term.hasSuffix("-direct") {
            return .trueColor
        }
        if term.contains("256color") { return .ansi256 }
        if term.isEmpty { return .unknown }
        // Named classic terminals are evidence of a 16-color palette.
        // A modern emulator name is not evidence of a palette; without
        // COLORTERM or a 256-color name the depth stays unknown.
        if isLimited(term) || isXtermFamily(term) { return .ansi16 }
        return .unknown
    }

    private static func unicode(term: String, environment: [String: String]) -> CapabilitySupport {
        if term == "dumb" { return .unsupported }
        let locale = [environment["LC_ALL"], environment["LC_CTYPE"], environment["LANG"]]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value.lowercased()
            }
            .first ?? ""
        if locale.contains("utf") { return .supported }
        if locale == "c" || locale == "posix" || locale.hasPrefix("c.") { return .unsupported }
        return .unknown
    }

    private static func mouse(term: String) -> CapabilitySupport {
        if term.isEmpty { return .unknown }
        if isXtermFamily(term) || isModern(term) { return .supported }
        if isLimited(term) { return .unsupported }
        return .unknown
    }

    private static func alternateScreen(term: String) -> CapabilitySupport {
        mouse(term: term)
    }

    private static func bracketedPaste(term: String) -> CapabilitySupport {
        if term.isEmpty { return .unknown }
        if isXtermFamily(term) || isModern(term) { return .supported }
        if isLimited(term) { return .unsupported }
        return .unknown
    }

    private static func focusReporting(term: String) -> CapabilitySupport {
        if term.isEmpty { return .unknown }
        if hasPrefix(term, "xterm") || isModern(term) { return .supported }
        if isLimited(term) { return .unsupported }
        return .unknown
    }

    private static func hyperlinks(term: String) -> CapabilitySupport {
        if term.isEmpty { return .unknown }
        if isHyperlinkTerminal(term) { return .supported }
        if isLimited(term) { return .unsupported }
        return .unknown
    }

    private static func isLimited(_ term: String) -> Bool {
        term == "dumb" || term == "linux" || term == "ansi" || term == "cons25"
            || hasPrefix(term, "vt100") || hasPrefix(term, "vt220")
    }

    private static func isXtermFamily(_ term: String) -> Bool {
        hasPrefix(term, "xterm") || hasPrefix(term, "screen") || hasPrefix(term, "tmux")
    }

    private static func isModern(_ term: String) -> Bool {
        ["alacritty", "kitty", "wezterm", "ghostty", "foot", "rio", "contour"]
            .contains { hasPrefix(term, $0) }
    }

    private static func isHyperlinkTerminal(_ term: String) -> Bool {
        ["kitty", "wezterm", "ghostty", "alacritty", "foot", "rio", "contour"]
            .contains { hasPrefix(term, $0) }
    }

    private static func hasPrefix(_ term: String, _ prefix: String) -> Bool {
        term == prefix || term.hasPrefix(prefix + "-")
    }
}

/// ANSI mode sequences for the features a capability report marks supported.
///
/// Unknown and unsupported features contribute no bytes. The enable string
/// is what raw mode writes; the disable string reverses that same set, so
/// a terminal that never entered the alternate screen is not told to leave it.
public enum TerminalModeSequences {
    /// Sequences that turn supported features on. Cursor hiding is always
    /// included. The alternate-screen clear is included only when that
    /// feature is ``CapabilitySupport/supported``, so an unknown terminal
    /// does not erase the primary screen.
    public static func enable(_ capabilities: TerminalCapabilities) -> String {
        var out = ""
        if capabilities.alternateScreen == .supported {
            out += "\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J\u{1B}[H"
        } else {
            out += "\u{1B}[?25l"
        }
        if capabilities.mouse == .supported {
            out += "\u{1B}[?1000h\u{1B}[?1006h"
        }
        if capabilities.bracketedPaste == .supported {
            out += "\u{1B}[?2004h"
        }
        if capabilities.focusReporting == .supported {
            out += "\u{1B}[?1004h"
        }
        return out
    }

    /// Sequences that turn the same supported features back off, in reverse
    /// order, then show the cursor and reset SGR.
    public static func disable(_ capabilities: TerminalCapabilities) -> String {
        var out = ""
        if capabilities.focusReporting == .supported {
            out += "\u{1B}[?1004l"
        }
        if capabilities.bracketedPaste == .supported {
            out += "\u{1B}[?2004l"
        }
        if capabilities.mouse == .supported {
            out += "\u{1B}[?1006l\u{1B}[?1000l"
        }
        out += "\u{1B}[0m\u{1B}[?25h"
        if capabilities.alternateScreen == .supported {
            out += "\u{1B}[?1049l"
        }
        return out
    }
}
