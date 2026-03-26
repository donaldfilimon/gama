// Plugin.swift — GamaMacros compiler plugin entry point

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
