/// A parsed USDA value. Numbers stay as text until a typed reader converts
/// them, so a value parsed as `Float` is exactly what the writer printed.
indirect enum USDAValue: Equatable {
    case number(String)
    case string(String)
    /// A bare word such as `true`, `false`, or `None`.
    case word(String)
    case path(String)
    case asset(String)
    case list([USDAValue])
    case tuple([USDAValue])
    case dictionary([String: USDAValue])
}

struct USDAProperty: Equatable {
    var name: String
    /// `nil` for a relationship.
    var typeName: String?
    var value: USDAValue?
    var line: Int
}

struct USDAPrim: Equatable {
    var specifier: String
    var typeName: String?
    var name: String
    var metadata: [String: USDAValue]
    var properties: [USDAProperty]
    var children: [USDAPrim]
    var line: Int

    func property(_ name: String) -> USDAProperty? {
        properties.first { $0.name == name }
    }
}

struct USDALayer: Equatable {
    var metadata: [String: USDAValue]
    var prims: [USDAPrim]
}

/// Parses the USDA structure Gama reads: prims with specifiers and optional
/// type names, `(…)` metadata including list-op prefixes, typed attributes
/// with scalar, tuple, list, and dictionary values, relationships, and
/// connections. Time samples, variants, and splines are refused as
/// ``USDError/unsupported(line:_:)`` rather than skipped.
func parseUSDA(_ text: String) throws(USDError) -> USDALayer {
    guard text.hasPrefix("#usda 1.0") else {
        throw .syntax(line: 1, "expected a '#usda 1.0' header")
    }
    var parser = USDAParser(tokens: try tokenizeUSDA(text))
    return try parser.layer()
}

private struct USDAParser {
    let tokens: [USDAToken]
    var position = 0

    init(tokens: [USDAToken]) {
        self.tokens = tokens
    }

    var current: USDAToken? { position < tokens.count ? tokens[position] : nil }
    var line: Int { current?.line ?? (tokens.last?.line ?? 1) }

    mutating func layer() throws(USDError) -> USDALayer {
        var metadata: [String: USDAValue] = [:]
        if isPunctuation("(") {
            metadata = try metadataBlock()
        }
        var prims: [USDAPrim] = []
        while current != nil {
            prims.append(try prim())
        }
        return USDALayer(metadata: metadata, prims: prims)
    }

    // MARK: Prims

    mutating func prim() throws(USDError) -> USDAPrim {
        let start = line
        let specifier = try word()
        guard ["def", "over", "class"].contains(specifier) else {
            throw .syntax(line: start, "expected def, over, or class, found '\(specifier)'")
        }
        var typeName: String?
        if case .word(let type)? = current?.kind {
            typeName = type
            position += 1
        }
        guard case .string(let name)? = current?.kind else {
            throw .syntax(line: line, "expected a quoted prim name")
        }
        position += 1
        var metadata: [String: USDAValue] = [:]
        if isPunctuation("(") {
            metadata = try metadataBlock()
        }
        try expect("{")
        var prim = USDAPrim(
            specifier: specifier, typeName: typeName, name: name,
            metadata: metadata, properties: [], children: [], line: start
        )
        while !isPunctuation("}") {
            guard let token = current else { throw .syntax(line: line, "unterminated prim '\(name)'") }
            if case .word(let keyword) = token.kind {
                switch keyword {
                case "def", "over", "class":
                    prim.children.append(try self.prim())
                    continue
                case "variantSet":
                    throw .unsupported(line: token.line, "variant sets")
                default:
                    break
                }
            }
            if isPunctuation(";") {
                position += 1
                continue
            }
            prim.properties.append(try property())
        }
        position += 1
        return prim
    }

