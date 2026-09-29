//  LayoutMetricsTests.swift — LayoutMetrics parity and scaling coverage.
//
//  LayoutMetricsParityTests proves that with `.cell` metrics (explicit or
//  defaulted) `LayoutEngine` produces byte-identical output to before
//  `LayoutMetrics` existed — the real oracle for that claim is the
//  untouched `LayoutTests`/`P1LayoutTests`/`DrawListTests` suites, run
//  alongside this one. LayoutMetricsScalingTests proves every authored
//  length is actually converted through a non-identity metrics value at
//  the point of use.

import Testing

@testable import GamaCore

@Suite("LayoutMetrics parity with .cell")
struct LayoutMetricsParityTests {
    private static let controlID = NodeID.root.child(7)

    /// One catalog entry: a name for failure messages, a node, and the
    /// bounds/proposal to measure and lay it out under.
    private struct Case {
        let name: String
        let node: RenderNode
        let bounds: Rect
    }

    private static let catalog: [Case] = [
        Case(name: "empty", node: .empty, bounds: Rect(x: 0, y: 0, width: 10, height: 10)),
        Case(
            name: "text simple", node: .text("Hello", style: .plain),
            bounds: Rect(x: 0, y: 0, width: 10, height: 3)),
        Case(
            name: "text wide grapheme", node: .text("界界", style: .plain),
            bounds: Rect(x: 0, y: 0, width: 10, height: 3)),
        Case(
            name: "text zero-width grapheme", node: .text("e\u{301}bc", style: .plain),
            bounds: Rect(x: 0, y: 0, width: 10, height: 3)),
        Case(
            name: "text wrapping", node: .text("hello world foo bar", style: .plain),
            bounds: Rect(x: 0, y: 0, width: 5, height: 10)),
        Case(
            name: "stack horizontal spacing alignment",
            node: .stack(
                axis: .horizontal, spacing: 2,
                alignment: Alignment(horizontal: .leading, vertical: .center),
                children: [.text("a", style: .plain), .text("bbb", style: .plain)]),
            bounds: Rect(x: 0, y: 0, width: 20, height: 5)),
        Case(
            name: "stack vertical spacing alignment",
            node: .stack(
                axis: .vertical, spacing: 1,
                alignment: Alignment(horizontal: .trailing, vertical: .top),
                children: [.text("a", style: .plain), .text("bbb", style: .plain)]),
            bounds: Rect(x: 0, y: 0, width: 10, height: 10)),
        Case(
            name: "stack with flexible spacer",
            node: .stack(
                axis: .horizontal, spacing: 1, alignment: .center,
                children: [
                    .text("a", style: .plain), .spacer(minLength: 0),
                    .text("b", style: .plain),
                ]),
            bounds: Rect(x: 0, y: 0, width: 20, height: 3)),
        Case(
            name: "overlay",
            node: .overlay(
                alignment: .bottomTrailing,
                children: [.text("a", style: .plain), .text("bbb", style: .plain)]),
            bounds: Rect(x: 0, y: 0, width: 10, height: 5)),
        Case(
            name: "group",
            node: .group(children: [.text("a", style: .plain), .text("bb", style: .plain)]),
            bounds: Rect(x: 0, y: 0, width: 10, height: 5)),
        Case(
            name: "spacer with minLength", node: .spacer(minLength: 3),
            bounds: Rect(x: 0, y: 0, width: 8, height: 8)),
        Case(
            name: "divider in horizontal stack",
            node: .stack(
                axis: .horizontal, spacing: 0, alignment: .center,
                children: [.text("a", style: .plain), .divider(style: .plain)]),
            bounds: Rect(x: 0, y: 0, width: 10, height: 4)),
        Case(
            name: "divider in vertical stack",
            node: .stack(
                axis: .vertical, spacing: 0, alignment: .center,
                children: [.text("a", style: .plain), .divider(style: .plain)]),
            bounds: Rect(x: 0, y: 0, width: 4, height: 10)),
        Case(
            name: "padding",
            node: .padding(
                EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2),
                child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 10)),
        Case(
            name: "border without title",
            node: .border(.single, style: .plain, title: nil, child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 6)),
        Case(
            name: "border with title",
            node: .border(.single, style: .plain, title: "T", child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 6)),
        Case(
            name: "background",
            node: .background(.red, child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 4)),
        Case(
            name: "frame",
            node: .frame(
                width: 6, height: 3, alignment: .center, child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 10)),
        Case(
            name: "flexFrame finite bounds",
            node: .flexFrame(
                minWidth: 2, maxWidth: 8, minHeight: 1, maxHeight: 4, alignment: .center,
                child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 10)),
        Case(
            name: "flexFrame max sentinel",
            node: .flexFrame(
                minWidth: nil, maxWidth: .max, minHeight: nil, maxHeight: nil,
                alignment: .center, child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 12, height: 4)),
        Case(
            name: "styled",
            node: .styled(TextStyle(foreground: .red), child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 4)),
        Case(
            name: "interactive",
            node: .interactive(id: controlID, focusable: true, child: .text("hi", style: .plain)),
            bounds: Rect(x: 0, y: 0, width: 10, height: 4)),
        Case(
            name: "nested flex mix",
            node: .stack(
                axis: .horizontal, spacing: 1, alignment: .center,
                children: [
                    .padding(EdgeInsets(all: 1), child: .text("a", style: .plain)),
                    .flexFrame(
                        minWidth: nil, maxWidth: .max, minHeight: nil, maxHeight: nil,
                        alignment: .center, child: .spacer(minLength: 2)),
                    .border(.single, style: .plain, title: nil, child: .text("b", style: .plain)),
                    .spacer(minLength: 1),
                ]),
            bounds: Rect(x: 0, y: 0, width: 40, height: 8)),
    ]

    @Test("measure(_:proposal:) agrees with measure(_:proposal:metrics: .cell)", arguments: catalog)
    private func measureAgreesWithExplicitCell(_ testCase: Case) {
        let proposal = ProposedSize(width: testCase.bounds.size.width, height: testCase.bounds.size.height)
        let implicit = LayoutEngine.measure(testCase.node, proposal: proposal)
        let explicit = LayoutEngine.measure(testCase.node, proposal: proposal, metrics: .cell)
        #expect(implicit == explicit, "\(testCase.name): measure diverged under explicit .cell")
    }

    @Test("layout(_:in:) agrees with layout(_:in:metrics: .cell)", arguments: catalog)
    private func layoutAgreesWithExplicitCell(_ testCase: Case) {
        let implicit = LayoutEngine.layout(testCase.node, in: testCase.bounds)
        let explicit = LayoutEngine.layout(testCase.node, in: testCase.bounds, metrics: .cell)
        #expect(implicit == explicit, "\(testCase.name): layout diverged under explicit .cell")
    }
}

