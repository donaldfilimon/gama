//  Capability.swift — GamaPlugin
//  The capability vocabulary and the grant table. V1 matching is
//  exact-match only: a grant satisfies a request when the two Capability
//  values are equal. Scope subsumption (a grant for "/a" satisfying a
//  request for "/a/b") is deliberately not implemented; its path
//  normalization traps are a post-V1 design item.

/// One host-mediated authority a plugin can request. The enum is closed
/// on purpose for V1: adding a capability is a framework decision with a
/// review, not a plugin-author string.
public enum Capability: Hashable, Sendable {
    /// Host-mediated logging.
    case log
    /// Monotonic time from the host.
    case clock
    /// Scoped filesystem access; never ambient.
    case filesystem(FilesystemScope)
}

/// A path-prefix-scoped filesystem authority. Scopes are matched
/// exactly at grant time; path containment inside a scope is checked
/// lexically by ``permitsRead(_:)`` and ``permitsWrite(_:)``.
public enum FilesystemScope: Hashable, Sendable {
    /// Read-only access beneath `pathPrefix`.
    case read(pathPrefix: String)
    /// Read and write access beneath `pathPrefix`.
    case readWrite(pathPrefix: String)

    /// The absolute path prefix this scope covers.
    public var pathPrefix: String {
        switch self {
        case .read(let prefix), .readWrite(let prefix):
            return prefix
        }
    }

    /// True when this scope permits reading `path`.
    ///
    /// Containment is lexical prefix containment on absolute paths, with
    /// no symlink resolution (a documented V1 limitation): the prefix and
    /// the path must both be absolute, neither may contain `.` or `..`
    /// components, an empty prefix denies everything (fail closed), and
    /// the prefix must match at a path-component boundary, so a prefix of
    /// `/a` never covers `/ab`.
    public func permitsRead(_ path: String) -> Bool {
        FilesystemScope.contains(prefix: pathPrefix, path: path)
    }

    /// True when this scope permits writing `path`. Only
    /// ``readWrite(pathPrefix:)`` scopes can permit writes; containment
    /// follows the same lexical rules as ``permitsRead(_:)``.
    public func permitsWrite(_ path: String) -> Bool {
        guard case .readWrite = self else { return false }
        return FilesystemScope.contains(prefix: pathPrefix, path: path)
    }

    /// Lexical prefix containment shared by both permission checks and by
    /// platform filesystem providers (defense in depth).
    static func contains(prefix: String, path: String) -> Bool {
        guard !prefix.isEmpty, !path.isEmpty else { return false }
        guard prefix.hasPrefix("/"), path.hasPrefix("/") else { return false }
        guard hasSafeComponents(prefix), hasSafeComponents(path) else { return false }
        var normalizedPrefix = prefix
        while normalizedPrefix.count > 1, normalizedPrefix.hasSuffix("/") {
            normalizedPrefix.removeLast()
        }
        if path == normalizedPrefix { return true }
        if normalizedPrefix == "/" { return true }
        return path.hasPrefix(normalizedPrefix + "/")
    }

    /// Rejects any path containing empty, `.`, or `..` components after
    /// the leading separator, so lexical containment cannot be escaped.
    private static func hasSafeComponents(_ path: String) -> Bool {
        let components = path.dropFirst().split(
            separator: "/", omittingEmptySubsequences: false)
        for (index, component) in components.enumerated() {
            if component.isEmpty && index != components.count - 1 { return false }
            if component == "." || component == ".." { return false }
        }
        return true
    }
}

/// The deny-by-default grant table an application hands its
/// ``PluginRuntime``. Grants are data, not a callback: inspectable,
/// testable, and serializable by an app shell later.
public struct CapabilityGrants: Sendable {
    /// The empty table: every permission check fails.
    public static let denyAll = CapabilityGrants()

    /// Granted capabilities per plugin identity.
    public var table: [PluginID: Set<Capability>]

    /// Creates a grant table; the default is empty (deny everything).
    public init(table: [PluginID: Set<Capability>] = [:]) {
        self.table = table
    }

    /// True when `capability` is granted to `id`. Matching is exact:
    /// a grant of `.filesystem(.read(pathPrefix: "/a"))` does not satisfy
    /// a request for `.filesystem(.read(pathPrefix: "/a/b"))`.
    public func permits(_ id: PluginID, _ capability: Capability) -> Bool {
        table[id]?.contains(capability) ?? false
    }
}
