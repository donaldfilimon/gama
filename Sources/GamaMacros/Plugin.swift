// Plugin.swift — GamaMacros compiler plugin entry point
// Part of GamaMacros

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct GamaMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GPUBufferLayoutMacro.self,
        ShaderBindingMacro.self,
        RenderPassMacro.self,
    ]
}
