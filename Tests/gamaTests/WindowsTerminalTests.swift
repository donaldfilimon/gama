//  WindowsTerminalTests.swift — Windows console key translation. The
//  translator is pure integer logic outside every platform `#if`, so this
//  runs on every host; the mouse translator's cases are in
//  `PointerBackendTests.swift` (`WindowsMouseTranslatorTests`).

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
}
