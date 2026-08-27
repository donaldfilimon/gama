//  GamaTests.swift — Swift Testing suites for core, layout, draw, and host.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

/// Mutable box for observer callbacks. Tests may import Synchronization;
/// GamaCore cannot. This keeps `@Sendable` closures compiling without
/// `nonisolated(unsafe)` counters.
private final class TestBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@Suite("Geometry")
struct GeometryTests {
    @Test("umbrella re-exports the core")
    func umbrellaReExportsCore() {
        // `import Gama` alone must surface GamaCore's API (via @_exported).
        let size: Gama.Size = Size(width: 2, height: 1)
        #expect(size.width == 2)
    }

    @Test("rect inset")
    func rectInset() {
        let r = Rect(x: 0, y: 0, width: 10, height: 6)
        let i = r.inset(by: EdgeInsets(all: 1))
        #expect(i == Rect(x: 1, y: 1, width: 8, height: 4))
    }

    @Test("NodeID child stability")
    func nodeIDChildStability() {
        let a = NodeID.root.child(0).child(3)
        let b = NodeID.root.child(0).child(3)
        let c = NodeID.root.child(1).child(3)
        #expect(a == b)
        #expect(a != c)
    }
}

@Suite("Style")
struct StyleTests {
    @Test("merging prefers override")
    func mergingPrefersOverride() {
        let base = TextStyle(foreground: .red, attributes: [.bold])
        let over = TextStyle(foreground: .blue)
        let m = base.merging(over)
        #expect(m.foreground == .blue)
        #expect(m.attributes.contains(.bold))
    }

    @Test("merging keeps base when default")
    func mergingKeepsBaseWhenDefault() {
        let base = TextStyle(foreground: .red)
        let m = base.merging(.plain)
        #expect(m.foreground == .red)
    }

    @Test("xterm 256 grayscale")
    func xterm256Grayscale() {
        let g = Color(r: 128, g: 128, b: 128)
        let code = g.xterm256
        #expect((232...255).contains(Int(code)) || code == 8 || (16...231).contains(Int(code)))
    }
}

@Suite("Layout")
struct LayoutTests {
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

@Suite("View builder")
struct BuilderTests {
    @Test("render nodes remain hashable")
    func renderNodesRemainHashable() {
        func requireHashable<T: Hashable>(_: T.Type) {}

        requireHashable(RenderNode.self)
        requireHashable(LaidOutNode.self)
    }

    @Test("tuple flattening")
    func tupleFlattening() {
        struct Two: View {
            var body: some View {
                Text("a")
                Text("b")
            }
        }
        let ir = Two().render(in: BuildContext(id: .root))
        guard case .group(let children) = ir else {
            Issue.record("expected group sentinel, got \(ir)")
            return
        }
        #expect(children.count == 2)
        let flat = flattenChildren(ir)
        #expect(flat.count == 2)
    }

    @Test("conditional")
    func conditional() {
        struct Cond: View {
            var flag: Bool
            var body: some View {
                if flag { Text("yes") } else { Text("no") }
            }
        }
        let yes = Cond(flag: true).render(in: BuildContext(id: .root))
        guard case .text(let s, _) = yes else {
            Issue.record("expected text")
            return
        }
        #expect(s == "yes")
    }

    @Test("ForEach")
    func forEach() {
        struct Listy: View {
            var body: some View {
                VStack {
                    ForEach([1, 2, 3]) { n in Text("\(n)") }
                }
            }
        }
        let ir = Listy().render(in: BuildContext(id: .root))
        guard case .stack(_, _, _, let children) = ir else {
            Issue.record("expected stack")
            return
        }
        #expect(children.count == 3)
    }

    @Test("ZStack(.topLeading) layers instead of flattening")
    func zStackTopLeadingLayersInsteadOfFlattening() {
        struct Layered: View {
            var body: some View {
                VStack {
                    ZStack(alignment: .topLeading) {
                        Text("under")
                        Text("over")
                    }
                }
            }
        }
        let ir = Layered().render(in: BuildContext(id: .root))
        guard case .stack(_, _, _, let children) = ir else {
            Issue.record("expected VStack, got \(ir)")
            return
        }
        #expect(children.count == 1, "ZStack(.topLeading) must remain one overlay child")
        guard case .overlay(let alignment, let layered) = children[0] else {
            Issue.record("expected overlay, got \(children[0])")
            return
        }
        #expect(alignment == Alignment.topLeading)
        #expect(layered.count == 2)
    }
}

@Suite("Signal")
struct SignalTests {
    @Test("observe and cancel")
    func observeAndCancel() {
        let s = Signal(0)
        let hits = TestBox(0)
        let token = s.observe { hits.value += 1 }
        s.set(1)
        #expect(hits.value == 1)
        s.cancel(token)
        s.set(2)
        #expect(hits.value == 1)
        #expect(s.get() == 2)
    }

