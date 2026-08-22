import Testing
@testable import GamaCore

@Suite
struct CellGridTests {
    @Test func snapshotStripsTrailingSpaces() {
        var g = CellGrid(width: 4, height: 2)
        g.put(x: 0, y: 0, scalar: "A", style: .plain)
        g.put(x: 0, y: 1, scalar: "B", style: .plain)
        #expect(g.snapshot() == "A\nB")
    }

    @Test func putOutOfBoundsIsDropped() {
        var g = CellGrid(width: 1, height: 1)
        g.put(x: 5, y: 5, scalar: "Z", style: .plain)
        #expect(g[0, 0].scalar == " ")
    }
}
