import Testing
import GamaCore
@testable import GamaTUI

@Suite
struct KeyParserTests {
    @Test func arrowsEnterCtrlCMouse() {
        var p = KeyParser()
        #expect(p.push([0x1b, 0x5b, 0x41]) == [.key(.up)])
        #expect(p.push([0x0d]) == [.key(.enter)])
        #expect(p.push([0x03]) == [.key(.ctrlC)])
        #expect(p.push([0x09]) == [.key(.tab)])
        #expect(p.push([0x1b, 0x5b, 0x5a]) == [.key(.backTab)])
        let seq: [UInt8] = [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x33, 0x3b, 0x35, 0x4d]
        #expect(p.push(seq) == [.mouse(Mouse(kind: .press, button: 0, x: 2, y: 4))])
    }
}
