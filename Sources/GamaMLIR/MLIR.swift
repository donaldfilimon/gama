//  MLIR.swift — GamaMLIR
//  ── Honest scope ─────────────────────────────────────────────────────
//  Swift has no official MLIR frontend; nothing here pretends otherwise.
//  What this target does, for real: lowers Gama's RenderNode IR into a
//  custom `gama` MLIR dialect as valid textual MLIR (generic op form),
//  suitable for mlir-opt/mlir-translate pipelines, custom dialect
//  conversions (e.g. gama → linalg/gpu for GPU compositors), or
//  ahead-of-time layout baking for Embedded targets.
//  ─────────────────────────────────────────────────────────────────────

import GamaCore

/// Minimal MLIR text builder — SSA names, attributes, regions. Uses the
/// *generic* op syntax ("dialect.op"(...) {attrs} : type) which is always
/// parseable without a registered dialect (with -allow-unregistered-dialect).
public struct MLIRBuilder {
    private var lines: [String] = []
    private var indentLevel = 0
    private var ssaCounter = 0

    public init() {}

    public mutating func fresh() -> String {
        defer { ssaCounter += 1 }
        return "%\(ssaCounter)"
    }

    public mutating func line(_ s: String) {
        lines.append(String(repeating: "  ", count: indentLevel) + s)
    }

    public mutating func open(_ s: String) {
        line(s)
        indentLevel += 1
    }

    public mutating func close(_ s: String = "}") {
        indentLevel = max(0, indentLevel - 1)
        line(s)
    }

    public var text: String { lines.joined(separator: "\n") + "\n" }
}

/// MLIR attribute value rendering.
public enum MLIRAttr {
    case i64(Int)
    case str(String)
    case bool(Bool)
    case color(Color)
    case unit

    public var rendered: String {
        switch self {
        case .i64(let v): return "\(v) : i64"
        case .str(let s): return "\"\(Self.escape(s))\""
        case .bool(let b): return b ? "true" : "false"
        case .color(let c):
            return c.isDefault
                ? "\"default\""
                : "dense<[\(c.r), \(c.g), \(c.b)]> : tensor<3xi8>"
        case .unit: return "unit"
        }
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        return out
    }
}

public func renderAttrs(_ attrs: [(String, MLIRAttr)]) -> String {
    guard !attrs.isEmpty else { return "" }
    let body = attrs.map { "\($0.0) = \($0.1.rendered)" }.joined(separator: ", ")
    return " {\(body)}"
}
