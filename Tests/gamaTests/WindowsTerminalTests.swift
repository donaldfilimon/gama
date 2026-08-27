#if os(Windows)

import Testing
import GamaCore
@testable import GamaTUI

@Suite("Native Windows console translation")
struct WindowsTerminalTests {
    @Test("maps navigation, modifiers, Unicode, and function keys")
    func keys() {
        #expect(WindowsInputTranslator.key(virtualKey: 0x25, scalar: 0, controlState: 0) == .key(.left))
        #expect(WindowsInputTranslator.key(virtualKey: 0x09, scalar: 9, controlState: 0x10) == .key(.backTab))
        #expect(WindowsInputTranslator.key(virtualKey: 0x70, scalar: 0, controlState: 0) == .key(.function(1)))
        #expect(WindowsInputTranslator.key(virtualKey: 0, scalar: 0x03BB, controlState: 0) == .key(.character("λ")))
        #expect(WindowsInputTranslator.key(virtualKey: 0, scalar: 0x03, controlState: 0) == .key(.ctrl("c")))
    }

    @Test("maps pointer transitions and ignores motion records")
    func pointer() {
        #expect(WindowsInputTranslator.pointer(x: 7, y: 4, buttonState: 1, eventFlags: 0) == .pointer(Point(x: 7, y: 4), pressed: true))
        #expect(WindowsInputTranslator.pointer(x: 7, y: 4, buttonState: 0, eventFlags: 0) == .pointer(Point(x: 7, y: 4), pressed: false))
        #expect(WindowsInputTranslator.pointer(x: 7, y: 4, buttonState: 1, eventFlags: 1) == nil)
    }
}

#endif
