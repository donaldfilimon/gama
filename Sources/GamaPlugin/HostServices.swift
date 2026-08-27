//  HostServices.swift — GamaPlugin
//  Capability interfaces stay in this stdlib-only target; implementations
//  are supplied by whoever owns the host: the application itself, or the
//  platform-conditional GamaPlatformServices target. A platform that
//  cannot provide a service simply does not, and the corresponding
//  required grants fail closed at install.

/// The filesystem implementation behind granted
/// ``Capability/filesystem(_:)`` handles. A provider receives the path
/// and the granted scope on every call and must itself refuse paths the
/// scope does not contain (defense in depth on top of the checks
/// ``FilesystemAccess`` already performs).
public struct FilesystemProvider: Sendable {
    /// Reads the file at `path` under `scope`; throws
    /// ``PluginError/accessDenied(path:)`` for uncontained paths and
    /// ``PluginError/ioFailure(path:)`` for platform I/O errors.
    public var read: @Sendable (_ path: String, _ scope: FilesystemScope)
        throws(PluginError) -> [UInt8]
    /// Writes `bytes` to `path` under `scope`; throws
    /// ``PluginError/accessDenied(path:)`` for uncontained or read-only
    /// paths and ``PluginError/ioFailure(path:)`` for platform I/O errors.
    public var write: @Sendable (_ bytes: [UInt8], _ path: String, _ scope: FilesystemScope)
        throws(PluginError) -> Void

    /// Creates a provider from its two operations.
    public init(
        read: @escaping @Sendable (_ path: String, _ scope: FilesystemScope)
            throws(PluginError) -> [UInt8],
        write: @escaping @Sendable (_ bytes: [UInt8], _ path: String, _ scope: FilesystemScope)
            throws(PluginError) -> Void
    ) {
        self.read = read
        self.write = write
    }
}

/// The service implementations one ``PluginRuntime`` mediates. Every
/// field is optional: a `nil` service makes the matching capability
/// unavailable, which fails required grants closed at install and leaves
/// optional handles `nil`.
public struct HostServices: Sendable {
    /// Receives one log line per call, tagged with the writing plugin.
    public var log: (@Sendable (PluginID, String) -> Void)?
    /// Returns monotonic milliseconds; the epoch is host-defined.
    public var clock: (@Sendable () -> UInt64)?
    /// Filesystem operations behind granted filesystem scopes.
    public var filesystem: FilesystemProvider?

    /// Creates a service set; each omitted service disables its
    /// capability. The initializer is public because the application is
    /// the host.
    public init(
        log: (@Sendable (PluginID, String) -> Void)? = nil,
        clock: (@Sendable () -> UInt64)? = nil,
        filesystem: FilesystemProvider? = nil
    ) {
        self.log = log
        self.clock = clock
        self.filesystem = filesystem
    }

    /// True when a backing service exists for `capability`.
    func supports(_ capability: Capability) -> Bool {
        switch capability {
        case .log: return log != nil
        case .clock: return clock != nil
        case .filesystem: return filesystem != nil
        }
    }
}