@Suite("LayoutMetrics scaling")
struct LayoutMetricsScalingTests {
    /// 8 layout units per horizontal cell, 17 per vertical cell; text is
    /// 7 units wide per character and 17 tall per line (ignoring the
    /// proposed width — these fixtures use single-line strings, so
    /// wrapping coverage stays in the parity catalog where `.cell` does
    /// the real wrapping work); one fixed-size control at `controlID`.
    private static let controlID = NodeID.root.child(3)
    private static let controlSize = Size(width: 40, height: 12)

    private static func makeMetrics() -> LayoutMetrics {
        LayoutMetrics(
            textSize: { text, _, _ in
                Size(width: text.count * 7, height: 1 * 17)
            },
            units: { cells, axis in cells * (axis == .horizontal ? 8 : 17) },
            dividerThickness: 1,
            controlSize: { id, _ in id == controlID ? controlSize : nil }
        )
    }

    @Test("spacer scales both axes")
    func spacerScalesBothAxes() {
        let metrics = Self.makeMetrics()
        let size = LayoutEngine.measure(
            .spacer(minLength: 2), proposal: .unspecified, metrics: metrics)
        #expect(size == Size(width: 16, height: 34))
    }

    @Test("padding scales per edge with the matching axis")
    func paddingScalesPerEdge() {
        let metrics = Self.makeMetrics()
        let node = RenderNode.padding(
            EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2),
            child: .text("hi", style: .plain))
        // text("hi") -> 2 * 7 = 14 wide, 17 tall.
        // horizontal inset: (2 + 2) cells * 8 = 32; vertical inset: (1 + 1) * 17 = 34.
        let size = LayoutEngine.measure(node, proposal: .unspecified, metrics: metrics)
        #expect(size == Size(width: 14 + 32, height: 17 + 34))

