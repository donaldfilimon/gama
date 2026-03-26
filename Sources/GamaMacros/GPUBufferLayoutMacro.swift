// GPUBufferLayoutMacro.swift — @GPUBufferLayout macro implementation

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Attached member macro that generates GPU buffer layout info from a struct's stored properties.
///
/// Generates:
/// - `static var bufferLayout: [String: (offset: Int, size: Int)]`
/// - `static var stride: Int`
public struct GPUBufferLayoutMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.message("@GPUBufferLayout can only be applied to structs")
        }

        let structName = structDecl.name.trimmed.text

        // Collect stored properties (those with no accessor block)
        var properties: [(name: String, type: String)] = []
        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.tokenKind == .keyword(.var) || varDecl.bindingSpecifier.tokenKind == .keyword(.let)
            else { continue }

            for binding in varDecl.bindings {
                // Skip computed properties (those with accessor blocks)
                if binding.accessorBlock != nil { continue }

                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let typeAnnotation = binding.typeAnnotation
                else { continue }

                let name = pattern.identifier.trimmed.text
                let type = typeAnnotation.type.trimmed.description
                properties.append((name: name, type: type))
            }
        }

        // Build the bufferLayout computed property
        var layoutEntries: [String] = []
        for prop in properties {
            layoutEntries.append(
                "            \"\(prop.name)\": (offset: MemoryLayout<\(structName)>.offset(of: \\Self.\(prop.name))!, size: MemoryLayout<\(prop.type)>.size)"
            )
        }

        let layoutDict = layoutEntries.joined(separator: ",\n")

        let bufferLayoutDecl: DeclSyntax = """
            static var bufferLayout: [String: (offset: Int, size: Int)] {
                [
            \(raw: layoutDict)
                ]
            }
            """

        let strideDecl: DeclSyntax = """
            static var stride: Int {
                MemoryLayout<\(raw: structName)>.stride
            }
            """

        return [bufferLayoutDecl, strideDecl]
    }
}
