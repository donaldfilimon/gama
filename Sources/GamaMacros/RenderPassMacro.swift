// RenderPassMacro.swift — @RenderPass macro implementation

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Attached member macro that generates a `buildDescriptor()` method
/// constructing a `GPURenderPassDescriptor` from the type's properties.
///
/// Expects the annotated type to have:
/// - `colorAttachments: [GPUColorAttachment]`
/// - Optionally `depthAttachment: GPUDepthStencilAttachment?`
public struct RenderPassMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Check for colorAttachments and depthAttachment properties
        var hasColorAttachments = false
        var depthPropertyName: String?

        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = pattern.identifier.trimmed.text

                if name == "colorAttachments" {
                    hasColorAttachments = true
                } else if name.contains("depth") || name.contains("Depth") {
                    depthPropertyName = name
                }
            }
        }

        guard hasColorAttachments else {
            throw MacroError.message("@RenderPass requires a 'colorAttachments' property")
        }

        let depthArg: String
        if let depthName = depthPropertyName {
            depthArg = "\(depthName)"
        } else {
            depthArg = "nil"
        }

        let buildDescriptorDecl: DeclSyntax = """
            func buildDescriptor() -> GPURenderPassDescriptor {
                GPURenderPassDescriptor(
                    colorAttachments: colorAttachments,
                    depthStencilAttachment: \(raw: depthArg)
                )
            }
            """

        return [buildDescriptorDecl]
    }
}
