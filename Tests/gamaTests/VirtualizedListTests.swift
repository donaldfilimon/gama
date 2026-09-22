//  VirtualizedListTests.swift — windowed collection rendering: only the
//  rows the surface can show are built, arrow keys move the window and are
//  consumed at both ends, and rows render under element identity. Without
//  a surface size (host-less rendering) the list falls back to building
//  every row.

import Testing

@testable import GamaCore

/// Every string drawn anywhere in a laid-out tree, in visual order.
private func texts(in laid: LaidOutNode) -> [String] {
    var out: [String] = []
    func walk(_ n: LaidOutNode) {
        if case .text(let s, _) = n.node { out.append(s) }
        for c in n.children { walk(c) }
    }
    walk(laid)
    return out
}

private func containsRow(_ laid: LaidOutNode, _ label: String) -> Bool {
    texts(in: laid).contains { $0.contains(label) }
}

private struct BigListApp: App {
    init() {}

    var scenes: some Scene {
        Window("Big", id: "main", role: .primary) {
            VirtualizedList(0..<1000, id: { NodeID(raw: UInt64($0 + 1)) }) { index in
                Text("row \(index)")
            }
        }
    }
}

@Suite("Virtualized list")
struct VirtualizedListTests {
    @Test("only the rows the surface can show are built")
    func buildsOnlyTheVisibleWindow() throws {
        var host = try FrameHost(app: BigListApp())
        let laid = host.pump(size: Size(width: 20, height: 12))
        #expect(containsRow(laid, "row 0"))
        #expect(!containsRow(laid, "row 900"))
        // The window is bounded by the surface, not by the collection.
        let drawn = texts(in: laid).filter { $0.contains("row ") }
        #expect(drawn.count <= 12)
    }

    @Test("the window moves when the focused list is scrolled down")
    func scrollingMovesTheWindow() throws {
        var host = try FrameHost(app: BigListApp())
        _ = host.pump(size: Size(width: 20, height: 12))
        for _ in 0..<20 { host.handle(.key(.down)) }
        let laid = host.pump(size: Size(width: 20, height: 12))
        #expect(!containsRow(laid, "row 0"))
        #expect(containsRow(laid, "row 20"))
    }

    @Test("scrolling up at the top is consumed and does not move the window")
    func scrollClampsAtTheTop() throws {
        var host = try FrameHost(app: BigListApp())
        _ = host.pump(size: Size(width: 20, height: 12))
        for _ in 0..<5 { host.handle(.key(.up)) }
        let laid = host.pump(size: Size(width: 20, height: 12))
        #expect(containsRow(laid, "row 0"))
    }

    @Test("scrolling past the end stops on the last row")
    func scrollClampsAtTheBottom() throws {
        var host = try FrameHost(app: BigListApp())
        _ = host.pump(size: Size(width: 20, height: 12))
        for _ in 0..<5000 { host.handle(.key(.down)) }
        let laid = host.pump(size: Size(width: 20, height: 12))
        #expect(containsRow(laid, "row 999"))
        #expect(!containsRow(laid, "row 0"))
    }

    @Test("host-less rendering has no surface, so it builds every row")
    func hostLessRenderingBuildsEverything() {
        let node = VirtualizedList(0..<50, id: { NodeID(raw: UInt64($0 + 1)) }) { index in
            Text("row \(index)")
        }.render(in: BuildContext())
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 20, height: 4))
        let drawn = texts(in: laid).filter { $0.contains("row ") }
        #expect(drawn.count == 50)
    }

    @Test("rows render under element identity, not position")
    func rowsUseElementIdentity() {
        let node = VirtualizedList([10, 20, 30], id: { NodeID(raw: UInt64($0)) }) { value in
            Button("v\(value)") {}
        }.render(in: BuildContext())
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 20, height: 6))
        var regions: [InteractiveRegion] = []
        laid.collectInteractive(into: &regions)
        let ids = regions.map(\.id)
        #expect(ids.contains(NodeID(raw: 10 as UInt64)))
        #expect(ids.contains(NodeID(raw: 30 as UInt64)))
    }
}
