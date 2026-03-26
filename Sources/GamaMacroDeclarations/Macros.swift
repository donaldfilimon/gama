// Macros.swift — Public macro declarations for Gama

/// Generates GPU buffer layout metadata from a struct's stored properties.
///
/// Adds `static var bufferLayout` and `static var stride` members.
@attached(member, names: named(bufferLayout), named(stride))
public macro GPUBufferLayout() = #externalMacro(module: "GamaMacros", type: "GPUBufferLayoutMacro")

/// Generates shader binding index constants for each stored property.
///
/// Adds `static let bindingCount` and `static let <name>Index` for each property.
@attached(member, names: arbitrary)
public macro ShaderBinding() = #externalMacro(module: "GamaMacros", type: "ShaderBindingMacro")

/// Generates a `buildDescriptor()` method that constructs a `GPURenderPassDescriptor`.
///
/// Requires `colorAttachments` and optionally a depth attachment property.
@attached(member, names: named(buildDescriptor))
public macro RenderPass() = #externalMacro(module: "GamaMacros", type: "RenderPassMacro")
