import Testing
@testable import GamaCore

@Suite
struct DisplayWidthTests {
    @Test func asciiIsOne() {
        #expect(DisplayWidth.of("A") == 1)
    }

    @Test func cjkIsTwoPerScalar() {
        #expect(DisplayWidth.of("你好") == 4)
    }

    @Test func combiningMarkDoesNotAddACell() {
        let s = "e\u{0301}"
        #expect(DisplayWidth.of(s) == 1)
    }
}
