#if canImport(SwiftSyntaxMacrosGenericTestSupport)

import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import GamaMacrosImpl

@Suite("Macro expansion")
struct MacroExpansionTests {
    private let macros: [String: any Macro.Type] = [
        "Component": ComponentMacro.self,
        "Reactive": ReactiveMacro.self,
        "rgb": RGBMacro.self,
    ]

    private func expectExpansion(
        _ original: String,
        expanded: String,
        diagnostics: [DiagnosticSpec] = []
    ) {
        let specs = macros.mapValues { MacroSpec(type: $0) }
        assertMacroExpansion(
            original,
            expandedSource: expanded,
            diagnostics: diagnostics,
            macroSpecs: specs,
            failureHandler: { spec in
                Issue.record(
                    Comment(rawValue: spec.message),
                    sourceLocation: SourceLocation(
                        fileID: spec.location.fileID,
                        filePath: spec.location.filePath,
                        line: spec.location.line,
                        column: spec.location.column
                    )
                )
            }
        )
    }

    @Test("RGB shorthand and six-digit expansion")
    func rgbShorthandAndSixDigitExpansion() {
        expectExpansion(
            "let a = #rgb(\"F80\")\nlet b = #rgb(\"12ABef\")",
            expanded: "let a = GamaCore.Color(r: 255, g: 136, b: 0)\nlet b = GamaCore.Color(r: 18, g: 171, b: 239)"
        )
    }

    @Test("RGB malformed literal has actionable diagnostic")
    func rgbMalformedLiteralHasActionableDiagnostic() {
        expectExpansion(
            "let color = #rgb(\"oops\")",
            expanded: "let color = GamaCore.Color.default",
            diagnostics: [
                DiagnosticSpec(
                    message: "invalid hex color 'oops': expected RGB or RRGGBB hex digits",
                    line: 1,
                    column: 13
                )
            ]
        )
    }

    @Test("Reactive rejects immutable properties once")
    func reactiveRejectsImmutablePropertiesOnce() {
        expectExpansion(
            "struct Bad {\n  @Reactive let value: Int = 1\n}",
            expanded: "struct Bad {\n  let value: Int = 1\n}",
            diagnostics: [
                DiagnosticSpec(message: "@Reactive requires a stored 'var'", line: 2, column: 3)
            ]
        )
    }

    @Test("Component preserves public access")
    func componentPreservesPublicAccess() {
        expectExpansion(
            "@Component\npublic struct Badge {\n  public var label: String\n  public var body: some GamaCore.View { GamaCore.Text(label) }\n}",
            expanded: "public struct Badge {\n  public var label: String\n  public var body: some GamaCore.View { GamaCore.Text(label) }\n\n    public init(label: String) {\n        self.label = label\n    }\n}"
        )
    }
}

#endif
