#if canImport(SwiftSyntaxMacrosTestSupport)

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import GamaMacrosImpl

final class MacroExpansionTests: XCTestCase {
    private let macros: [String: any Macro.Type] = [
        "Component": ComponentMacro.self,
        "Reactive": ReactiveMacro.self,
        "rgb": RGBMacro.self,
    ]

    func testRGBShorthandAndSixDigitExpansion() {
        assertMacroExpansion(
            "let a = #rgb(\"F80\")\nlet b = #rgb(\"12ABef\")",
            expandedSource: "let a = GamaCore.Color(r: 255, g: 136, b: 0)\nlet b = GamaCore.Color(r: 18, g: 171, b: 239)",
            macros: macros
        )
    }

    func testRGBMalformedLiteralHasActionableDiagnostic() {
        assertMacroExpansion(
            "let color = #rgb(\"oops\")",
            expandedSource: "let color = GamaCore.Color.default",
            diagnostics: [
                .init(
                    message: "invalid hex color 'oops': expected RGB or RRGGBB hex digits",
                    line: 1,
                    column: 13
                )
            ],
            macros: macros
        )
    }

    func testReactiveRejectsImmutablePropertiesOnce() {
        assertMacroExpansion(
            "struct Bad {\n  @Reactive let value: Int = 1\n}",
            expandedSource: "struct Bad {\n  let value: Int = 1\n}",
            diagnostics: [
                .init(message: "@Reactive requires a stored 'var'", line: 2, column: 3)
            ],
            macros: macros
        )
    }

    func testComponentPreservesPublicAccess() {
        assertMacroExpansion(
            "@Component\npublic struct Badge {\n  public var label: String\n  public var body: some GamaCore.View { GamaCore.Text(label) }\n}",
            expandedSource: "public struct Badge {\n  public var label: String\n  public var body: some GamaCore.View { GamaCore.Text(label) }\n\n    public init(label: String) {\n        self.label = label\n    }\n}",
            macros: macros
        )
    }
}

#endif
