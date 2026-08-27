//  CellPainter.swift — GamaDraw
//  One painter for every backend: walks laid-out IR into a CellBuffer.
//  Extracted from the TUI renderer so DOM, GUI, and embed hosts paint
//  pixel-identically — a backend only decides how cells reach the screen.

import GamaCore

/// Rasterizes a laid-out tree into a ``CellBuffer`` — the one shared
/// painter every backend drives.
public enum CellPainter {
    /// Paints `root` (and its subtree) into the buffer's back plane.
    public static func paint(_ root: LaidOutNode, into buffer: inout CellBuffer) {
        draw(root, inheritedStyle: .plain, into: &buffer)
    }

    private static func draw(
        _ laid: LaidOutNode, inheritedStyle: TextStyle, into buffer: inout CellBuffer
    ) {
        let frame = laid.frame
        switch laid.node {
        case .empty:
            break

        case .text(let s, let style):
            // Outer wrappers (focus, disabled) win over a child's baked style
            // so a focused custom-colored label still shows the focus wrap.
            buffer.putText(
                s,
                at: frame.origin,
                style: style.merging(inheritedStyle),
                maxWidth: max(1, frame.size.width)
            )

        case .spacer:
            break

        case .divider(let style, let axis):
            let merged = inheritedStyle.merging(style)
            let vertical: Bool
            if let axis {
                vertical = axis == .horizontal
            } else {
                vertical = frame.size.height > frame.size.width
            }
            if vertical {
                let x = frame.minX
                for y in frame.minY..<frame.maxY {
                    buffer.put("│", at: Point(x: x, y: y), style: merged)
                }
            } else {
                let y = frame.minY
                for x in frame.minX..<frame.maxX {
                    buffer.put("─", at: Point(x: x, y: y), style: merged)
                }
            }

        case .background(let color, _):
            buffer.fillBackground(frame, color: color)
            for c in laid.children { draw(c, inheritedStyle: inheritedStyle, into: &buffer) }

        case .styled(let style, _):
            let merged = style.merging(inheritedStyle)
            // Paint style backdrop across the interactive/styled region so
            // focus highlights read as a block, not per-glyph. Outer wrap
            // background wins when both are set.
            if !merged.background.isDefault {
                buffer.fillBackground(frame, color: merged.background)
            }
            for c in laid.children { draw(c, inheritedStyle: merged, into: &buffer) }

        case .border(let borderStyle, let style, let title, _):
            drawBorder(
                borderStyle, style: inheritedStyle.merging(style),
                title: title, in: frame, into: &buffer)
            for c in laid.children { draw(c, inheritedStyle: inheritedStyle, into: &buffer) }

        case .stack, .overlay, .group, .padding, .frame, .flexFrame, .interactive:
            for c in laid.children { draw(c, inheritedStyle: inheritedStyle, into: &buffer) }
        }
    }

    private static func drawBorder(
        _ borderStyle: BorderStyle, style: TextStyle, title: String?, in rect: Rect,
        into buffer: inout CellBuffer
    ) {
        guard rect.size.width >= 2, rect.size.height >= 2 else { return }
        let g = borderStyle.glyphs
        let (tl, top, tr, left, right, bl, bottom, br) = (
            g.topLeft, g.top, g.topRight, g.left, g.right,
            g.bottomLeft, g.bottom, g.bottomRight
        )

        buffer.put(tl, at: Point(x: rect.minX, y: rect.minY), style: style)
        buffer.put(tr, at: Point(x: rect.maxX - 1, y: rect.minY), style: style)
        buffer.put(bl, at: Point(x: rect.minX, y: rect.maxY - 1), style: style)
        buffer.put(br, at: Point(x: rect.maxX - 1, y: rect.maxY - 1), style: style)

        for x in (rect.minX + 1)..<(rect.maxX - 1) {
            buffer.put(top, at: Point(x: x, y: rect.minY), style: style)
            buffer.put(bottom, at: Point(x: x, y: rect.maxY - 1), style: style)
        }
        for y in (rect.minY + 1)..<(rect.maxY - 1) {
            buffer.put(left, at: Point(x: rect.minX, y: y), style: style)
            buffer.put(right, at: Point(x: rect.maxX - 1, y: y), style: style)
        }

        if let title, !title.isEmpty,
            rect.size.width >= TextLayout.displayWidth(of: title) + 4
        {
            var titleStyle = style
            titleStyle.attributes.insert(.bold)
            // Measure reserves displayWidth+4: corner + " title " + corner.
            buffer.putText(
                " \(title) ",
                at: Point(x: rect.minX + 1, y: rect.minY),
                style: titleStyle,
                maxWidth: max(1, rect.size.width - 2)
            )
        }
    }
}
