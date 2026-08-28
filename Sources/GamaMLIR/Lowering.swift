//  Lowering.swift — GamaMLIR
//  RenderNode → `gama` dialect. Two entry points:
//   • lower(module:)    — structural lowering (pre-layout)
//   • lower(laidOut:)   — frame-annotated lowering (post-layout), the
//                         form GPU-compositor or AOT-bake pipelines want.
//
//  Dialect vocabulary (generic form, unregistered-dialect friendly):
//   "gama.module"     region-holding root; attr: sym_name
//   "gama.empty"      leaf; no structural attrs
//   "gama.text"       leaf; attrs: text, fg, bg, sgr
//   "gama.stack"      region; attrs: axis, spacing, halign, valign
//   "gama.overlay"    region; attrs: halign, valign
//   "gama.group"      region; ViewBuilder flatten sentinel
//   "gama.spacer"     leaf;  attrs: min
//   "gama.divider"    leaf;  attrs: fg, bg, sgr, axis?
//   "gama.padding"    region; attrs: top/leading/bottom/trailing
//   "gama.border"     region; attrs: style, title, fg
//   "gama.background" region; attrs: color
//   "gama.frame"      region; attrs: dimensions, halign, valign; shared by
//                       fixed and flex frame nodes
//   "gama.styled"     region; attrs: fg, bg, sgr
//   "gama.interactive" region; attrs: id, focusable
//  Post-layout ops additionally carry x, y, w, h.
//  Layout rewrites normal groups to top-leading overlays and resolves missing
//  divider axes; hand-built laid groups still emit gama.group. Attribute order
//  is dimensions, alignment, then the post-layout frame quad.
//  Canonical user-facing reference: docs/MLIRDialect.md.

import GamaCore

/// Lowers render trees into the textual `gama` MLIR dialect (generic op
/// form, parseable with `mlir-opt --allow-unregistered-dialect`).
public enum GamaLowering {
    /// Lowers a structural (pre-layout) tree into a `gama.module`.
    public static func lower(module node: RenderNode, name: String = "main") -> String {
        var b = MLIRBuilder()
        b.open("\"gama.module\"() ({")
        emit(node, into: &b, frame: nil, laid: nil)
        b.close("}) {sym_name = \(MLIRAttr.str(name).rendered)} : () -> ()")
        return b.text
    }

    /// Lowers a laid-out tree, attaching absolute frame geometry to ops.
    public static func lower(laidOut root: LaidOutNode, name: String = "main") -> String {
        var b = MLIRBuilder()
        b.open("\"gama.module\"() ({")
        emit(root.node, into: &b, frame: root.frame, laid: root.children)
        b.close("}) {sym_name = \(MLIRAttr.str(name).rendered)} : () -> ()")
        return b.text
    }

    // MARK: Emission

