import Testing
@testable import GamaCore

@Suite
struct GeometryTests {
    @Test func rectContainsInclusiveOriginExclusiveMax() {
        let r = Rect(origin: Point(x: 2, y: 3), size: Size(width: 4, height: 1))
        #expect(r.contains(Point(x: 2, y: 3)))
        #expect(r.contains(Point(x: 5, y: 3)))
        #expect(!r.contains(Point(x: 6, y: 3)))
        #expect(!r.contains(Point(x: 2, y: 4)))
        #expect(r.maxX == 6 && r.maxY == 4)
    }

    @Test func negativeSizeClampsOnUseInLayoutHelpers() {
        #expect(Size(width: -3, height: -1).clampedNonNegative == Size.zero)
    }
}