        let laid = LayoutEngine.layout(
            node, in: Rect(x: 0, y: 0, width: 200, height: 200), metrics: metrics)
        // `.padding`'s child is passed the full carved-out box (existing,
        // unchanged pass-through behavior for `.text` in `layout()` — it
        // does not shrink to its own natural size); only the box's
        // origin/extent, driven by the converted insets, is under test
        // here. Horizontal inset = 2+2 cells * 8 = 32; vertical = 1+1
        // cells * 17 = 34.
        #expect(laid.children[0].frame == Rect(x: 16, y: 17, width: 168, height: 166))
    }

    @Test("border insets convert each edge with the matching axis")
    func borderInsetsScalePerAxis() {
        let metrics = Self.makeMetrics()
        // No title: BorderTitleLayout's cell-space width never dominates
        // the scaled child width, keeping this assertion unambiguous.
        let node = RenderNode.border(
            .single, style: .plain, title: nil, child: .text("hi", style: .plain))
        let laid = LayoutEngine.layout(
            node, in: Rect(x: 0, y: 0, width: 200, height: 200), metrics: metrics)
        // Same pass-through note as padding above. Left/right inset = 1
        // cell * 8 = 8; top/bottom inset = 1 cell * 17 = 17.
        #expect(laid.children[0].frame == Rect(x: 8, y: 17, width: 184, height: 166))
    }

    @Test("fixed frame dimensions convert through units")
    func fixedFrameScales() {
        let metrics = Self.makeMetrics()
        let node = RenderNode.frame(
            width: 3, height: 2, alignment: .topLeading, child: .text("hi", style: .plain))
        let size = LayoutEngine.measure(node, proposal: .unspecified, metrics: metrics)
        // width: 3 cells * 8 = 24; height: 2 cells * 17 = 34.
        #expect(size == Size(width: 24, height: 34))

        let laid = LayoutEngine.layout(
            node, in: Rect(x: 0, y: 0, width: 200, height: 200), metrics: metrics)
        #expect(laid.frame == Rect(x: 0, y: 0, width: 24, height: 34))
    }

    @Test("flexFrame finite bounds convert; the .max sentinel never does")
    func flexFrameBoundsScale() {
        let metrics = Self.makeMetrics()
        let finite = RenderNode.flexFrame(
            minWidth: 1, maxWidth: 4, minHeight: nil, maxHeight: nil, alignment: .center,
            child: .text("hi", style: .plain))
        // min 1 cell * 8 = 8 (floor, not binding since text is 14 wide);
        // max 4 cells * 8 = 32 (clamps text's 14 down to... no, 14 < 32,
        // so width stays 14, the child's natural size).
        let finiteSize = LayoutEngine.measure(finite, proposal: .unspecified, metrics: metrics)
        #expect(finiteSize.width == 14)

        let clamped = RenderNode.flexFrame(
            minWidth: nil, maxWidth: 1, minHeight: nil, maxHeight: nil, alignment: .center,
            child: .text("hi", style: .plain))
        // max 1 cell * 8 = 8, clamps the child's 14-wide text down to 8.
        let clampedSize = LayoutEngine.measure(clamped, proposal: .unspecified, metrics: metrics)
        #expect(clampedSize.width == 8)

        let sentinel = RenderNode.flexFrame(
            minWidth: nil, maxWidth: .max, minHeight: nil, maxHeight: nil, alignment: .center,
            child: .text("hi", style: .plain))
        // .max is never passed through units(): were it converted like an
        // authored length, `metrics.units(.max, .horizontal)` would
        // overflow or produce nonsense. Instead the proposal's width (999)
        // passes straight through, proving the sentinel bypassed units().
        let sentinelSize = LayoutEngine.measure(
            sentinel, proposal: ProposedSize(width: 999, height: nil), metrics: metrics)
        #expect(sentinelSize.width == 999)
    }

    @Test("text measures through metrics.textSize")
    func textScales() {
        let metrics = Self.makeMetrics()
        let size = LayoutEngine.measure(
            .text("hello", style: .plain), proposal: .unspecified, metrics: metrics)
        #expect(size == Size(width: 5 * 7, height: 17))
    }

    @Test("stack spacing converts through units on the main axis")
    func stackSpacingScales() {
        let metrics = Self.makeMetrics()
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 1, alignment: .topLeading,
            children: [.text("a", style: .plain), .text("b", style: .plain)])
        let laid = LayoutEngine.layout(
            node, in: Rect(x: 0, y: 0, width: 200, height: 200), metrics: metrics)
        // Each "a"/"b" measures 7 wide; spacing of 1 cell * 8 = 8 units
        // separates the second child's origin from the first's extent.
        #expect(laid.children[0].frame == Rect(x: 0, y: 0, width: 7, height: 17))
        #expect(laid.children[1].frame == Rect(x: 7 + 8, y: 0, width: 7, height: 17))
    }

    @Test("dividers use dividerThickness, not the axis unit scale")
    func dividerUsesThicknessNotUnits() {
        let metrics = Self.makeMetrics()
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0, alignment: .center,
            children: [.text("a", style: .plain), .divider(style: .plain)])
        let laid = LayoutEngine.layout(
            node, in: Rect(x: 0, y: 0, width: 200, height: 200), metrics: metrics)
        // The divider's main-axis extent is 1 (dividerThickness), never
        // scaled by the horizontal unit factor of 8.
        #expect(laid.children[1].frame.size.width == 1)
        #expect(laid.children[1].frame.size.height == 200)
    }

    @Test("controlSize wins over the child's natural size")
    func controlSizeWinsOverChild() {
        let metrics = Self.makeMetrics()
        let node = RenderNode.interactive(
            id: Self.controlID, focusable: true, child: .text("hi", style: .plain))
        let measured = LayoutEngine.measure(node, proposal: .unspecified, metrics: metrics)
        #expect(measured == Self.controlSize)

        // Inside a stack, the stack's own measure of a fixed child honors
        // controlSize too, so the child's frame is exactly the control's
        // registered size, not the text's 14x17.
        let stacked = RenderNode.stack(
            axis: .horizontal, spacing: 0, alignment: .center,
            children: [node, .text("x", style: .plain)])
        let laid = LayoutEngine.layout(
            stacked, in: Rect(x: 0, y: 0, width: 200, height: 200), metrics: metrics)
        #expect(laid.children[0].frame.size == Self.controlSize)
    }

    @Test("flex distribution still works on the converted main axis")
    func flexDistributionOnConvertedAxis() {
        let metrics = Self.makeMetrics()
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0, alignment: .center,
            children: [.text("a", style: .plain), .spacer(minLength: 0)])
        // Available main axis: 200. Fixed "a" = 7. Spacer absorbs the rest.
        let laid = LayoutEngine.layout(
            node, in: Rect(x: 0, y: 0, width: 200, height: 34), metrics: metrics)
        #expect(laid.children[0].frame.size.width == 7)
        #expect(laid.children[1].frame.size.width == 200 - 7)
    }

    @Test("flexMinimum consults controlSize before the flexible child")
    func flexMinimumConsultsControlSize() {
        let metrics = Self.makeMetrics()
        // An interactive node wrapping a flexible spacer: flexPriority
        // delegates to the child (flexible), but the registered control
        // size should still set the floor, not the spacer's minLength.
        let node = RenderNode.interactive(
            id: Self.controlID, focusable: true, child: .spacer(minLength: 1))
        let stack = RenderNode.stack(
            axis: .horizontal, spacing: 0, alignment: .center,
            children: [node])
        let laid = LayoutEngine.layout(
            stack, in: Rect(x: 0, y: 0, width: 5, height: 34), metrics: metrics)
        // mainAvailable (5) is far below the control's width (40); the
        // flex distribution floors at the control's minimum, so the
        // stack reports the child at its control-size floor rather than
        // shrinking it to the spacer's 1-cell minimum (8 units).
        #expect(laid.children[0].frame.size.width == Self.controlSize.width)
    }
}

