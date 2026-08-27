//  Lowering.swift — GamaMLIR
//  RenderNode → `gama` dialect. Two entry points:
//   • lower(node:)      — structural lowering (pre-layout)
//   • lower(laidOut:)   — frame-annotated lowering (post-layout), the
//                         form GPU-compositor or AOT-bake pipelines want.
//
//  Dialect vocabulary (generic form, unregistered-dialect friendly):
//   "gama.module"     region-holding root
//   "gama.text"       leaf; attrs: text, fg, bg, attrs-bitmask
//   "gama.stack"      region; attrs: axis, spacing, halign, valign
//   "gama.overlay"    region; attrs: halign, valign
//   "gama.group"      region; ViewBuilder flatten sentinel
//   "gama.spacer"     leaf;  attrs: min
//   "gama.padding"    region; attrs: top/leading/bottom/trailing
//   "gama.border"     region; attrs: style, title, fg
//   "gama.background" region; attrs: color
//   "gama.frame"      region; attrs: width?, height?, min*/max*
//   "gama.styled"     region; attrs: fg, bg, attrs-bitmask
//   "gama.interactive" region; attrs: id, focusable
//  Post-layout ops additionally carry x, y, w, h.

import GamaCore

/// Lowers render trees into the textual `gama` MLIR dialect (generic op
/// form, parseable with `mlir-opt --allow-unregistered-dialect`).
public enum GamaLowering {
    /// Lowers a structural (pre-layout) tree into a `gama.module`.
    public static func lower(module node: RenderNode, name: String = "main") -> String {
        var b = MLIRBuilder()
        b.open("\"gama.module\"() ({")
        emit(node, into: &b, frame: nil)
        b.close("}) {sym_name = \(MLIRAttr.str(name).rendered)} : () -> ()")
        return b.text
    }

    /// Lowers a laid-out tree, attaching absolute frame geometry to ops.
    public static func lower(laidOut root: LaidOutNode, name: String = "main") -> String {
        var b = MLIRBuilder()
        b.open("\"gama.module\"() ({")
        emitLaid(root, into: &b)
        b.close("}) {sym_name = \(MLIRAttr.str(name).rendered)} : () -> ()")
        return b.text
    }

    // MARK: Structural