    private static func emit(
        _ node: RenderNode,
        into b: inout MLIRBuilder,
        frame: Rect?,
        laid: [LaidOutNode]?
    ) {
        switch node {
        case .empty:
            b.line("\"gama.empty\"()\(renderAttrs(frameAttrs(frame))) : () -> ()")

        case .text(let s, let style):
            let attrs: [(String, MLIRAttr)] = [
                ("text", .str(s)),
                ("fg", .color(style.foreground)),
                ("bg", .color(style.background)),
                ("sgr", .i64(Int(style.attributes.rawValue))),
            ]
            b.line("\"gama.text\"()\(renderAttrs(attrs + frameAttrs(frame))) : () -> ()")

        case .spacer(let minLength):
            let attrs: [(String, MLIRAttr)] = [("min", .i64(minLength))]
            b.line("\"gama.spacer\"()\(renderAttrs(attrs + frameAttrs(frame))) : () -> ()")

        case .divider(let style, let axis):
            var attrs: [(String, MLIRAttr)] = [
                ("fg", .color(style.foreground)),
                ("bg", .color(style.background)),
                ("sgr", .i64(Int(style.attributes.rawValue))),
            ]
            if let axis {
                attrs.append(("axis", .str(axis == .horizontal ? "h" : "v")))
            }
            b.line("\"gama.divider\"()\(renderAttrs(attrs + frameAttrs(frame))) : () -> ()")

        case .stack(let axis, let spacing, let alignment, let children):
            region(
                "stack",
                [
                    ("axis", .str(axis == .horizontal ? "h" : "v")),
                    ("spacing", .i64(spacing)),
                    ("halign", .str(name(alignment.horizontal))),
                    ("valign", .str(name(alignment.vertical))),
                ],
                children,
                laid,
                into: &b,
                frame: frame
            )

        case .overlay(let alignment, let children):
            region(
                "overlay",
                [
                    ("halign", .str(name(alignment.horizontal))),
                    ("valign", .str(name(alignment.vertical))),
                ],
                children,
                laid,
                into: &b,
                frame: frame
            )

        case .group(let children):
            region("group", [], children, laid, into: &b, frame: frame)

        case .padding(let e, let child):
            region(
                "padding",
                [
                    ("top", .i64(e.top)), ("leading", .i64(e.leading)),
                    ("bottom", .i64(e.bottom)), ("trailing", .i64(e.trailing)),
                ],
                [child],
                laid,
                into: &b,
                frame: frame
            )

        case .border(let style, let textStyle, let title, let child):
            var attrs: [(String, MLIRAttr)] = [
                ("style", .str(name(style))),
                ("fg", .color(textStyle.foreground)),
            ]
            if let title { attrs.append(("title", .str(title))) }
            region("border", attrs, [child], laid, into: &b, frame: frame)

        case .background(let color, let child):
            region(
                "background",
                [("color", .color(color))],
                [child],
                laid,
                into: &b,
                frame: frame
            )

        case .frame(let w, let h, let alignment, let child):
            var attrs: [(String, MLIRAttr)] = []
            if let w { attrs.append(("width", .i64(w))) }
            if let h { attrs.append(("height", .i64(h))) }
            attrs.append(("halign", .str(name(alignment.horizontal))))
            attrs.append(("valign", .str(name(alignment.vertical))))
            region("frame", attrs, [child], laid, into: &b, frame: frame)

        case .flexFrame(let minW, let maxW, let minH, let maxH, let alignment, let child):
            var attrs: [(String, MLIRAttr)] = []
            if let minW { attrs.append(("min_width", .i64(minW))) }
            if let maxW { attrs.append(("max_width", .i64(maxW == .max ? -1 : maxW))) }
            if let minH { attrs.append(("min_height", .i64(minH))) }
            if let maxH { attrs.append(("max_height", .i64(maxH == .max ? -1 : maxH))) }
            attrs.append(("halign", .str(name(alignment.horizontal))))
            attrs.append(("valign", .str(name(alignment.vertical))))
            region("frame", attrs, [child], laid, into: &b, frame: frame)

        case .styled(let style, let child):
            region(
                "styled",
                [
                    ("fg", .color(style.foreground)),
                    ("bg", .color(style.background)),
                    ("sgr", .i64(Int(style.attributes.rawValue))),
                ],
                [child],
                laid,
                into: &b,
                frame: frame
            )

        case .interactive(let id, let focusable, let child):
            region(
                "interactive",
                [
                    ("id", .i64(Int64(bitPattern: id.raw))),
                    ("focusable", .bool(focusable)),
                ],
                [child],
                laid,
                into: &b,
                frame: frame
            )
        }
    }

    private static func frameAttrs(_ frame: Rect?) -> [(String, MLIRAttr)] {
        guard let frame else { return [] }
        return [
            ("x", .i64(frame.minX)), ("y", .i64(frame.minY)),
            ("w", .i64(frame.size.width)), ("h", .i64(frame.size.height)),
        ]
    }

    private static func region(
        _ op: String,
        _ attrs: [(String, MLIRAttr)],
        _ structuralChildren: [RenderNode],
        _ laid: [LaidOutNode]?,
        into b: inout MLIRBuilder,
        frame: Rect?
    ) {
        b.open("\"gama.\(op)\"() ({")
        if let laid {
            for child in laid {
                emit(
                    child.node,
                    into: &b,
                    frame: child.frame,
                    laid: child.children
                )
            }
        } else {
            for child in structuralChildren {
                emit(child, into: &b, frame: nil, laid: nil)
            }
        }
        b.close("})\(renderAttrs(attrs + frameAttrs(frame))) : () -> ()")
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
