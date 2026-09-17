//  GeometryTests.swift — geometry value types.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

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
