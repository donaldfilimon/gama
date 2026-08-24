//  GamaTests.swift
import XCTest

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

final class GeometryTests: XCTestCase {
    func testLegacyGreetingCompatibility() {
        XCTAssertEqual(hello(), "Hello, world!")
    }
    func testRectInset() {
        let r = Rect(x: 0, y: 0, width: 10, height: 6)
        let i = r.inset(by: EdgeInsets(all: 1))
        XCTAssertEqual(i, Rect(x: 1, y: 1, width: 8, height: 4))
    }

    func testNodeIDChildStability() {
        let a = NodeID.root.child(0).child(3)
        let b = NodeID.root.child(0).child(3)
        let c = NodeID.root.child(1).child(3)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

final class StyleTests: XCTestCase {
    func testMergingPrefersOverride() {
        let base = TextStyle(foreground: .red, attributes: [.bold])
        let over = TextStyle(foreground: .blue)
        let m = base.merging(over)
        XCTAssertEqual(m.foreground, .blue)
        XCTAssertTrue(m.attributes.contains(.bold))
    }

    func testMergingKeepsBaseWhenDefault() {
        let base = TextStyle(foreground: .red)
        let m = base.merging(.plain)
        XCTAssertEqual(m.foreground, .red)
    }

    func testXterm256Grayscale() {
        let g = Color(r: 128, g: 128, b: 128)
        let code = g.xterm256
        XCTAssertTrue((232...255).contains(Int(code)) || code == 8 || (16...231).contains(Int(code)))
    }
}

final class LayoutTests: XCTestCase {
    func testTextMeasure() {
        let s = LayoutEngine.measure(
            .text("hello", style: .plain), proposal: .unspecified)
        XCTAssertEqual(s, Size(width: 5, height: 1))
    }

    func testTextWrap() {
        let s = LayoutEngine.measure(
            .text("hello world", style: .plain),
            proposal: ProposedSize(width: 5))
        XCTAssertEqual(s.width, 5)
        XCTAssertEqual(s.height, 2)  // word wrap: "hello" / "world"
    }

    func testWordWrapBreaksOnSpaces() {
        XCTAssertEqual(TextLayout.wrap("hello world", width: 5), ["hello", "world"])
        XCTAssertEqual(TextLayout.wrap("a bb ccc", width: 4), ["a bb", "ccc"])
    }

    func testWordWrapHardBreaksLongWords() {
        XCTAssertEqual(TextLayout.wrap("abcdefgh", width: 3), ["abc", "def", "gh"])
    }

    func testWordWrapPreservesNewlines() {
        XCTAssertEqual(TextLayout.wrap("a\nb", width: 10), ["a", "b"])
    }

    func testUnicodeDisplayWidthAndWrapping() {
        XCTAssertEqual(TextLayout.displayWidth(of: "e\u{301}"), 1)
        XCTAssertEqual(TextLayout.displayWidth(of: "界"), 2)
        XCTAssertEqual(TextLayout.displayWidth(of: "🙂"), 2)
        XCTAssertEqual(TextLayout.wrap("a界b", width: 3), ["a界", "b"])
        XCTAssertEqual(TextLayout.size(of: "界a", width: nil), Size(width: 3, height: 1))
    }

    func testExactHardWrapDoesNotAppendEmptyLine() {
        XCTAssertEqual(TextLayout.wrap("abc", width: 3), ["abc"])
        XCTAssertEqual(TextLayout.wrap("abcdef", width: 3), ["abc", "def"])
    }

    func testDividerAxisResolution() {
        let h = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("a", style: .plain),
                .divider(style: .plain),
                .text("b", style: .plain),
            ])
        let laidH = LayoutEngine.layout(h, in: Rect(x: 0, y: 0, width: 9, height: 5))
        // 1 wide, full height in an HStack.
        XCTAssertEqual(laidH.children[1].frame.size.width, 1)
        XCTAssertEqual(laidH.children[1].frame.size.height, 5)

        let v = RenderNode.stack(
            axis: .vertical, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("a", style: .plain),
                .divider(style: .plain),
                .text("b", style: .plain),
            ])
        let laidV = LayoutEngine.layout(v, in: Rect(x: 0, y: 0, width: 9, height: 5))
        // full width, 1 tall in a VStack.
        XCTAssertEqual(laidV.children[1].frame.size.width, 9)
        XCTAssertEqual(laidV.children[1].frame.size.height, 1)
    }

    func testFlexRemainderFullyDistributed() {
        // 3 equal-weight spacers over 10 cells: shares must sum to 10.
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .spacer(minLength: 0),
                .spacer(minLength: 0),
                .spacer(minLength: 0),
            ])
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 1))
        let total = laid.children.reduce(0) { $0 + $1.frame.size.width }
        XCTAssertEqual(total, 10)
        XCTAssertEqual(laid.children.last!.frame.maxX, 10)
    }

    func testSpacerHonorsMinLength() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("abcdefgh", style: .plain),
                .spacer(minLength: 4),
            ])
        // Only 10 wide: text takes 8, spacer must still get its 4 minimum
        // (measure reports the overflow; layout floors at the minimum).
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 1))
        XCTAssertGreaterThanOrEqual(laid.children[1].frame.size.width, 4)
    }

    func testVStackStacksVertically() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 1, alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("a", style: .plain),
                .text("b", style: .plain),
            ])
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(laid.children.count, 2)
        XCTAssertEqual(laid.children[0].frame.minY, 0)
        XCTAssertEqual(laid.children[1].frame.minY, 2)  // 1 line + spacing 1
    }

    func testSpacerAbsorbsLeftover() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("ab", style: .plain),
                .spacer(minLength: 0),
                .text("cd", style: .plain),
            ])
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 20, height: 1))
        XCTAssertEqual(laid.children[0].frame.minX, 0)
        XCTAssertEqual(laid.children[2].frame.maxX, 20)
        XCTAssertEqual(laid.children[1].frame.size.width, 16)
    }

    func testFixedFrameCentersChild() {
        let node = RenderNode.frame(
            width: 10, height: 3,
            alignment: Alignment(horizontal: .center, vertical: .center),
            child: .text("hi", style: .plain))
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 40, height: 10))
        XCTAssertEqual(laid.frame.size, Size(width: 10, height: 3))
        let child = laid.children[0]
        XCTAssertEqual(child.frame.minX, laid.frame.minX + 4)
        XCTAssertEqual(child.frame.minY, laid.frame.minY + 1)
    }

    func testBorderReservesTwoCells() {
        let node = RenderNode.border(
            .single, style: .plain, title: nil,
            child: .text("x", style: .plain))
        let m = LayoutEngine.measure(node, proposal: .unspecified)
        XCTAssertEqual(m, Size(width: 3, height: 3))
    }
}

