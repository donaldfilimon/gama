// ShaderBindingMacro.swift — @ShaderBinding macro implementation

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Attached member macro that generates binding index constants for each stored property.
///
/// Generates:
/// - `static let bindingCount: Int`
/// - `static let <name>Index: UInt32` for each property (sequentially numbered)
public struct ShaderBindingMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) else {
            throw MacroError.message("@ShaderBinding can only be applied to structs or classes")
        }

        // Collect stored properties
        var propertyNames: [String] = []
        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            for binding in varDecl.bindings {
                if binding.accessorBlock != nil { continue }

                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                propertyNames.append(pattern.identifier.trimmed.text)
            }
        }

        var decls: [DeclSyntax] = []

        let countDecl: DeclSyntax = "static let bindingCount: Int = \(raw: propertyNames.count)"
        decls.append(countDecl)

        for (index, name) in propertyNames.enumerated() {
            let indexDecl: DeclSyntax = "static let \(raw: name)Index: UInt32 = \(raw: index)"
            decls.append(indexDecl)
        }

        return decls
    }
}