/// Records the `surfaceSize` its build pass saw; a reference box because
/// views are values and the build runs inside the host.
private final class SurfaceProbe {
    var seen: Size?? = nil
}

/// A primitive that reports the environment's surface size to a probe and
/// lays out as fixed text.
private struct SurfaceReader: View {
    typealias Body = Never_
    var body: Never_ { Never_() }
    let probe: SurfaceProbe
    let label: String
    func render(in context: BuildContext) -> RenderNode {
        probe.seen = .some(context.environment.surfaceSize)
        return .text(label, style: .plain)
    }
}

private struct SurfaceProbeApp: App {
    let probe: SurfaceProbe
    init() { probe = SurfaceProbe() }
    init(probe: SurfaceProbe) { self.probe = probe }
    var scenes: some Scene {
        Window("Probe", id: "main", role: .primary) {
            VStack(spacing: 1) {
                SurfaceReader(probe: probe, label: "hi")
                Text("abc")
            }
        }
    }
}

@Suite("FrameHost metrics")
struct FrameHostMetricsTests {
    /// Same fake as `LayoutMetricsScalingTests`: 8 units per horizontal
    /// cell, 17 per vertical cell, 7 units per character, 17 per line.
    private static func makeMetrics() -> LayoutMetrics {
        LayoutMetrics(
            textSize: { text, _, _ in Size(width: text.count * 7, height: 17) },
            units: { cells, axis in cells * (axis == .horizontal ? 8 : 17) },
            dividerThickness: 1,
            controlSize: { _, _ in nil }
        )
    }

