//  ViewBuilderTests.swift — result-builder composition.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

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