    private static func emit(_ node: RenderNode, into b: inout MLIRBuilder, frame: Rect?) {
        var frameAttrs: [(String, MLIRAttr)] = []
        if let f = frame {
            frameAttrs = [
                ("x", .i64(f.minX)), ("y", .i64(f.minY)),
                ("w", .i64(f.size.width)), ("h", .i64(f.size.height)),
            ]
        }

        switch node {
        case .empty:
            b.line("\"gama.empty\"()\(renderAttrs(frameAttrs)) : () -> ()")

        case .text(let s, let style):
            let attrs: [(String, MLIRAttr)] =
                [
                    ("text", .str(s)),
                    ("fg", .color(style.foreground)),
                    ("bg", .color(style.background)),
                    ("sgr", .i64(Int(style.attributes.rawValue))),
                ] + frameAttrs
            b.line("\"gama.text\"()\(renderAttrs(attrs)) : () -> ()")

        case .spacer(let minLength):
            b.line(
                "\"gama.spacer\"()\(renderAttrs([("min", .i64(minLength))] + frameAttrs)) : () -> ()"
            )

        case .divider(let style):
            b.line(
                "\"gama.divider\"()\(renderAttrs([("fg", .color(style.foreground))] + frameAttrs)) : () -> ()"
            )

        case .stack(let axis, let spacing, let alignment, let children):
            let attrs: [(String, MLIRAttr)] =
                [
                    ("axis", .str(axis == .horizontal ? "h" : "v")),
                    ("spacing", .i64(spacing)),
                    ("halign", .str(name(alignment.horizontal))),
                    ("valign", .str(name(alignment.vertical))),
                ] + frameAttrs
            b.open("\"gama.stack\"() ({")
            for c in children { emit(c, into: &b, frame: nil) }
            b.close("})\(renderAttrs(attrs)) : () -> ()")

        case .overlay(let alignment, let children):
            let attrs: [(String, MLIRAttr)] =
                [
                    ("halign", .str(name(alignment.horizontal))),
                    ("valign", .str(name(alignment.vertical))),
                ] + frameAttrs
            b.open("\"gama.overlay\"() ({")
            for c in children { emit(c, into: &b, frame: nil) }
            b.close("})\(renderAttrs(attrs)) : () -> ()")

        case .group(let children):
            b.open("\"gama.group\"() ({")
            for c in children { emit(c, into: &b, frame: nil) }
            b.close("})\(renderAttrs(frameAttrs)) : () -> ()")

        case .padding(let e, let child):
            let attrs: [(String, MLIRAttr)] =
                [
                    ("top", .i64(e.top)), ("leading", .i64(e.leading)),
                    ("bottom", .i64(e.bottom)), ("trailing", .i64(e.trailing)),
                ] + frameAttrs
            b.open("\"gama.padding\"() ({")
            emit(child, into: &b, frame: nil)
            b.close("})\(renderAttrs(attrs)) : () -> ()")

        case .border(let style, let textStyle, let title, let child):
            var attrs: [(String, MLIRAttr)] = [
                ("style", .str(name(style))),
                ("fg", .color(textStyle.foreground)),
            ]
            if let title { attrs.append(("title", .str(title))) }
            attrs += frameAttrs
            b.open("\"gama.border\"() ({")
            emit(child, into: &b, frame: nil)
            b.close("})\(renderAttrs(attrs)) : () -> ()")

        case .background(let color, let child):
            b.open("\"gama.background\"() ({")
            emit(child, into: &b, frame: nil)
            b.close("})\(renderAttrs([("color", .color(color))] + frameAttrs)) : () -> ()")

        case .frame(let w, let h, let alignment, let child):
            var attrs: [(String, MLIRAttr)] = []
            if let w { attrs.append(("width", .i64(w))) }
            if let h { attrs.append(("height", .i64(h))) }
            attrs.append(("halign", .str(name(alignment.horizontal))))
            attrs.append(("valign", .str(name(alignment.vertical))))
            attrs += frameAttrs
            b.open("\"gama.frame\"() ({")
            emit(child, into: &b, frame: nil)
            b.close("})\(renderAttrs(attrs)) : () -> ()")

        case .flexFrame(let minW, let maxW, let minH, let maxH, let alignment, let child):
            var attrs: [(String, MLIRAttr)] = []
            if let minW { attrs.append(("min_width", .i64(minW))) }
            if let maxW { attrs.append(("max_width", .i64(maxW == .max ? -1 : maxW))) }
            if let minH { attrs.append(("min_height", .i64(minH))) }
            if let maxH { attrs.append(("max_height", .i64(maxH == .max ? -1 : maxH))) }
            attrs.append(("halign", .str(name(alignment.horizontal))))
            attrs.append(("valign", .str(name(alignment.vertical))))
            attrs += frameAttrs
            b.open("\"gama.frame\"() ({")
            emit(child, into: &b, frame: nil)
            b.close("})\(renderAttrs(attrs)) : () -> ()")

        case .styled(let style, let child):
            let attrs: [(String, MLIRAttr)] =
                [
                    ("fg", .color(style.foreground)),
                    ("bg", .color(style.background)),
                    ("sgr", .i64(Int(style.attributes.rawValue))),
                ] + frameAttrs
            b.open("\"gama.styled\"() ({")
            emit(child, into: &b, frame: nil)
            b.close("})\(renderAttrs(attrs)) : () -> ()")

        case .interactive(let id, let focusable, let child):
            let attrs: [(String, MLIRAttr)] =
                [
                    ("id", .i64(Int64(bitPattern: id.raw))),
                    ("focusable", .bool(focusable)),
                ] + frameAttrs
            b.open("\"gama.interactive\"() ({")
            emit(child, into: &b, frame: nil)
            b.close("})\(renderAttrs(attrs)) : () -> ()")
        }
    }

    // MARK: Frame-annotated

    private static func emitLaid(_ laid: LaidOutNode, into b: inout MLIRBuilder) {
        switch laid.node {
        case .empty, .text, .spacer, .divider:
            emit(laid.node, into: &b, frame: laid.frame)
        default:
            emitContainerLaid(laid, into: &b)
        }
    }

