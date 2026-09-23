/// One lexical token of USDA text, with the line it starts on.
struct USDAToken: Equatable {
    enum Kind: Equatable {
        /// An identifier or keyword; may contain `:` and `.` (`xformOp:translate`,
        /// `outputs:surface.connect`).
        case word(String)
        /// Number text, kept verbatim so parsing to `Float` is exact.
        case number(String)
        case string(String)
        /// `<…>`
        case path(String)
        /// `@…@`
        case asset(String)
        /// One of `( ) [ ] { } = , ; :` (a lone `:` appears only in time
        /// samples, which the parser refuses by name).
        case punctuation(Character)
    }

    let kind: Kind
    let line: Int
}

/// Splits USDA into tokens. Comments (`#…` to the end of the line) and
/// whitespace, including newlines, are dropped: the subset Gama reads never
/// needs line structure beyond error positions.
func tokenizeUSDA(_ text: String) throws(USDError) -> [USDAToken] {
    let scalars = Array(text.unicodeScalars)
    var tokens: [USDAToken] = []
    var index = 0
    var line = 1

    func isWordStart(_ s: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(s) || ("A"..."Z").contains(s) || s == "_"
    }
    func isWordBody(_ s: Unicode.Scalar) -> Bool {
        isWordStart(s) || ("0"..."9").contains(s) || s == ":" || s == "."
    }
    func isNumberBody(_ s: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(s) || s == "." || s == "e" || s == "E" || s == "-" || s == "+"
    }

    while index < scalars.count {
        let scalar = scalars[index]
        switch scalar {
        case "\n":
            line += 1
            index += 1
        case " ", "\t", "\r":
            index += 1
        case "#":
            while index < scalars.count, scalars[index] != "\n" { index += 1 }
        case "(", ")", "[", "]", "{", "}", "=", ",", ";", ":":
            tokens.append(USDAToken(kind: .punctuation(Character(scalar)), line: line))
            index += 1
        case "\"", "'":
            let start = line
            let triple = index + 2 < scalars.count && scalars[index + 1] == scalar && scalars[index + 2] == scalar
            index += triple ? 3 : 1
            var value = ""
            var closed = false
            while index < scalars.count {
                let current = scalars[index]
                if current == scalar {
                    if !triple {
                        index += 1
                        closed = true
                        break
                    }
                    if index + 2 < scalars.count, scalars[index + 1] == scalar, scalars[index + 2] == scalar {
                        index += 3
                        closed = true
                        break
                    }
                }
                if current == "\n" {
                    guard triple else { throw .syntax(line: start, "unterminated string") }
                    line += 1
                }
                if current == "\\" {
                    guard index + 1 < scalars.count else { break }
                    let escaped = scalars[index + 1]
                    index += 2
                    switch escaped {
                    case "n": value += "\n"
                    case "t": value += "\t"
                    case "r": value += "\r"
                    case "a": value += "\u{7}"
                    case "b": value += "\u{8}"
                    case "f": value += "\u{C}"
                    case "v": value += "\u{B}"
                    case "0"..."7":
                        // Up to three octal digits, as USD's own unescaping reads them.
                        var code = escaped.value - 48
                        var digits = 1
                        while digits < 3, index < scalars.count, ("0"..."7").contains(scalars[index]) {
                            code = code * 8 + scalars[index].value - 48
                            index += 1
                            digits += 1
                        }
                        guard let decoded = Unicode.Scalar(code) else {
                            throw .syntax(line: line, "bad octal escape")
                        }
                        value.unicodeScalars.append(decoded)
                    case "x":
                        guard index + 1 < scalars.count,
                              let code = UInt32(String(String.UnicodeScalarView(scalars[index...index + 1])), radix: 16),
                              let decoded = Unicode.Scalar(code)
                        else { throw .syntax(line: line, "bad \\x escape") }
                        value.unicodeScalars.append(decoded)
                        index += 2
                    default: value.unicodeScalars.append(escaped)
                    }
                    continue
                }
                value.unicodeScalars.append(current)
                index += 1
            }
            guard closed else { throw .syntax(line: start, "unterminated string") }
            tokens.append(USDAToken(kind: .string(value), line: start))
        case "<", "@":
            let close: Unicode.Scalar = scalar == "<" ? ">" : "@"
            let start = index + 1
            var end = start
            while end < scalars.count, scalars[end] != close, scalars[end] != "\n" { end += 1 }
            guard end < scalars.count, scalars[end] == close else {
                throw .syntax(line: line, "unterminated \(scalar == "<" ? "path" : "asset path")")
            }
            let body = String(String.UnicodeScalarView(scalars[start..<end]))
            tokens.append(USDAToken(kind: scalar == "<" ? .path(body) : .asset(body), line: line))
            index = end + 1
        default:
            if isWordStart(scalar) {
                var end = index
                while end < scalars.count, isWordBody(scalars[end]) { end += 1 }
                tokens.append(USDAToken(kind: .word(String(String.UnicodeScalarView(scalars[index..<end]))), line: line))
                index = end
            } else if ("0"..."9").contains(scalar) || scalar == "-" || scalar == "+" || scalar == "." {
                var end = index + 1
                // `-inf` and `-nan` are words after a sign.
                if scalar == "-" || scalar == "+", end < scalars.count, isWordStart(scalars[end]) {
                    while end < scalars.count, isWordBody(scalars[end]) { end += 1 }
                } else {
                    while end < scalars.count, isNumberBody(scalars[end]) { end += 1 }
                }
                tokens.append(USDAToken(kind: .number(String(String.UnicodeScalarView(scalars[index..<end]))), line: line))
                index = end
            } else {
                throw .syntax(line: line, "unexpected character '\(scalar)'")
            }
        }
    }
    return tokens
}
