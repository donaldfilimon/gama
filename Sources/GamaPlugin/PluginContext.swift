//  PluginContext.swift — GamaPlugin
//  Everything a plugin may touch arrives through this value at
//  activation; nothing is fetched from a global. The handle types have
//  internal initializers, so they are unforgeable outside this module:
//  the only way to hold a LogAccess is to have been granted `.log`.

import GamaCore

/// Unforgeable handle for the granted ``Capability/log`` capability.
public struct LogAccess: Sendable {
    private let plugin: PluginID
    private let sink: @Sendable (PluginID, String) -> Void

    /// Internal on purpose: handles exist only through a granted install.
    init(plugin: PluginID, sink: @escaping @Sendable (PluginID, String) -> Void) {
        self.plugin = plugin
        self.sink = sink
    }

    /// Writes one line to the host's log sink, tagged with the owning
    /// plugin's identity.
    public func log(_ message: String) {
        sink(plugin, message)
    }
}

/// Unforgeable handle for the granted ``Capability/clock`` capability.
public struct ClockAccess: Sendable {
    private let read: @Sendable () -> UInt64

    /// Internal on purpose: handles exist only through a granted install.
    init(read: @escaping @Sendable () -> UInt64) {
        self.read = read
    }

    /// The host's monotonic clock, in milliseconds from a host-defined
    /// epoch.
    public func nowMillis() -> UInt64 {
        read()
    }
}

/// Unforgeable handle for granted ``Capability/filesystem(_:)`` scopes.
/// Every operation checks the path against the granted scopes with the
/// lexical containment rules of ``FilesystemScope`` before reaching the
/// host's provider, which checks again.
public struct FilesystemAccess: Sendable {
    private let scopes: [FilesystemScope]
    private let provider: FilesystemProvider

    /// Internal on purpose: handles exist only through a granted install.
    init(scopes: [FilesystemScope], provider: FilesystemProvider) {
        self.scopes = scopes
        self.provider = provider
    }

    /// The granted scopes, in grant-declaration order, for inspection.
    public var grantedScopes: [FilesystemScope] { scopes }

    /// Reads the file at `path` through the first granted scope that
    /// permits reading it.
    /// - Throws: ``PluginError/accessDenied(path:)`` when no granted
    ///   scope contains the path, or ``PluginError/ioFailure(path:)``
    ///   from the provider.
    public func read(path: String) throws(PluginError) -> [UInt8] {
        guard let scope = scopes.first(where: { $0.permitsRead(path) }) else {
            throw .accessDenied(path: path)
        }
        return try provider.read(path, scope)
    }

    /// Writes `bytes` to `path` through the first granted read-write
    /// scope that permits writing it.
    /// - Throws: ``PluginError/accessDenied(path:)`` when no granted
    ///   scope permits the write, or ``PluginError/ioFailure(path:)``
    ///   from the provider.
    public func write(_ bytes: [UInt8], path: String) throws(PluginError) {
        guard let scope = scopes.first(where: { $0.permitsWrite(path) }) else {
            throw .accessDenied(path: path)
        }
        try provider.write(bytes, path, scope)
    }
}

/// The complete authority one plugin holds, handed to it once at
/// activation. Handles are `nil` unless the matching capability was
/// granted (required capabilities are always non-nil after a successful
/// install; optional ones are filtered to the granted, service-backed
/// subset).
public struct PluginContext: Sendable {
    /// The identity this context was issued to.
    public let plugin: PluginID
    /// Log handle, or `nil` when ``Capability/log`` was not granted.
    public let log: LogAccess?
    /// Clock handle, or `nil` when ``Capability/clock`` was not granted.
    public let clock: ClockAccess?
    /// Filesystem handle covering every granted scope, or `nil` when no
    /// ``Capability/filesystem(_:)`` scope was granted.
    public let filesystem: FilesystemAccess?
    /// Host invalidation and signal observation, bounded by the owning
    /// host's lifetime. A plugin `Signal` observed here dirties exactly
    /// the one host this runtime was built with.
    public let subscriptions: SubscriptionContext

    /// Internal on purpose: contexts are issued by ``PluginRuntime``.
    init(
        plugin: PluginID,
        log: LogAccess?,
        clock: ClockAccess?,
        filesystem: FilesystemAccess?,
        subscriptions: SubscriptionContext
    ) {
        self.plugin = plugin
        self.log = log
        self.clock = clock
        self.filesystem = filesystem
        self.subscriptions = subscriptions
    }

    /// Marks the owning host dirty: the explicit out-of-band path for
    /// changes no observed signal carries.
    public func invalidate() {
        subscriptions.invalidate()
    }
}