    @Test("host-owned subscription invalidates and cancels in isolation")
    func hostOwnedSubscriptionInvalidatesAndCancelsInIsolation() throws {
        struct StaticApp: App {
            var scenes: some Scene {
                Window("Model", id: "main", role: .primary) { Text("model") }
            }
        }
        let model = Signal(0)
        var first = try FrameHost(app: StaticApp())
        var second = try FrameHost(app: StaticApp())
        first.observe(model)
        first.observe(model)
        second.observe(model)
        _ = first.pump(size: Size(width: 10, height: 1))
        _ = second.pump(size: Size(width: 10, height: 1))
        // Bind before #expect: the macro's property-access form needs a
        // Copyable base, and FrameHost is deliberately noncopyable.
        let pumpedStates = (first.needsFrame, second.needsFrame)
        #expect(!pumpedStates.0)
        #expect(!pumpedStates.1)

        first.cancelSubscriptions()
        model.set(1)
        let cancelledStates = (first.needsFrame, second.needsFrame)
        #expect(!cancelledStates.0)
        #expect(cancelledStates.1)
    }

    @Test("binding can receive explicit subscription context")
    func bindingCanReceiveExplicitSubscriptionContext() {
        let model = Signal(1)
        let invalidations = TestBox(0)
        let context = SubscriptionContext { invalidations.value += 1 }
        let binding = model.binding(in: context)
        binding.wrappedValue = 2
        #expect(invalidations.value == 1)
        #expect(model.get() == 2)
        context.cancelAll()
        model.set(3)
        #expect(invalidations.value == 1)
    }

    @Test("reentrant set does not reenter observers")
    func reentrantSetDoesNotReenterObservers() {
        let s = Signal(0)
        let hits = TestBox(0)
        let token = s.observe {
            hits.value += 1
            if s.get() == 1 { s.set(2) }
        }
        s.set(1)
        #expect(hits.value == 1)
        #expect(s.get() == 2)
        s.cancel(token)
    }

    @Test("observer added during notify defers to next change")
    func observerAddedDuringNotifyDefersToNextChange() {
        let s = Signal(0)
        let lateHits = TestBox(0)
        let added = TestBox(false)
        let token = s.observe {
            if !added.value {
                added.value = true
                s.observe { lateHits.value += 1 }
            }
        }
        s.set(1)
        #expect(lateHits.value == 0)
        s.set(2)
        #expect(lateHits.value == 1)
        s.cancel(token)
    }

    @Test("setIfChanged skips redundant notifies")
    func setIfChangedSkipsRedundantNotifies() {
        let s = Signal(7)
        let hits = TestBox(0)
        s.observe { hits.value += 1 }
        s.setIfChanged(7)
        #expect(hits.value == 0)
        s.setIfChanged(8)
        #expect(hits.value == 1)
    }

    @Test("binding reads and writes through Signal")
    func bindingReadsAndWritesThroughSignal() {
        let s = Signal(1)
        let b = s.binding()
        #expect(b.wrappedValue == 1)
        b.wrappedValue = 5
        #expect(s.get() == 5)

        let doubled = b.map(get: { $0 * 2 }, set: { v, new in v = new / 2 })
        #expect(doubled.wrappedValue == 10)
        doubled.wrappedValue = 8
        #expect(s.get() == 4)
    }

    @Test("signal routes changes to explicit observer")
    func signalRoutesChangesToExplicitObserver() {
        let fired = TestBox(0)
        let s = Signal("a")
        s.observe { fired.value += 1 }
        s.set("b")
        #expect(fired.value == 1)
    }

    @Test("concurrent hosts remain isolated")
    func concurrentHostsRemainIsolated() async {
        struct ConcurrentApp: App {
            let count: Signal<Int>
            init() { count = Signal(0) }
            init(count: Signal<Int>) { self.count = count }
            var scenes: some Scene {
                Window("Concurrent", id: "main", role: .primary) {
                    Button("increment") { count.update { $0 += 1 } }
                }
            }
        }

        let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let count = Signal(0)
                    var host = try! FrameHost(app: ConcurrentApp(count: count))
                    _ = host.pump(size: Size(width: 20, height: 2))
                    host.handle(.key(.enter))
                    _ = host.pump(size: Size(width: 20, height: 2))
                    return count.get()
                }
            }
            var values: [Int] = []
            for await value in group { values.append(value) }
            return values
        }
        #expect(results.count == 16)
        #expect(results.allSatisfy { $0 == 1 })
    }
}

