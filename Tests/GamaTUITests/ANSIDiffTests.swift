import Testing
import GamaCore
@testable import GamaTUI

@Suite
struct ANSIDiffTests {
    @Test func emptyToAContainsScalarAndCSI() {
        let old = CellGrid(width: 1, height: 1)
        var new = CellGrid(width: 1, height: 1)
        new.put(x: 0, y: 0, scalar: "A", style: .plain)
        let encoded = ANSIDiff.encode(old: old, new: new)
        #expect(encoded.contains("A"))
        #expect(encoded.contains("\u{1b}"))
    }
}