    @Test("a host with scaling metrics lays out in layout units")
    func scalingHostLaysOutInUnits() throws {
        let probe = SurfaceProbe()
        var host = try FrameHost(app: SurfaceProbeApp(probe: probe), metrics: Self.makeMetrics())
        let laid = host.pump(size: Size(width: 160, height: 170))
        var texts: [Rect] = []
        func collect(_ node: LaidOutNode) {
            if case .text = node.node { texts.append(node.frame) }
            for child in node.children { collect(child) }
        }
        collect(laid)
        // "hi" is 14 x 17; spacing 1 vertical cell is 17 units; "abc" 21 x 17.
        #expect(texts.count == 2)
        #expect(texts.first?.size == Size(width: 14, height: 17))
        #expect(texts.last?.size == Size(width: 21, height: 17))
        #expect((texts.last?.minY ?? 0) - (texts.first?.maxY ?? 0) == 17)
    }

    @Test("surfaceSize is the pump size divided by one cell per axis")
    func surfaceSizeIsInCells() throws {
        let probe = SurfaceProbe()
        var host = try FrameHost(app: SurfaceProbeApp(probe: probe), metrics: Self.makeMetrics())
        _ = host.pump(size: Size(width: 165, height: 170))
        // 165 / 8 = 20 (integer division), 170 / 17 = 10.
        #expect(probe.seen == .some(Size(width: 20, height: 10)))
    }

    @Test("a zero cell unit divides by one instead of trapping")
    func zeroUnitDivisorFloorsAtOne() throws {
        let probe = SurfaceProbe()
        let metrics = LayoutMetrics(
            textSize: { text, _, _ in Size(width: text.count, height: 1) },
            units: { _, _ in 0 },
            dividerThickness: 1,
            controlSize: { _, _ in nil }
        )
        var host = try FrameHost(app: SurfaceProbeApp(probe: probe), metrics: metrics)
        _ = host.pump(size: Size(width: 30, height: 12))
        #expect(probe.seen == .some(Size(width: 30, height: 12)))
    }

    @Test("the default host uses cell metrics and reports the pump size")
    func defaultHostIsCell() throws {
        let defaultProbe = SurfaceProbe()
        let cellProbe = SurfaceProbe()
        var defaulted = try FrameHost(app: SurfaceProbeApp(probe: defaultProbe))
        var explicit = try FrameHost(app: SurfaceProbeApp(probe: cellProbe), metrics: .cell)
        let a = defaulted.pump(size: Size(width: 20, height: 6))
        let b = explicit.pump(size: Size(width: 20, height: 6))
        #expect(a == b)
        #expect(defaultProbe.seen == .some(Size(width: 20, height: 6)))
        #expect(cellProbe.seen == .some(Size(width: 20, height: 6)))
    }
}