@Suite("Actions")
struct ActionTests {
    @Test("collect interactive order")
    func collectInteractiveOrder() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .interactive(id: NodeID.root.child(1), focusable: true, child: .text("a", style: .plain)),
                .interactive(id: NodeID.root.child(2), focusable: true, child: .text("b", style: .plain)),
            ]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 4))
        var out: [InteractiveRegion] = []
        laid.collectInteractive(into: &out)
        #expect(out.map(\.id) == [NodeID.root.child(1), NodeID.root.child(2)])
    }

    @Test("disabled button does not register and is not focusable")
    func disabledButtonDoesNotRegisterAndIsNotFocusable() {
        let pressed = TestBox(false)
        let button = Button("go") { pressed.value = true }.disabled()
        let registered = TestBox<(@Sendable () -> Void)?>(nil)
        let ctx = BuildContext(id: .root, registerAction: { _, action in registered.value = action })
        let node = button.render(in: ctx)

        guard case .interactive(_, let focusable, _) = node else {
            Issue.record("expected interactive node, got \(node)")
            return
        }
        #expect(!focusable)
        #expect(registered.value == nil)
        #expect(!pressed.value)
    }

    @Test("enabled button still registers")
    func enabledButtonStillRegisters() {
        let pressed = TestBox(false)
        let button = Button("go") { pressed.value = true }.disabled(false)
        let registered = TestBox<(@Sendable () -> Void)?>(nil)
        let context = BuildContext(id: .root, registerAction: { _, action in registered.value = action })
        let node = button.render(in: context)
        guard case .interactive(_, let focusable, _) = node else {
            Issue.record("expected interactive node")
            return
        }
        #expect(focusable)
        registered.value?()
        #expect(pressed.value)
    }
}

@Suite("Cell buffer")
struct CellBufferTests {
    @Test("equal buffers compare equal")
    func equalBuffersCompareEqual() {
        var left = CellBuffer(size: Size(width: 4, height: 1))
        var right = CellBuffer(size: Size(width: 4, height: 1))
        left.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        right.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        #expect(left == right)
        right.putText("aB", at: .zero, style: .plain, maxWidth: 4)
        #expect(left != right)
    }

    @Test("diff only emits changes")
    func diffOnlyEmitsChanges() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        let first = buf.presentDiff()
        #expect(!first.isEmpty)

        buf.clearBack()
        buf.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        let second = buf.presentDiff()
        #expect(second.isEmpty, "identical frame should emit nothing")

        buf.clearBack()
        buf.putText("aB", at: .zero, style: .plain, maxWidth: 4)
        let third = buf.presentDiff()
        #expect(third.contains("B"))
        #expect(!third.contains("a"), "unchanged cell should be skipped")
    }
}

@Suite("MLIR")
struct MLIRTests {
    @Test("structural lowering well formed")
    func structuralLoweringWellFormed() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 1,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("hello \"mlir\"", style: TextStyle(foreground: .red)),
                .spacer(minLength: 2),
                .divider(style: .plain),
            ]
        )
        let mlir = GamaLowering.lower(module: node, name: "t")
        #expect(mlir.contains("\"gama.module\"()"))
        #expect(mlir.contains("sym_name = \"t\""))
        #expect(mlir.contains("\"gama.stack\"()"))
        #expect(mlir.contains("axis = \"v\""))
        #expect(mlir.contains(#"text = "hello \"mlir\"""#))
        #expect(mlir.contains("dense<[224, 64, 64]> : tensor<3xi8>"))
        #expect(mlir.contains("min = 2 : i64"))
        #expect(mlir.contains("\"gama.divider\"()"))
        #expect(mlir.filter { $0 == "{" }.count == mlir.filter { $0 == "}" }.count)
    }

    @Test("group sentinel lowers to gama.group")
    func groupSentinelLowersToGamaGroup() {
        let node = RenderNode.group(children: [
            .text("a", style: .plain), .text("b", style: .plain),
        ])
        let mlir = GamaLowering.lower(module: node, name: "grouped")
        // Proves the Capabilities.md claim: the flatten sentinel reaches
        // the dialect as its own op, not as an overlay.
        #expect(mlir.contains("\"gama.group\"()"))
        #expect(!mlir.contains("\"gama.overlay\"()"))
    }

    @Test("interactive NodeID emits full 64-bit id")
    func interactiveNodeIDEmitsFull64BitId() {
        let id = NodeID(raw: 1 << 40)
        let node = RenderNode.interactive(
            id: id, focusable: true, child: .text("x", style: .plain))
        let mlir = GamaLowering.lower(module: node, name: "id64")
        #expect(mlir.contains("id = \(Int64(bitPattern: id.raw)) : i64"))
        #expect(!mlir.contains("id = 0 : i64"))
    }

    @Test("frame-annotated lowering carries geometry")
    func frameAnnotatedLoweringCarriesGeometry() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [.text("hi", style: .plain)]
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 8, height: 2))
        let mlir = GamaLowering.lower(laidOut: laid, name: "geo")
        #expect(mlir.contains("x = 0 : i64"))
        #expect(mlir.contains("w = "))
        #expect(mlir.contains("\"gama.text\"()"))
    }
}

