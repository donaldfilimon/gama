//  Plugin.swift — GamaMacrosImpl
//  Host-side compiler plugin. swift-syntax is confined to this target.

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct GamaPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        ComponentMacro.self,
        ReactiveMacro.self,
        RGBMacro.self,
    ]
}

struct GamaDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String, id: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GamaMacros", id: id)
        self.severity = severity
    }
}

// MARK: - @Component

/// `@Component`: synthesizes a memberwise initializer over stored
/// properties (member role) and adds the missing `GamaCore.View`
/// conformance (extension role). Structs only.
public struct ComponentMacro: MemberMacro, ExtensionMacro {
    // Extension role: add `: GamaCore.View` when the conformance is
    // missing (the compiler passes only missing protocols in).
    /// Extension role: adds `: GamaCore.View` when the compiler reports
    /// the conformance missing.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self), !protocols.isEmpty else { return [] }
        let ext: DeclSyntax = "extension \(type.trimmed): GamaCore.View {}"
        guard let extDecl = ext.as(ExtensionDeclSyntax.self) else { return [] }
        return [extDecl]
    }

    // Member role: memberwise init over stored properties.
    /// Member role: synthesizes the access-mirroring memberwise `init`.
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: GamaDiagnostic(
                        "@Component can only be applied to structs",
                        id: "component.struct-only"
                    )
                )
            )
            return []
        }

        var params: [String] = []
        var assigns: [String] = []

        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            // Skip computed properties (`var body` etc.) and static members.
            let isStatic = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
            if isStatic { continue }
            let isReactive = varDecl.attributes.contains { element in
                guard case .attribute(let attribute) = element else { return false }
                return attribute.attributeName.trimmedDescription == "Reactive"
            }

            for binding in varDecl.bindings {
                guard binding.accessorBlock == nil,
                    let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                    let type = binding.typeAnnotation?.type
                else { continue }

                let name = pattern.identifier.text
                // `let x = fixed` — already initialized constants are not
                // init parameters.
                let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)
                if isLet, binding.initializer != nil { continue }
                // The accessor macro's `init(initialValue)` has already
                // initialized the Signal for a defaulted reactive property.
                if isReactive, binding.initializer != nil { continue }

                if let initial = binding.initializer?.value {
                    params.append("\(name): \(type.trimmed) = \(initial.trimmed)")
                } else {
                    params.append("\(name): \(type.trimmed)")
                }
                assigns.append("self.\(name) = \(name)")
            }
        }

        // Mirror the type's access level: a package/internal component
        // shouldn't leak a public initializer.
        var access = ""
        for m in declaration.modifiers {
            switch m.name.tokenKind {
            case .keyword(.public), .keyword(.package):
                access = m.name.text + " "
            case .keyword(.fileprivate), .keyword(.private):
                access = ""  // memberwise init stays internal-visible to the file
            default:
                break
            }
        }

        let body = assigns.isEmpty ? "" : "\n    " + assigns.joined(separator: "\n    ") + "\n"
        let initDecl: DeclSyntax = """
            \(raw: access)init(\(raw: params.joined(separator: ", "))) {\(raw: body)}
            """
        return [initDecl]
    }
}

// MARK: - @Reactive

/// `@Reactive`: backs a stored `var` with a `GamaCore.Signal` peer and
/// accessor set, so reads/writes route through host-observable state.
public struct ReactiveMacro: PeerMacro, AccessorMacro {
    private static func binding(
        of declaration: some DeclSyntaxProtocol,
        node: AttributeSyntax,
        context: some MacroExpansionContext,
        diagnose: Bool
    ) -> (name: String, type: TypeSyntax)? {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            let binding = varDecl.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
            if diagnose {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(node),
                        message: GamaDiagnostic(
                            "@Reactive requires a stored 'var'",
                            id: "reactive.var-only"
                        )
                    )
                )
            }
            return nil
        }
        guard let type = binding.typeAnnotation?.type else {
            if diagnose {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(node),
                        message: GamaDiagnostic(
                            "@Reactive requires an explicit type annotation",
                            id: "reactive.needs-type"
                        )
                    )
                )
            }
            return nil
        }
        return (pattern.identifier.text, type)
    }

    /// Peer role: emits the `_name: GamaCore.Signal<T>` storage (and owns
    /// the diagnostics, so each error reports exactly once).
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let (name, type) = binding(
            of: declaration, node: node, context: context, diagnose: true
        ) else {
            return []
        }
        return [
            "private let _\(raw: name): GamaCore.Signal<\(type.trimmed)>"
        ]
    }

    /// Accessor role: emits the storage-restricted `init(initialValue)`,
    /// `get`, and `nonmutating set` over the signal.
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let (name, _) = binding(
            of: declaration, node: node, context: context, diagnose: false
        ) else {
            return []
        }
        return [
            """
            @storageRestrictions(initializes: _\(raw: name))
            init(initialValue) {
                _\(raw: name) = GamaCore.Signal(initialValue)
            }
            """,
            "get { _\(raw: name).get() }",
            "nonmutating set { _\(raw: name).set(newValue) }",
        ]
    }
}

// MARK: - #rgb

/// `#rgb`: compile-time hex color literal (`"F80"` or `"FF8800"`,
/// optional leading `#`); malformed input diagnoses and expands to
/// `Color.default` so the expression stays recoverable.
public struct RGBMacro: ExpressionMacro {
    /// Parses the literal and expands to a `GamaCore.Color` constructor.
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard
            let literal = node.arguments.first?.expression.as(StringLiteralExprSyntax.self),
            literal.segments.count == 1,
            case .stringSegment(let segment)? = literal.segments.first
        else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: GamaDiagnostic(
                        "#rgb requires a plain string literal like #rgb(\"FF8800\")",
                        id: "rgb.literal-required"
                    )
                )
            )
            return "GamaCore.Color.default"
        }

        var hex = segment.content.text
        if hex.hasPrefix("#") { hex.removeFirst() }

        func fail() -> ExprSyntax {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: GamaDiagnostic(
                        "invalid hex color '\(segment.content.text)': expected RGB or RRGGBB hex digits",
                        id: "rgb.malformed"
                    )
                )
            )
            return "GamaCore.Color.default"
        }

        if hex.count == 3 {
            // CSS-style shorthand: each digit doubles (F80 → FF8800).
            hex = hex.reduce(into: "") { $0.append($1); $0.append($1) }
        }
        guard hex.count == 6 else { return fail() }
        var bytes: [UInt8] = []
        var iter = hex.makeIterator()
        while let hi = iter.next(), let lo = iter.next() {
            guard let h = hi.hexDigitValue, let l = lo.hexDigitValue else { return fail() }
            bytes.append(UInt8(h * 16 + l))
        }
        guard bytes.count == 3 else { return fail() }

        return "GamaCore.Color(r: \(raw: bytes[0]), g: \(raw: bytes[1]), b: \(raw: bytes[2]))"
    }
}