final class BuilderTests: XCTestCase {
    func testTupleFlattening() {
        struct Two: View {
            var body: some View {
                Text("a")
                Text("b")
            }
        }
        let ir = Two().render(in: BuildContext(id: .root))
        guard case .overlay(_, let children) = ir else {
            // Body of two views renders via TupleView sentinel overlay.
            return XCTFail("expected sentinel overlay, got \(ir)")
        }
        XCTAssertEqual(children.count, 2)
        let flat = flattenChildren(ir)
        XCTAssertEqual(flat.count, 2)
    }

    func testConditional() {
        struct Cond: View {
            var flag: Bool
            var body: some View {
                if flag { Text("yes") } else { Text("no") }
            }
        }
        let yes = Cond(flag: true).render(in: BuildContext(id: .root))
        guard case .text(let s, _) = yes else { return XCTFail("expected text") }
        XCTAssertEqual(s, "yes")
    }

    func testForEach() {
        struct Listy: View {
            var body: some View {
                VStack {
                    ForEach([1, 2, 3]) { n in Text("\(n)") }
                }
            }
        }
        let ir = Listy().render(in: BuildContext(id: .root))
        guard case .stack(_, _, _, let children) = ir else { return XCTFail("expected stack") }
        XCTAssertEqual(children.count, 3)
    }
}

final class SignalTests: XCTestCase {
    func testObserveAndCancel() {
        let s = Signal(0)
        nonisolated(unsafe) var hits = 0
        let token = s.observe { hits += 1 }
        s.set(1)
        XCTAssertEqual(hits, 1)
        s.cancel(token)
        s.set(2)
        XCTAssertEqual(hits, 1)
        XCTAssertEqual(s.get(), 2)
    }

    func testHostOwnedSubscriptionInvalidatesAndCancelsInIsolation() {
        struct StaticApp: App {
            var content: some View { Text("model") }
        }
        let model = Signal(0)
        var first = FrameHost(app: StaticApp())
        var second = FrameHost(app: StaticApp())
        first.observe(model)
        first.observe(model) // duplicate connection is coalesced
        second.observe(model)
        _ = first.pump(size: Size(width: 10, height: 1))
        _ = second.pump(size: Size(width: 10, height: 1))
        XCTAssertFalse(first.needsFrame)
        XCTAssertFalse(second.needsFrame)

        first.cancelSubscriptions()
        model.set(1)
        XCTAssertFalse(first.needsFrame)
        XCTAssertTrue(second.needsFrame)
    }

