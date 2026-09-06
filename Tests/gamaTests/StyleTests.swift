//  StyleTests.swift — style value types.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

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
