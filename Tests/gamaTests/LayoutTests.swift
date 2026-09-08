//  LayoutTests.swift — layout engine behaviour.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

@Suite("Layout")
struct LayoutTests {
    /// ADR 0013: flexibility is per-axis, and the public API now says so.
    /// This is the case the deprecated axis-agnostic property got wrong — a
    /// `maxWidth: .max` frame reported `.flexible` outright, but it only
    /// competes for space inside a horizontal stack.
    @Test("flexPriority(along:) answers per axis")
    func flexPriorityIsPerAxis() {
        let wide = RenderNode.flexFrame(
            minWidth: nil, maxWidth: .max, minHeight: nil, maxHeight: nil,
            alignment: .center, child: .empty)
        #expect(wide.flexPriority(along: .horizontal) == .flexible(weight: 1))
        #expect(wide.flexPriority(along: .vertical) == .fixed)

        let tall = RenderNode.flexFrame(
            minWidth: nil, maxWidth: nil, minHeight: nil, maxHeight: .max,
            alignment: .center, child: .empty)
        #expect(tall.flexPriority(along: .horizontal) == .fixed)
        #expect(tall.flexPriority(along: .vertical) == .flexible(weight: 1))

        // A spacer is flexible on whichever axis it is asked about, and a
        // wrapper is transparent to its child's answer.
        #expect(RenderNode.spacer(minLength: 0).flexPriority(along: .vertical) == .flexible(weight: 1))
        let wrapped = RenderNode.padding(EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1), child: wide)
        #expect(wrapped.flexPriority(along: .horizontal) == .flexible(weight: 1))
        #expect(wrapped.flexPriority(along: .vertical) == .fixed)
    }

    @Test("text measure")
    func textMeasure() {
        let s = LayoutEngine.measure(.text("hello", style: .plain), proposal: .unspecified)
        #expect(s == Size(width: 5, height: 1))
    }

    @Test("text wrap")
    func textWrap() {
        let s = LayoutEngine.measure(
            .text("hello world", style: .plain),
            proposal: ProposedSize(width: 5)
        )
        #expect(s.width == 5)
        #expect(s.height == 2)
    }

    @Test("word wrap breaks on spaces")
    func wordWrapBreaksOnSpaces() {
        #expect(TextLayout.wrap("hello world", width: 5) == ["hello", "world"])
        #expect(TextLayout.wrap("a bb ccc", width: 4) == ["a bb", "ccc"])
    }

    @Test("word wrap hard-breaks long words")
    func wordWrapHardBreaksLongWords() {
        #expect(TextLayout.wrap("abcdefgh", width: 3) == ["abc", "def", "gh"])
    }

    @Test("word wrap preserves newlines")
    func wordWrapPreservesNewlines() {
        #expect(TextLayout.wrap("a\nb", width: 10) == ["a", "b"])
    }

    @Test("unicode display width and wrapping")
    func unicodeDisplayWidthAndWrapping() {
        #expect(TextLayout.displayWidth(of: "e\u{301}") == 1)
        #expect(TextLayout.displayWidth(of: "界") == 2)
        #expect(TextLayout.displayWidth(of: "🙂") == 2)
        #expect(TextLayout.wrap("a界b", width: 3) == ["a界", "b"])
        #expect(TextLayout.size(of: "界a", width: nil) == Size(width: 3, height: 1))
    }

    @Test("exact hard wrap does not append empty line")
    func exactHardWrapDoesNotAppendEmptyLine() {
        #expect(TextLayout.wrap("abc", width: 3) == ["abc"])
        #expect(TextLayout.wrap("abcdef", width: 3) == ["abc", "def"])
    }

    @Test("divider axis resolution")
    func dividerAxisResolution() {
        let h = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("a", style: .plain),
                .divider(style: .plain),
                .text("b", style: .plain),
            ]
        )
        let laidH = LayoutEngine.layout(h, in: Rect(x: 0, y: 0, width: 9, height: 5))
        #expect(laidH.children[1].frame.size.width == 1)
        #expect(laidH.children[1].frame.size.height == 5)

        let v = RenderNode.stack(
            axis: .vertical, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("a", style: .plain),
                .divider(style: .plain),
                .text("b", style: .plain),
            ]
        )
        let laidV = LayoutEngine.layout(v, in: Rect(x: 0, y: 0, width: 9, height: 5))
        #expect(laidV.children[1].frame.size.width == 9)
        #expect(laidV.children[1].frame.size.height == 1)
    }

    @Test("flex remainder fully distributed")
    func flexRemainderFullyDistributed() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .spacer(minLength: 0),
                .spacer(minLength: 0),
                .spacer(minLength: 0),
            ]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 1))
        let total = laid.children.reduce(0) { $0 + $1.frame.size.width }
        #expect(total == 10)
        #expect(laid.children.last!.frame.maxX == 10)
    }

    @Test("spacer honors min length")
    func spacerHonorsMinLength() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("abcdefgh", style: .plain),
                .spacer(minLength: 4),
            ]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 1))
        #expect(laid.children[1].frame.size.width >= 4)
    }

    @Test("VStack stacks vertically")
    func vStackStacksVertically() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 1,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("a", style: .plain),
                .text("b", style: .plain),
            ]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 10))
        #expect(laid.children.count == 2)
        #expect(laid.children[0].frame.minY == 0)
        #expect(laid.children[1].frame.minY == 2)
    }

    @Test("spacer absorbs leftover")
    func spacerAbsorbsLeftover() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("ab", style: .plain),
                .spacer(minLength: 0),
                .text("cd", style: .plain),
            ]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 20, height: 1))
        #expect(laid.children[0].frame.minX == 0)
        #expect(laid.children[2].frame.maxX == 20)
        #expect(laid.children[1].frame.size.width == 16)
    }

    @Test("fixed frame centers child")
    func fixedFrameCentersChild() {
        let node = RenderNode.frame(
            width: 10, height: 3,
            alignment: Alignment(horizontal: .center, vertical: .center),
            child: .text("hi", style: .plain)
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 40, height: 10))
        #expect(laid.frame.size == Size(width: 10, height: 3))
        let child = laid.children[0]
        #expect(child.frame.minX == laid.frame.minX + 4)
        #expect(child.frame.minY == laid.frame.minY + 1)
    }

    @Test("flexible child still contributes its cross extent")
    func flexibleChildContributesCrossExtent() {
        let column = RenderNode.stack(
            axis: .vertical, spacing: 0, alignment: .topLeading,
            children: [
                .flexFrame(
                    minWidth: nil, maxWidth: nil,
                    minHeight: nil, maxHeight: .max,
                    alignment: .topLeading,
                    child: .text("Hello", style: .plain)
                )
            ]
        )
        let m = LayoutEngine.measure(column, proposal: .unspecified)
        #expect(m.width == 5)
    }

    @Test("a flexible column measured inside a row keeps its text unwrapped")
    func flexibleColumnInsideRowIsNotStarvedOnCross() {
        let column = RenderNode.stack(
            axis: .vertical, spacing: 0, alignment: .topLeading,
            children: [
                .flexFrame(
                    minWidth: nil, maxWidth: nil,
                    minHeight: nil, maxHeight: .max,
                    alignment: .topLeading,
                    child: .text("Hello", style: .plain)
                )
            ]
        )
        let row = RenderNode.stack(
            axis: .horizontal, spacing: 0, alignment: .topLeading,
            children: [column, .text("X", style: .plain)]
        )
        let laid = LayoutEngine.layout(row, in: Rect(x: 0, y: 0, width: 20, height: 3))
        #expect(laid.children[0].frame.size.width == 5)
        #expect(laid.children[1].frame.minX == 5)
    }

    @Test("a maxWidth child is not flexible on a column's main axis")
    func flexibilityIsResolvedPerAxis() {
        let column = RenderNode.stack(
            axis: .vertical, spacing: 0, alignment: .topLeading,
            children: [
                .flexFrame(
                    minWidth: nil, maxWidth: .max,
                    minHeight: nil, maxHeight: nil,
                    alignment: .topLeading,
                    child: .text("A", style: .plain)
                ),
                .text("B", style: .plain),
            ]
        )
        let m = LayoutEngine.measure(column, proposal: .unspecified)
        #expect(m.height == 2)

        let laid = LayoutEngine.layout(column, in: Rect(x: 0, y: 0, width: 10, height: 10))
        #expect(laid.children[0].frame.size.height == 1)
        #expect(laid.children[0].frame.size.width == 10)
        #expect(laid.children[1].frame.minY == 1)
    }

    @Test("border reserves two cells")
    func borderReservesTwoCells() {
        let node = RenderNode.border(
            .single, style: .plain, title: nil,
            child: .text("x", style: .plain)
        )
        let m = LayoutEngine.measure(node, proposal: .unspecified)
        #expect(m == Size(width: 3, height: 3))
    }
}
