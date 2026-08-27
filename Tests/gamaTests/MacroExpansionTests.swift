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
        diagnostics: [DiagnosticSpec] = [],
        macroSpecs: [String: MacroSpec]? = nil
    ) {
        let specs = macroSpecs ?? macros.mapValues { MacroSpec(type: $0) }
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

    // MARK: #rgb

    @Test("RGB shorthand and six-digit expansion")
    func rgbShorthandAndSixDigitExpansion() {
        expectExpansion(
            "let a = #rgb(\"F80\")\nlet b = #rgb(\"12ABef\")",
            expanded: "let a = GamaCore.Color(r: 255, g: 136, b: 0)\nlet b = GamaCore.Color(r: 18, g: 171, b: 239)"
        )
    }

    @Test("RGB accepts a leading hash")
    func rgbAcceptsLeadingHash() {
        expectExpansion(
            "let a = #rgb(\"#F80\")",
            expanded: "let a = GamaCore.Color(r: 255, g: 136, b: 0)"
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

    @Test("RGB rejects a non-literal argument")
    func rgbRejectsNonLiteralArgument() {
        expectExpansion(
            "let color = #rgb(name)",
            expanded: "let color = GamaCore.Color.default",
            diagnostics: [
                DiagnosticSpec(
                    message: "#rgb requires a plain string literal like #rgb(\"FF8800\")",
                    line: 1,
                    column: 13
                )
            ]
        )
    }

    // MARK: @Reactive

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

    @Test("Reactive expands signal storage and accessors")
    func reactiveExpandsStorageAndAccessors() {
        expectExpansion(
            "struct Counter {\n  @Reactive var value: Int = 1\n}",
            expanded: """
                struct Counter {
                  var value: Int {
                      @storageRestrictions(initializes: _value)
                      init(initialValue) {
                          _value = GamaCore.Signal(initialValue)
                      }
                      get {
                          _value.get()
                      }
                      nonmutating set {
                          _value.set(newValue)
                      }
                  }

                  private let _value: GamaCore.Signal<Int>
                }
                """
        )
    }

    // MARK: @Component

    @Test("Component preserves public access")
    func componentPreservesPublicAccess() {
        expectExpansion(
            "@Component\npublic struct Badge {\n  public var label: String\n  public var body: some GamaCore.View { GamaCore.Text(label) }\n}",
            expanded: "public struct Badge {\n  public var label: String\n  public var body: some GamaCore.View { GamaCore.Text(label) }\n\n    public init(label: String) {\n        self.label = label\n    }\n}"
        )
    }

    @Test("Component rejects classes")
    func componentRejectsClasses() {
        expectExpansion(
            "@Component\nfinal class Bad {\n  var label: String = \"\"\n}",
            expanded: "final class Bad {\n  var label: String = \"\"\n}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@Component can only be applied to structs",
                    line: 1,
                    column: 1
                )
            ]
        )
    }

    @Test("Component extension role adds the View conformance")
    func componentExtensionRoleAddsConformance() {
        expectExpansion(
            "@Component\nstruct Badge {\n  var label: String\n}",
            expanded: """
                struct Badge {
                  var label: String

                    init(label: String) {
                        self.label = label
                    }
                }

                extension Badge: GamaCore.View {
                }
                """,
            macroSpecs: [
                "Component": MacroSpec(
                    type: ComponentMacro.self, conformances: ["GamaCore.View"])
            ]
        )
    }
}

#endif
