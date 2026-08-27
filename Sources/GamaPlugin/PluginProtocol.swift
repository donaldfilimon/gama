//  PluginProtocol.swift — GamaPlugin
//  The Tier-1 plugin contract: a statically-registered feature module
//  compiled into the application. Plugins contribute render IR, not
//  views: RenderNode is the framework's own Sendable value erasure
//  boundary, so contributions stay portable and Embedded-compatible
//  without `any View` existentials.

import GamaCore

/// Names one render slot an application opts into with ``PluginSlot``.
public struct SlotID: Hashable, Sendable, ExpressibleByStringLiteral {
    /// The application-defined slot name.
    public var raw: String

    /// Creates a slot identity from its raw string.
    public init(_ raw: String) { self.raw = raw }
    /// Creates a slot identity from a string literal.
    public init(stringLiteral value: String) { self.raw = value }
}

/// The runtime plugin contract. A conforming value carries a static
/// ``PluginManifest``, receives everything it may touch through the
/// ``PluginContext`` handed to `activate(in:)`, and contributes
/// host-mediated render IR. Its lifecycle is owned by the
/// ``PluginRuntime`` it is installed into.
public protocol GamaPluginProtocol: Sendable {
    /// Static identity, version, ABI, and capability declaration.
    var manifest: PluginManifest { get }
    /// Called once at install, on the host's executor. Everything the
    /// plugin may touch arrives here; keep what you need.
    mutating func activate(in context: PluginContext) throws(PluginError)
    /// Called once at uninstall or when the owning runtime is destroyed.
    mutating func deactivate()
    /// Render-IR contribution for a named slot the application renders.
    /// The default contributes nothing.
    func render(slot: SlotID, in context: BuildContext) -> RenderNode
}

extension GamaPluginProtocol {
    /// Default no-op deactivation.
    public mutating func deactivate() {}

    /// Default slot contribution: nothing.
    public func render(slot: SlotID, in context: BuildContext) -> RenderNode {
        .empty
    }
}