    mutating func property() throws(USDError) -> USDAProperty {
        let start = line
        var first = try word()
        // List-op prefixes and variability qualifiers carry nothing Gama reads.
        while ["custom", "uniform", "varying", "prepend", "append", "add", "delete", "reorder"].contains(first) {
            first = try word()
        }
        var typeName: String?
        let name: String
        if first == "rel" {
            name = try word()
        } else {
            var type = first
            if isPunctuation("[") {
                position += 1
                try expect("]")
                type += "[]"
            }
            typeName = type
            name = try word()
        }
        if name.hasSuffix(".timeSamples") || name.hasSuffix(".spline") {
            throw .unsupported(line: start, "animated attribute '\(name)'")
        }
        var value: USDAValue?
        if isPunctuation("=") {
            position += 1
            value = try self.value()
        }
        if isPunctuation("(") {
            _ = try metadataBlock()
        }
        return USDAProperty(name: name, typeName: typeName, value: value, line: start)
    }

    // MARK: Metadata

    /// `( key = value … )`, with optional list-op prefixes and a leading doc
    /// string. Entries are keyed by name; list-op prefixes are dropped.
    mutating func metadataBlock() throws(USDError) -> [String: USDAValue] {
        try expect("(")
        var entries: [String: USDAValue] = [:]
        while !isPunctuation(")") {
            guard let token = current else { throw .syntax(line: line, "unterminated metadata") }
            if isPunctuation(";") {
                position += 1
                continue
            }
            if case .string(let doc) = token.kind {
                entries["doc"] = .string(doc)
                position += 1
                continue
            }
            var key = try word()
            if ["prepend", "append", "add", "delete", "reorder"].contains(key) {
                key = try word()
            }
            try expect("=")
            entries[key] = try value()
        }
        position += 1
        return entries
    }

    // MARK: Values

    mutating func value() throws(USDError) -> USDAValue {
        guard let token = current else { throw .syntax(line: line, "expected a value") }
        switch token.kind {
        case .number(let text):
            position += 1
            return .number(text)
        case .string(let text):
            position += 1
            return .string(text)
        case .path(let text):
            position += 1
            return .path(text)
        case .asset(let text):
            position += 1
            return .asset(text)
        case .word(let text):
            position += 1
            if text == "inf" || text == "nan" { return .number(text) }
            return .word(text)
        case .punctuation("("):
            return .tuple(try sequence(closing: ")"))
        case .punctuation("["):
            return .list(try sequence(closing: "]"))
        case .punctuation("{"):
            return .dictionary(try dictionary())
        case .punctuation(let mark):
            throw .syntax(line: token.line, "unexpected '\(mark)' where a value belongs")
        }
    }

    mutating func sequence(closing: Character) throws(USDError) -> [USDAValue] {
        position += 1
        var values: [USDAValue] = []
        while !isPunctuation(closing) {
            values.append(try value())
            if isPunctuation(",") {
                position += 1
            } else if !isPunctuation(closing) {
                throw .syntax(line: line, "expected ',' or '\(closing)'")
            }
        }
        position += 1
        return values
    }

    /// `{ type key = value … }`; keys may be quoted.
    mutating func dictionary() throws(USDError) -> [String: USDAValue] {
        try expect("{")
        var entries: [String: USDAValue] = [:]
        while !isPunctuation("}") {
            if isPunctuation(";") {
                position += 1
                continue
            }
            _ = try word()
            if isPunctuation("[") {
                position += 1
                try expect("]")
            }
            let key: String
            switch current?.kind {
            case .string(let text)?, .word(let text)?:
                key = text
                position += 1
            default:
                throw .syntax(line: line, "expected a dictionary key")
            }
            try expect("=")
            entries[key] = try value()
        }
        position += 1
        return entries
    }

    // MARK: Tokens

    func isPunctuation(_ mark: Character) -> Bool {
        current?.kind == .punctuation(mark)
    }

    mutating func expect(_ mark: Character) throws(USDError) {
        guard isPunctuation(mark) else {
            throw .syntax(line: line, current == nil ? "expected '\(mark)' before the end of the file" : "expected '\(mark)'")
        }
        position += 1
    }

    mutating func word() throws(USDError) -> String {
        guard case .word(let text)? = current?.kind else {
            throw .syntax(line: line, "expected an identifier")
        }
        position += 1
        return text
    }
}