@Suite("Run iteration")
struct RunIterationTests {
    @Test("forEachRun merges identical styles")
    func forEachRunMergesIdenticalStyles() {
        var buf = CellBuffer(size: Size(width: 6, height: 1))
        buf.clearBack()
        let red = TextStyle(foreground: .red)
        buf.putText("ab", at: Point(x: 0, y: 0), style: red, maxWidth: 6)
        buf.putText("cd", at: Point(x: 2, y: 0), style: red, maxWidth: 4)
        var runs: [(String, TextStyle)] = []
        buf.forEachRun { _, _, _, text, style in runs.append((text, style)) }
        #expect(runs.count == 2)
        #expect(runs[0].0 == "abcd")
        #expect(runs[0].1.foreground == .red)
        #expect(runs[1].0 == "  ")
    }

    @Test("forEachRun splits on style change")
    func forEachRunSplitsOnStyleChange() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.clearBack()
        buf.putText("ab", at: Point(x: 0, y: 0), style: TextStyle(foreground: .red), maxWidth: 4)
        buf.putText("cd", at: Point(x: 2, y: 0), style: TextStyle(foreground: .blue), maxWidth: 2)
        var runs: [String] = []
        buf.forEachRun { _, _, _, text, _ in runs.append(text) }
        #expect(runs == ["ab", "cd"])
    }
}

@Suite("DrawList")
struct DrawListTests {
    @Test("from buffer skips blank default runs")
    func fromBufferSkipsBlankDefaultRuns() {
        var buf = CellBuffer(size: Size(width: 10, height: 2))
        buf.clearBack()
        buf.putText("hi", at: Point(x: 1, y: 0), style: .plain, maxWidth: 2)
        let list = DrawList.from(buf)
        #expect(list.commands.count == 1)
        guard case .text(let s, let p, _) = list.commands[0] else {
            Issue.record("expected text")
            return
        }
        #expect(s == "hi")
        #expect(p == Point(x: 1, y: 0))
    }

    @Test("from buffer emits background rects")
    func fromBufferEmitsBackgroundRects() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.clearBack()
        buf.fillBackground(Rect(x: 0, y: 0, width: 4, height: 1), color: .blue)
        let list = DrawList.from(buf)
        #expect(
            list.commands.contains { cmd in
                if case .fillRect(let r, let c) = cmd {
                    return r == Rect(x: 0, y: 0, width: 4, height: 1) && c == .blue
                }
                return false
            }
        )
        #expect(!list.commands.contains { if case .text = $0 { return true } else { return false } })
    }

    @Test("binary round trip")
    func binaryRoundTrip() throws {
        var style = TextStyle(foreground: .red, background: .blue)
        style.attributes = [.bold, .underline]
        let original = DrawList(
            size: Size(width: 80, height: 24),
            commands: [
                .fillRect(Rect(x: 2, y: 3, width: 10, height: 1), Color(r: 8, g: 16, b: 32)),
                .fillRect(Rect(x: 0, y: 0, width: 80, height: 24), .default),
                .text("héllo — 世界", at: Point(x: 5, y: 7), style: style),
                .text("plain", at: Point(x: 0, y: 0), style: .plain),
            ]
        )
        #expect(try DrawList.decode(original.encode()) == original)
    }

    @Test("decode rejects garbage")
    func decodeRejectsGarbage() {
        #expect(throws: DrawList.DecodeError.truncated) { try DrawList.decode([]) }
        #expect(throws: DrawList.DecodeError.badMagic) { try DrawList.decode([1, 2, 3, 4]) }
        var truncated = DrawList(
            size: Size(width: 1, height: 1),
            commands: [.text("x", at: Point(x: 0, y: 0), style: .plain)]
        ).encode()
        truncated.removeLast()
        #expect(throws: DrawList.DecodeError.truncated) { try DrawList.decode(truncated) }
    }
}

