#if canImport(SwiftSyntaxMacrosGenericTestSupport)

import SwiftSyntax
import SwiftSyntaxBuilder
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
            expanded: "let a = GamaCore::Color(r: 255, g: 136, b: 0)\nlet b = GamaCore::Color(r: 18, g: 171, b: 239)"
        )
    }

    @Test("RGB accepts a leading hash")
    func rgbAcceptsLeadingHash() {
        expectExpansion(
            "let a = #rgb(\"#F80\")",
            expanded: "let a = GamaCore::Color(r: 255, g: 136, b: 0)"
        )
    }

    @Test("RGB malformed literal has actionable diagnostic")
    func rgbMalformedLiteralHasActionableDiagnostic() {
        expectExpansion(
            "let color = #rgb(\"oops\")",
            expanded: "let color = GamaCore::Color.default",
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
            expanded: "let color = GamaCore::Color.default",
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
                DiagnosticSpec(
                    message: "@Reactive requires a stored 'var'",
                    line: 2,
                    column: 3,
                    fixIts: [FixItSpec(message: "replace 'let' with 'var'")]
                )
            ]
        )
    }

    @Test("Reactive offers no Fix-It when the declaration is not a property")
    func reactiveOffersNoFixItForNonProperties() {
        // `let` -> `var` is only correct when the declaration really is an
        // immutable stored property. Applied to anything else there is no
        // single right edit, so the diagnostic stays advice-only.
        expectExpansion(
            "struct Bad {\n  @Reactive func value() -> Int {\n    1\n  }\n}",
            expanded: "struct Bad {\n  func value() -> Int {\n    1\n  }\n}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@Reactive requires a stored 'var'",
                    line: 2,
                    column: 3,
                    fixIts: []
                )
            ]
        )
    }

    @Test("Reactive offers no let-to-var Fix-It on a property that is already var")
    func reactiveOffersNoFixItWhenAlreadyVar() {
        // A tuple-pattern binding reaches the same diagnostic while already
        // being `var`. Offering "replace 'let' with 'var'" here would apply a
        // rewrite with no `let` to rewrite, so the Fix-It must be withheld.
        expectExpansion(
            "struct Bad {\n  @Reactive var (a, b): (Int, Int) = (1, 2)\n}",
            expanded: "struct Bad {\n  var (a, b): (Int, Int) = (1, 2)\n}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@Reactive requires a stored 'var'",
                    line: 2,
                    column: 3,
                    fixIts: []
                )
            ]
        )
    }

    @Test("Reactive missing-type diagnostic offers no Fix-It")
    func reactiveMissingTypeOffersNoFixIt() {
        // The intended type cannot be recovered from the syntax alone, so
        // offering an edit here would be a guess presented as a fix.
        expectExpansion(
            "struct Bad {\n  @Reactive var value = 1\n}",
            expanded: "struct Bad {\n  var value = 1\n}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@Reactive requires an explicit type annotation",
                    line: 2,
                    column: 3,
                    fixIts: []
                )
            ]
        )
    }

    @Test("Reactive expands slot storage, accessors, and the binding render")
    func reactiveExpandsStorageAccessorsAndRender() {
        expectExpansion(
            "@Component\nstruct Counter {\n  @Reactive var value: Int = 1\n}",
            expanded: """
                struct Counter {
                  var value: Int {
                      @storageRestrictions(initializes: _value)
                      init(initialValue) {
                          _value = GamaCore::ReactiveSlot(initialValue)
                      }
                      get {
                          _value.get()
                      }
                      nonmutating set {
                          _value.set(newValue)
                      }
                  }

                  private let _value: GamaCore::ReactiveSlot<Int>

                    init() {
                    }

                    func render(in context: GamaCore::BuildContext) -> GamaCore::RenderNode {
                        _value._bind(in: context, slot: 0)
                        return body.render(in: context.child(0))
                    }
                }
                """
        )
    }

    @Test("Reactive slots bind in declaration order")
    func reactiveSlotsBindInDeclarationOrder() {
        expectExpansion(
            "@Component\npublic struct Panel {\n  @Reactive var count: Int = 0\n  var label: String\n  @Reactive var step: Int = 1\n}",
            expanded: """
                public struct Panel {
                  var count: Int {
                      @storageRestrictions(initializes: _count)
                      init(initialValue) {
                          _count = GamaCore::ReactiveSlot(initialValue)
                      }
                      get {
                          _count.get()
                      }
                      nonmutating set {
                          _count.set(newValue)
                      }
                  }

                  private let _count: GamaCore::ReactiveSlot<Int>
                  var label: String
                  var step: Int {
                      @storageRestrictions(initializes: _step)
                      init(initialValue) {
                          _step = GamaCore::ReactiveSlot(initialValue)
                      }
                      get {
                          _step.get()
                      }
                      nonmutating set {
                          _step.set(newValue)
                      }
                  }

                  private let _step: GamaCore::ReactiveSlot<Int>

                    public init(label: String) {
                        self.label = label
                    }

                    public func render(in context: GamaCore::BuildContext) -> GamaCore::RenderNode {
                        _count._bind(in: context, slot: 0)
                        _step._bind(in: context, slot: 1)
                        return body.render(in: context.child(0))
                    }
                }
                """
        )
    }

    @Test("Reactive outside a Component struct is an error, not silent local state")
    func reactiveOutsideComponentIsDiagnosed() {
        expectExpansion(
            "struct Plain {\n  @Reactive var value: Int = 1\n}",
            expanded: """
                struct Plain {
                  var value: Int {
                      @storageRestrictions(initializes: _value)
                      init(initialValue) {
                          _value = GamaCore::ReactiveSlot(initialValue)
                      }
                      get {
                          _value.get()
                      }
                      nonmutating set {
                          _value.set(newValue)
                      }
                  }

                  private let _value: GamaCore::ReactiveSlot<Int>
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Reactive requires a struct marked @Component; elsewhere its state never binds to a host",
                    line: 2,
                    column: 3
                )
            ]
        )
    }

    @Test("Reactive in a class is diagnosed by both macros")
    func reactiveInClassIsDiagnosed() {
        expectExpansion(
            "@Component\nfinal class Bad {\n  @Reactive var value: Int = 1\n}",
            expanded: """
                final class Bad {
                  var value: Int {
                      @storageRestrictions(initializes: _value)
                      init(initialValue) {
                          _value = GamaCore::ReactiveSlot(initialValue)
                      }
                      get {
                          _value.get()
                      }
                      nonmutating set {
                          _value.set(newValue)
                      }
                  }

                  private let _value: GamaCore::ReactiveSlot<Int>
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Reactive requires a struct marked @Component; elsewhere its state never binds to a host",
                    line: 3,
                    column: 3
                ),
                DiagnosticSpec(
                    message: "@Component can only be applied to structs",
                    line: 1,
                    column: 1,
                    fixIts: [FixItSpec(message: "remove '@Component'")]
                ),
            ]
        )
    }

    @Test("Component refuses to skip the binding render silently")
    func componentDiagnosesHandWrittenRenderCollision() {
        expectExpansion(
            "@Component\nstruct Custom {\n  @Reactive var value: Int = 1\n  func render(in context: GamaCore.BuildContext) -> GamaCore.RenderNode {\n    .empty\n  }\n}",
            expanded: """
                struct Custom {
                  var value: Int {
                      @storageRestrictions(initializes: _value)
                      init(initialValue) {
                          _value = GamaCore::ReactiveSlot(initialValue)
                      }
                      get {
                          _value.get()
                      }
                      nonmutating set {
                          _value.set(newValue)
                      }
                  }

                  private let _value: GamaCore::ReactiveSlot<Int>
                  func render(in context: GamaCore.BuildContext) -> GamaCore.RenderNode {
                    .empty
                  }

                    init() {
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Component synthesizes render(in:) to bind @Reactive state; remove this render(in:) or the @Reactive properties",
                    line: 4,
                    column: 3
                )
            ]
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
                    column: 1,
                    fixIts: [FixItSpec(message: "remove '@Component'")]
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

                extension Badge: GamaCore::View {
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
