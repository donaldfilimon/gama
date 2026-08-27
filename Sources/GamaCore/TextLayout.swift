//  TextLayout.swift — GamaCore
//  Foundation-free terminal-column measurement and greedy word wrapping.

/// Terminal-column text metrics and greedy word wrapping with no
/// Foundation or ICU dependency: a built-in zero-width / East-Asian-wide
/// classification drives measurement, so every backend that shares
/// GamaCore measures text the same way.
public enum TextLayout {
    /// Display cells occupied by an extended grapheme cluster. Combining
    /// marks and joiners are zero width; East Asian wide characters and emoji
    /// occupy two cells. A cluster uses its widest scalar, not their sum.
    ///
    /// Default-emoji-presentation scalars outside the main U+1F300 block are
    /// a documented subset (WATCH/HOURGLASS and a few media keys). Other
    /// miscellaneous symbols stay narrow unless VS16 (U+FE0F) is present.
    public static func cellWidth(of character: Character) -> Int {
        var width = 0
        var emojiPresentation = false
        for scalar in character.unicodeScalars {
            let value = scalar.value
            if value == 0xFE0F { emojiPresentation = true }
            if isZeroWidth(value) { continue }
            width = max(width, isWide(value) ? 2 : 1)
        }
        return emojiPresentation && width > 0 ? 2 : width
    }

    /// Total display columns for `string`: the sum of every character's
    /// `cellWidth(of:)`, saturating at `Int.max` rather than overflowing.
    public static func displayWidth(of string: String) -> Int {
        string.reduce(into: 0) { result, character in
            let (sum, overflow) = result.addingReportingOverflow(cellWidth(of: character))
            result = overflow ? .max : sum
        }
    }

    /// Wrap `string` to `width` display columns. `width <= 0` preserves raw lines.
    public static func wrap(_ string: String, width: Int) -> [String] {
        var out: [String] = []
        for rawLine in split(string, on: "\n") {
            if width <= 0 || displayWidth(of: rawLine) <= width {
                out.append(rawLine)
                continue
            }
            var current = ""
            var currentWidth = 0
            for word in split(rawLine, on: " ") {
                let wordWidth = displayWidth(of: word)
                if wordWidth > width {
                    if !current.isEmpty {
                        out.append(current)
                        current = ""
                        currentWidth = 0
                    }
                    var chunk = ""
                    var chunkWidth = 0
                    for ch in word {
                        let characterWidth = cellWidth(of: ch)
                        if !chunk.isEmpty && chunkWidth + characterWidth > width {
                            out.append(chunk)
                            chunk = ""
                            chunkWidth = 0
                        }
                        chunk.append(ch)
                        chunkWidth += characterWidth
                        if chunkWidth >= width {
                            out.append(chunk)
                            chunk = ""
                            chunkWidth = 0
                        }
                    }
                    current = chunk
                    currentWidth = chunkWidth
                } else if current.isEmpty {
                    current = word
                    currentWidth = wordWidth
                } else if currentWidth + 1 + wordWidth <= width {
                    current += " " + word
                    currentWidth += 1 + wordWidth
                } else {
                    out.append(current)
                    current = word
                    currentWidth = wordWidth
                }
            }
            if !current.isEmpty || rawLine.isEmpty { out.append(current) }
        }
        return out.isEmpty ? [""] : out
    }

    /// Measured size of wrapped text.
    public static func size(of s: String, width: Int?) -> Size {
        let lines = wrap(s, width: width ?? 0)
        var maxLine = 0
        for l in lines { maxLine = max(maxLine, displayWidth(of: l)) }
        if let w = width { maxLine = min(maxLine, max(0, w)) }
        return Size(width: maxLine, height: lines.count)
    }

    /// Foundation-free split that preserves empty segments.
    static func split(_ s: String, on separator: Character) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in s {
            if ch == separator {
                out.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        out.append(current)
        return out
    }

    private static func isZeroWidth(_ value: UInt32) -> Bool {
        value == 0 || value < 0x20 || (0x7F...0x9F).contains(value)
            || (0x0300...0x036F).contains(value) || (0x0483...0x0489).contains(value)
            || (0x0591...0x05BD).contains(value) || value == 0x05BF
            || (0x05C1...0x05C2).contains(value) || (0x05C4...0x05C5).contains(value)
            || value == 0x05C7 || (0x0610...0x061A).contains(value)
            || (0x064B...0x065F).contains(value) || value == 0x0670
            || (0x06D6...0x06ED).contains(value) || (0x0711...0x0711).contains(value)
            || (0x0730...0x074A).contains(value) || (0x07A6...0x07B0).contains(value)
            || (0x07EB...0x07F3).contains(value) || (0x0816...0x082D).contains(value)
            || (0x0859...0x085B).contains(value) || (0x08D3...0x0902).contains(value)
            || (0x093A...0x093C).contains(value) || (0x0941...0x0948).contains(value)
            || value == 0x094D || (0x0951...0x0957).contains(value)
            || (0x0962...0x0963).contains(value) || (0x1AB0...0x1AFF).contains(value)
            || (0x1DC0...0x1DFF).contains(value) || value == 0x200B
            || value == 0x200C || value == 0x200D || (0x202A...0x202E).contains(value)
            || (0x2060...0x206F).contains(value) || (0x20D0...0x20FF).contains(value)
            || (0xFE00...0xFE0F).contains(value) || value == 0xFEFF
            || (0xE0100...0xE01EF).contains(value)
    }

    private static func isWide(_ value: UInt32) -> Bool {
        (0x1100...0x115F).contains(value) || value == 0x231A || value == 0x231B
            || value == 0x2329 || value == 0x232A
            || (0x23E9...0x23EC).contains(value) || value == 0x23F0 || value == 0x23F3
            || (0x2E80...0x303E).contains(value) || (0x3040...0xA4CF).contains(value)
            || (0xAC00...0xD7A3).contains(value) || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE19).contains(value) || (0xFE30...0xFE6F).contains(value)
            || (0xFF00...0xFF60).contains(value) || (0xFFE0...0xFFE6).contains(value)
            || (0x1F1E6...0x1F1FF).contains(value) || (0x1F300...0x1FAFF).contains(value)
            || (0x20000...0x3FFFD).contains(value)
    }
}
