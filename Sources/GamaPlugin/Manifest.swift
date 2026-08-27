//  Manifest.swift — GamaPlugin
//  Static plugin identity: who a plugin is, what it needs, and which ABI
//  it was written against. The manifest is code, not a data file: Gama's
//  portable core has no runtime file loading, and a Swift value is
//  typo-checked by the compiler where a JSON manifest is typo-checked in
//  production.

/// Stable reverse-DNS identity for one plugin, e.g. `"dev.gama.stats"`.
public struct PluginID: Hashable, Sendable, ExpressibleByStringLiteral {
    /// The reverse-DNS identity string.
    public var raw: String

    /// Creates an identity from its raw string.
    public init(_ raw: String) { self.raw = raw }
    /// Creates an identity from a string literal.
    public init(stringLiteral value: String) { self.raw = value }
}

/// Semantic plugin version without Foundation: three plain integers.
public struct PluginVersion: Hashable, Sendable {
    /// Incompatible-change counter.
    public var major: Int
    /// Backward-compatible feature counter.
    public var minor: Int
    /// Backward-compatible fix counter.
    public var patch: Int

    /// Creates a version triple.
    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

/// The static declaration every plugin carries: identity, version, the
/// ABI number it was compiled against, and the capabilities it requires
/// or can optionally use. Install is all-or-nothing over `requires`;
/// `optional` entries are filtered to the granted subset.
public struct PluginManifest: Sendable {
    /// The plugin ABI number this framework build installs. A manifest
    /// declaring any other value is rejected with
    /// ``PluginError/abiMismatch(expected:found:)``.
    public static let currentABI: UInt32 = 1

    /// Reverse-DNS plugin identity; must be unique per runtime.
    public var id: PluginID
    /// The plugin's own semantic version.
    public var version: PluginVersion
    /// The plugin ABI number the plugin was written against.
    public var abi: UInt32
    /// Capabilities the plugin cannot function without. Every entry must
    /// be granted or install fails with a typed error naming the first
    /// missing capability; nothing is partially activated.
    public var requires: [Capability]
    /// Capabilities the plugin can use when present. The granted subset
    /// determines which handles its ``PluginContext`` exposes.
    public var optional: [Capability]

    /// Creates a manifest. `abi` defaults to ``currentABI``.
    public init(
        id: PluginID,
        version: PluginVersion,
        abi: UInt32 = PluginManifest.currentABI,
        requires: [Capability] = [],
        optional: [Capability] = []
    ) {
        self.id = id
        self.version = version
        self.abi = abi
        self.requires = requires
        self.optional = optional
    }
}