    func testBindingCanReceiveExplicitSubscriptionContext() {
        let model = Signal(1)
        nonisolated(unsafe) var invalidations = 0
        let context = SubscriptionContext { invalidations += 1 }
        let binding = model.binding(in: context)
        binding.wrappedValue = 2
        XCTAssertEqual(invalidations, 1)
        XCTAssertEqual(model.get(), 2)
        context.cancelAll()
        model.set(3)
        XCTAssertEqual(invalidations, 1)
    }

    func testReentrantSetDoesNotReenterObservers() {
        let s = Signal(0)
        nonisolated(unsafe) var hits = 0
        s.observe {
            hits += 1
            if s.get() == 1 { s.set(2) }  // re-entrant set inside observer
        }
        s.set(1)
        XCTAssertEqual(hits, 1)  // inner set coalesced into the outer pass
        XCTAssertEqual(s.get(), 2)
    }

    func testObserverAddedDuringNotifyDefersToNextChange() {
        let s = Signal(0)
        nonisolated(unsafe) var lateHits = 0
        nonisolated(unsafe) var added = false
        s.observe {
            if !added {
                added = true
                s.observe { lateHits += 1 }
            }
        }
        s.set(1)
        XCTAssertEqual(lateHits, 0)  // not called in the pass that added it
        s.set(2)
        XCTAssertEqual(lateHits, 1)
    }

    func testSetIfChangedSkipsRedundantNotifies() {
        let s = Signal(7)
        nonisolated(unsafe) var hits = 0
        s.observe { hits += 1 }
        s.setIfChanged(7)
        XCTAssertEqual(hits, 0)
        s.setIfChanged(8)
        XCTAssertEqual(hits, 1)
    }

    func testBindingReadsAndWritesThroughSignal() {
        let s = Signal(1)
        let b = s.binding()
        XCTAssertEqual(b.wrappedValue, 1)
        b.wrappedValue = 5
        XCTAssertEqual(s.get(), 5)

        let doubled = b.map(get: { $0 * 2 }, set: { v, new in v = new / 2 })
        XCTAssertEqual(doubled.wrappedValue, 10)
        doubled.wrappedValue = 8
        XCTAssertEqual(s.get(), 4)
    }

    func testSignalRoutesChangesToExplicitObserver() {
        nonisolated(unsafe) var fired = 0
        let s = Signal("a")
        s.observe { fired += 1 }
        s.set("b")
        XCTAssertEqual(fired, 1)
    }

    func testConcurrentHostsRemainIsolated() async {
        struct ConcurrentApp: App {
            let count: Signal<Int>
            init() { count = Signal(0) }
            init(count: Signal<Int>) { self.count = count }
            var content: some View {
                Button("increment") { count.update { $0 += 1 } }
            }
        }

        let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let count = Signal(0)
                    var host = FrameHost(app: ConcurrentApp(count: count))
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
        XCTAssertEqual(results.count, 16)
        XCTAssertTrue(results.allSatisfy { $0 == 1 })
    }
}

final class ActionTests: XCTestCase {
    func testCollectInteractiveOrder() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .interactive(id: NodeID.root.child(1), focusable: true, child: .text("a", style: .plain)),
                .interactive(id: NodeID.root.child(2), focusable: true, child: .text("b", style: .plain)),
            ])
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 4))
        var out: [(NodeID, Rect, focusable: Bool)] = []
        laid.collectInteractive(into: &out)
        XCTAssertEqual(out.map(\.0), [NodeID.root.child(1), NodeID.root.child(2)])
    }

    func testDisabledButtonDoesNotRegisterAndIsNotFocusable() {
        nonisolated(unsafe) var pressed = false
        let button = Button("go") { pressed = true }.disabled()
        nonisolated(unsafe) var registered: (@Sendable () -> Void)?
        let ctx = BuildContext(id: .root, registerAction: { _, action in registered = action })
        let node = button.render(in: ctx)

        guard case .interactive(_, let focusable, _) = node else {
            return XCTFail("expected interactive node, got \(node)")
        }
        XCTAssertFalse(focusable)
        XCTAssertNil(registered)
        XCTAssertFalse(pressed)
    }

    func testEnabledButtonStillRegisters() {
        nonisolated(unsafe) var pressed = false
        let button = Button("go") { pressed = true }.disabled(false)
        nonisolated(unsafe) var registered: (@Sendable () -> Void)?
        let context = BuildContext(id: .root, registerAction: { _, action in registered = action })
        let node = button.render(in: context)
        guard case .interactive(_, let focusable, _) = node else {
            return XCTFail("expected interactive node")
        }
        XCTAssertTrue(focusable)
        registered?()
        XCTAssertTrue(pressed)
    }
}