@Suite("Cell painter")
struct CellPainterTests {
    @Test("painter matches direct paint")
    func painterMatchesDirectPaint() {
        let node = RenderNode.border(
            .rounded, style: TextStyle(foreground: .cyan), title: "T",
            child: .text("body", style: .plain)
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 12, height: 3))
        var buf = CellBuffer(size: Size(width: 12, height: 3))
        buf.clearBack()
        CellPainter.paint(laid, into: &buf)
        #expect(buf.cell(atX: 0, y: 0)?.character == "╭")
        #expect(buf.cell(atX: 11, y: 2)?.character == "╯")
        var titleCell: Cell?
        for x in 0..<12 {
            if buf.cell(atX: x, y: 0)?.character == "T" {
                titleCell = buf.cell(atX: x, y: 0)
                break
            }
        }
        #expect(titleCell != nil)
        #expect(titleCell?.style.attributes.contains(.bold) == true)
    }
}

private struct HostProbeApp: App {
    var scenes: some Scene {
        Window("Probe", id: "main", role: .primary) {
            VStack(spacing: 1) {
                Button("One", action: {})
                Button("Two", action: {})
            }
        }
    }
}

private struct HostIsolationApp: App {
    let value: Signal<Int>
    init() { value = Signal(0) }
    init(value: Signal<Int>) { self.value = value }

    var scenes: some Scene {
        Window("Isolation", id: "main", role: .primary) {
            Button("Increment") { value.update { $0 += 1 } }
        }
    }
}

@Suite("FrameHost")
struct FrameHostTests {
    @Test("focus cycles with tab")
    func focusCyclesWithTab() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.tab))
        // Bound before #expect throughout this suite: the macro's
        // property-access form needs a Copyable base, and FrameHost is
        // deliberately noncopyable.
        let dirtyAfterTab = host.needsFrame
        #expect(dirtyAfterTab)
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.tab))
        _ = host.pump(size: Size(width: 20, height: 6))
        let quitRequested = host.wantsQuit
        #expect(!quitRequested)
    }

    @Test("ctrl-C requests quit")
    func ctrlCRequestsQuit() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.ctrl("c")))
        let quitRequested = host.wantsQuit
        #expect(quitRequested)
    }

    @Test("resize marks dirty")
    func resizeMarksDirty() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        let cleanAfterPump = host.needsFrame
        #expect(!cleanAfterPump)
        host.handle(.resize(Size(width: 30, height: 8)))
        let dirtyAfterResize = host.needsFrame
        #expect(dirtyAfterResize)
    }

    @Test("resize event records lastSize and dirties")
    func resizeEventRecordsLastSizeAndDirties() throws {
        var host = try FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        let sizeAfterPump = host.lastSize
        let cleanAfterPump = host.needsFrame
        #expect(sizeAfterPump == Size(width: 20, height: 6))
        #expect(!cleanAfterPump)
        host.handle(.resize(Size(width: 30, height: 8)))
        let sizeAfterResize = host.lastSize
        let dirtyAfterResize = host.needsFrame
        #expect(sizeAfterResize == Size(width: 30, height: 8))
        #expect(dirtyAfterResize)
    }

    @Test("hosts keep actions and dirty state isolated")
    func hostsKeepActionsAndDirtyStateIsolated() throws {
        let leftValue = Signal(0)
        let rightValue = Signal(0)
        var left = try FrameHost(app: HostIsolationApp(value: leftValue))
        var right = try FrameHost(app: HostIsolationApp(value: rightValue))
        _ = left.pump(size: Size(width: 20, height: 3))
        _ = right.pump(size: Size(width: 20, height: 3))

        left.handle(.key(.enter))

        #expect(leftValue.get() == 1)
        #expect(rightValue.get() == 0)
        let dirtyStates = (left.needsFrame, right.needsFrame)
        #expect(dirtyStates.0)
        #expect(!dirtyStates.1)
    }
}
