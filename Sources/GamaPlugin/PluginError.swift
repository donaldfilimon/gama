//  PluginError.swift — GamaPlugin
//  The one typed error vocabulary of the plugin layer, following the
//  typed-throws discipline of GamaCore's Runtime.swift: every throwing
//  entry point declares `throws(PluginError)` and callers switch on
//  exact cases instead of matching strings.

/// Typed failures produced by plugin install, activation, contribution
/// validation, and capability-scoped access.
public enum PluginError: Error, Hashable, Sendable {
    /// A plugin with the same ``PluginID`` is already installed in this
    /// runtime.
    case duplicate(PluginID)
    /// The manifest's ABI number does not match
    /// ``PluginManifest/currentABI``.
    case abiMismatch(expected: UInt32, found: UInt32)
    /// A required capability was not granted to the plugin; install
    /// performed no partial activation.
    case missingRequiredCapability(PluginID, Capability)
    /// A required capability is granted but the host supplied no backing
    /// service for it, so the grant fails closed at install.
    case serviceUnavailable(PluginID, Capability)
    /// The plugin's own `activate(in:)` reported failure.
    case activationFailed(PluginID)
    /// A scene contribution asked for the primary role, which is never
    /// available to plugins; the application's primary scene is not up
    /// for grabs. The associated name is the contribution's local name.
    case primarySceneContribution(PluginID, name: String)
    /// A filesystem access fell outside every granted scope, or used a
    /// path the lexical containment rules refuse.
    case accessDenied(path: String)
    /// A granted filesystem operation failed in the underlying platform
    /// I/O layer.
    case ioFailure(path: String)
}