    private static func emitContainerLaid(_ laid: LaidOutNode, into b: inout MLIRBuilder) {
        // Re-emit the container op with its frame, recursing over laid
        // children instead of structural children.
        let f = laid.frame
        let frameAttrs: [(String, MLIRAttr)] = [
            ("x", .i64(f.minX)), ("y", .i64(f.minY)),
            ("w", .i64(f.size.width)), ("h", .i64(f.size.height)),
        ]

        func region(_ op: String, _ attrs: [(String, MLIRAttr)]) {
            b.open("\"gama.\(op)\"() ({")
            for c in laid.children { emitLaid(c, into: &b) }
            b.close("})\(renderAttrs(attrs + frameAttrs)) : () -> ()")
        }

        switch laid.node {
        case .stack(let axis, let spacing, let alignment, _):
            region(
                "stack",
                [
                    ("axis", .str(axis == .horizontal ? "h" : "v")),
                    ("spacing", .i64(spacing)),
                    ("halign", .str(name(alignment.horizontal))),
                    ("valign", .str(name(alignment.vertical))),
                ]
            )
        case .overlay(let alignment, _):
            region(
                "overlay",
                [
                    ("halign", .str(name(alignment.horizontal))),
                    ("valign", .str(name(alignment.vertical))),
                ]
            )
        case .group:
            region("group", [])
        case .padding(let e, _):
            region(
                "padding",
                [
                    ("top", .i64(e.top)), ("leading", .i64(e.leading)),
                    ("bottom", .i64(e.bottom)), ("trailing", .i64(e.trailing)),
                ]
            )
        case .border(let style, let textStyle, let title, _):
            var a: [(String, MLIRAttr)] = [
                ("style", .str(name(style))), ("fg", .color(textStyle.foreground)),
            ]
            if let title { a.append(("title", .str(title))) }
            region("border", a)
        case .background(let color, _):
            region("background", [("color", .color(color))])
        case .frame(let width, let height, let alignment, _):
            var attrs: [(String, MLIRAttr)] = [
                ("halign", .str(name(alignment.horizontal))),
                ("valign", .str(name(alignment.vertical))),
            ]
            if let width { attrs.append(("width", .i64(width))) }
            if let height { attrs.append(("height", .i64(height))) }
            region("frame", attrs)
        case .flexFrame(let minWidth, let maxWidth, let minHeight, let maxHeight, let alignment, _):
            var attrs: [(String, MLIRAttr)] = [
                ("halign", .str(name(alignment.horizontal))),
                ("valign", .str(name(alignment.vertical))),
            ]
            if let minWidth { attrs.append(("min_width", .i64(minWidth))) }
            if let maxWidth { attrs.append(("max_width", .i64(maxWidth == .max ? -1 : maxWidth))) }
            if let minHeight { attrs.append(("min_height", .i64(minHeight))) }
            if let maxHeight { attrs.append(("max_height", .i64(maxHeight == .max ? -1 : maxHeight))) }
            region("frame", attrs)
        case .styled(let style, _):
            region(
                "styled",
                [
                    ("fg", .color(style.foreground)),
                    ("bg", .color(style.background)),
                    ("sgr", .i64(Int(style.attributes.rawValue))),
                ]
            )
        case .interactive(let id, let focusable, _):
            region(
                "interactive",
                [
                    ("id", .i64(Int64(bitPattern: id.raw))),
                    ("focusable", .bool(focusable)),
                ]
            )
        case .empty, .text, .spacer, .divider:
            break  // handled by caller
        }
    }

    // MARK: Names

    private static func name(_ h: HorizontalAlignment) -> String {
        switch h {
        case .leading: return "leading"
        case .center: return "center"
        case .trailing: return "trailing"
        }
    }
    private static func name(_ v: VerticalAlignment) -> String {
        switch v {
        case .top: return "top"
        case .center: return "center"
        case .bottom: return "bottom"
        }
    }
    private static func name(_ s: BorderStyle) -> String {
        switch s {
        case .single: return "single"
        case .double: return "double"
        case .rounded: return "rounded"
        case .heavy: return "heavy"
        case .ascii: return "ascii"
        }
    }
}