final class CellBufferTests: XCTestCase {
    func testDiffOnlyEmitsChanges() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        let first = buf.presentDiff()
        XCTAssertFalse(first.isEmpty)

        buf.clearBack()
        buf.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        let second = buf.presentDiff()
        XCTAssertTrue(second.isEmpty, "identical frame should emit nothing")

        buf.clearBack()
        buf.putText("aB", at: .zero, style: .plain, maxWidth: 4)
        let third = buf.presentDiff()
        XCTAssertTrue(third.contains("B"))
        XCTAssertFalse(third.contains("a"), "unchanged cell should be skipped")
    }
}

final class MLIRTests: XCTestCase {
    func testStructuralLoweringWellFormed() {
        let node = RenderNode.stack(
            axis: .vertical, spacing: 1,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [
                .text("hello \"mlir\"", style: TextStyle(foreground: .red)),
                .spacer(minLength: 2),
                .divider(style: .plain),
            ])
        let mlir = GamaLowering.lower(module: node, name: "t")
        XCTAssertTrue(mlir.contains("\"gama.module\"()"))
        XCTAssertTrue(mlir.contains("sym_name = \"t\""))
        XCTAssertTrue(mlir.contains("\"gama.stack\"()"))
        XCTAssertTrue(mlir.contains("axis = \"v\""))
        XCTAssertTrue(mlir.contains(#"text = "hello \"mlir\"""#))
        XCTAssertTrue(mlir.contains("dense<[224, 64, 64]> : tensor<3xi8>"))
        XCTAssertTrue(mlir.contains("min = 2 : i64"))
        XCTAssertTrue(mlir.contains("\"gama.divider\"()"))
        // Balanced regions.
        XCTAssertEqual(
            mlir.filter { $0 == "{" }.count,
            mlir.filter { $0 == "}" }.count)
    }

    func testFrameAnnotatedLoweringCarriesGeometry() {
        let node = RenderNode.stack(
            axis: .horizontal, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [.text("hi", style: .plain)])
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 8, height: 2))
        let mlir = GamaLowering.lower(laidOut: laid, name: "geo")
        XCTAssertTrue(mlir.contains("x = 0 : i64"))
        XCTAssertTrue(mlir.contains("w = "))
        XCTAssertTrue(mlir.contains("\"gama.text\"()"))
    }
}

// MARK: - Multi-backend (GamaDraw / FrameHost)

final class RunIterationTests: XCTestCase {
    func testForEachRunMergesIdenticalStyles() {
        var buf = CellBuffer(size: Size(width: 6, height: 1))
        buf.clearBack()
        let red = TextStyle(foreground: .red)
        buf.putText("ab", at: Point(x: 0, y: 0), style: red, maxWidth: 6)
        buf.putText("cd", at: Point(x: 2, y: 0), style: red, maxWidth: 4)
        var runs: [(String, TextStyle)] = []
        buf.forEachRun { _, _, _, text, style in runs.append((text, style)) }
        // "abcd" merges into one run; trailing blanks form a second.
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].0, "abcd")
        XCTAssertEqual(runs[0].1.foreground, .red)
        XCTAssertEqual(runs[1].0, "  ")
    }

    func testForEachRunSplitsOnStyleChange() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.clearBack()
        buf.putText("ab", at: Point(x: 0, y: 0), style: TextStyle(foreground: .red), maxWidth: 4)
        buf.putText("cd", at: Point(x: 2, y: 0), style: TextStyle(foreground: .blue), maxWidth: 2)
        var runs: [String] = []
        buf.forEachRun { _, _, _, text, _ in runs.append(text) }
        XCTAssertEqual(runs, ["ab", "cd"])
    }
}

final class DrawListTests: XCTestCase {
    func testFromBufferSkipsBlankDefaultRuns() {
        var buf = CellBuffer(size: Size(width: 10, height: 2))
        buf.clearBack()
        buf.putText("hi", at: Point(x: 1, y: 0), style: .plain, maxWidth: 2)
        let list = DrawList.from(buf)
        XCTAssertEqual(list.commands.count, 1)
        guard case .text(let s, let p, _) = list.commands[0] else {
            return XCTFail("expected text")
        }
        XCTAssertEqual(s, "hi")
        XCTAssertEqual(p, Point(x: 1, y: 0))
    }

