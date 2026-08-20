import Testing
@testable import GamaCore

@Suite
struct ViewBuilderTests {
    @Test func nodeIDFromStringLiteral() {
        let id: NodeID = "ok"
        #expect(id.raw == "ok")
    }

    @Test func vstackBuilderFlattensTwoTexts() {
        let node = VStack {
            Text("a")
            Text("b")
        }
        guard case .stack(let axis, _, let spacing, let children) = node else {
            Issue.record("expected stack")
            return
        }
        #expect(axis == .vertical)
        #expect(spacing == 0)
        #expect(children == [.text("a", .plain), .text("b", .plain)])
    }

    @Test func progressClamps() {
        #expect(Progress(-1) == .progress(0))
        #expect(Progress(2) == .progress(1))
    }
}