    func testFromBufferEmitsBackgroundRects() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.clearBack()
        buf.fillBackground(Rect(x: 0, y: 0, width: 4, height: 1), color: .blue)
        let list = DrawList.from(buf)
        XCTAssertTrue(list.commands.contains { cmd in
            if case .fillRect(let r, let c) = cmd {
                return r == Rect(x: 0, y: 0, width: 4, height: 1) && c == .blue
            }
            return false
        })
        // Blank text over a colored background produces no text command.
        XCTAssertFalse(list.commands.contains { if case .text = $0 { return true } else { return false } })
    }

    func testBinaryRoundTrip() {
        var style = TextStyle(foreground: .red, background: .blue)
        style.attributes = [.bold, .underline]
        let original = DrawList(
            size: Size(width: 80, height: 24),
            commands: [
                .fillRect(Rect(x: 2, y: 3, width: 10, height: 1), Color(r: 8, g: 16, b: 32)),
                .fillRect(Rect(x: 0, y: 0, width: 80, height: 24), .default),
                .text("héllo — 世界", at: Point(x: 5, y: 7), style: style),
                .text("plain", at: Point(x: 0, y: 0), style: .plain),
            ])
        let decoded = DrawList.decode(original.encode())
        XCTAssertEqual(decoded, original)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(DrawList.decode([]))
        XCTAssertNil(DrawList.decode([1, 2, 3, 4]))
        var truncated = DrawList(
            size: Size(width: 1, height: 1),
            commands: [.text("x", at: Point(x: 0, y: 0), style: .plain)]
        ).encode()
        truncated.removeLast()
        XCTAssertNil(DrawList.decode(truncated))
    }
}

final class CellPainterTests: XCTestCase {
    func testPainterMatchesDirectPaint() {
        let node = RenderNode.border(
            .rounded, style: TextStyle(foreground: .cyan), title: "T",
            child: .text("body", style: .plain))
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 12, height: 3))
        var buf = CellBuffer(size: Size(width: 12, height: 3))
        buf.clearBack()
        CellPainter.paint(laid, into: &buf)
        XCTAssertEqual(buf.cell(atX: 0, y: 0)?.character, "╭")
        XCTAssertEqual(buf.cell(atX: 11, y: 2)?.character, "╯")
        // Title renders bold at x=2.
        XCTAssertEqual(buf.cell(atX: 3, y: 0)?.character, "T")
        XCTAssertTrue(buf.cell(atX: 3, y: 0)?.style.attributes.contains(.bold) ?? false)
    }
}

private struct HostProbeApp: App {
    var content: some View {
        VStack(spacing: 1) {
            Button("One", action: {})
            Button("Two", action: {})
        }
    }
}

private struct HostIsolationApp: App {
    let value: Signal<Int>
    init() { value = Signal(0) }
    init(value: Signal<Int>) { self.value = value }

    var content: some View {
        Button("Increment") { value.update { $0 += 1 } }
    }
}

final class FrameHostTests: XCTestCase {
    func testFocusCyclesWithTab() {
        var host = FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.tab))
        XCTAssertTrue(host.needsFrame)
        // Two focusables: tab twice returns to the first — a third pump
        // must not crash and focus stays resolvable.
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.tab))
        _ = host.pump(size: Size(width: 20, height: 6))
        XCTAssertFalse(host.wantsQuit)
    }

    func testCtrlCRequestsQuit() {
        var host = FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        host.handle(.key(.ctrl("c")))
        XCTAssertTrue(host.wantsQuit)
    }

    func testResizeMarksDirty() {
        var host = FrameHost(app: HostProbeApp())
        _ = host.pump(size: Size(width: 20, height: 6))
        XCTAssertFalse(host.needsFrame)
        host.handle(.resize(Size(width: 30, height: 8)))
        XCTAssertTrue(host.needsFrame)
    }

    func testHostsKeepActionsAndDirtyStateIsolated() {
        let leftValue = Signal(0)
        let rightValue = Signal(0)
        var left = FrameHost(app: HostIsolationApp(value: leftValue))
        var right = FrameHost(app: HostIsolationApp(value: rightValue))
        _ = left.pump(size: Size(width: 20, height: 3))
        _ = right.pump(size: Size(width: 20, height: 3))

        left.handle(.key(.enter))

        XCTAssertEqual(leftValue.get(), 1)
        XCTAssertEqual(rightValue.get(), 0)
        XCTAssertTrue(left.needsFrame)
        XCTAssertFalse(right.needsFrame)
    }
}
