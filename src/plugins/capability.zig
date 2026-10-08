//! Exact grants and lexical containment, deliberately not a symlink/process sandbox.
const std = @import("std");
/// Lexical path-prefix scope with separate read/write permissions; not an OS sandbox.
pub const Scope = struct {
    /// Exact lexical filesystem scope prefix; no implicit wildcard grant.
    prefix: []const u8,

    /// Whether the filesystem grant permits writes as well as reads.
    writable: bool = false,

    /// Test exact capability/scope permission without treating prefixes as unrestricted authority.
    pub fn permits(self: Scope, path: []const u8, write: bool) bool {
        if (write and !self.writable) return false;
        if (!safe(self.prefix) or !safe(path)) return false;
        const prefix = if (self.prefix.len > 1 and self.prefix[self.prefix.len - 1] == '/') self.prefix[0 .. self.prefix.len - 1] else self.prefix;
        return std.mem.eql(u8, prefix, path) or std.mem.eql(u8, prefix, "/") or (std.mem.startsWith(u8, path, prefix) and path.len > prefix.len and path[prefix.len] == '/');
    }
    fn safe(path: []const u8) bool {
        if (path.len == 0 or path[0] != '/') return false;
        var iter = std.mem.splitScalar(u8, path[1..], '/');
        while (iter.next()) |part| {
            if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
            if (part.len == 0 and iter.index != null) return false;
        }
        return true;
    }
};
/// Cooperative host authority requested or granted to a plugin.
pub const Capability = union(enum) {
    /// Permission to submit messages to the host log callback.
    log,

    /// Permission to read the host monotonic clock.
    clock,

    /// Permission to access paths admitted by the lexical filesystem scope.
    filesystem: Scope,

    /// Compare the semantic contents without transferring ownership.
    pub fn eql(a: Capability, b: Capability) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .log, .clock => true,
            .filesystem => |s| s.writable == b.filesystem.writable and std.mem.eql(u8, s.prefix, b.filesystem.prefix),
        };
    }
};
/// Capability grants for one exact plugin ID; slices are borrowed by this value.
pub const Grant = struct {
    /// Exact plugin ID to which capabilities apply; no wildcard matching.
    id: []const u8,
    /// Allowed capabilities for this plugin; runtime creation copies them.
    capabilities: []const Capability,
};
/// Borrowed grant table queried by exact plugin ID and capability coverage.
pub const Grants = struct {
    /// Borrowed per-plugin entries; empty denies all capabilities.
    entries: []const Grant = &.{},

    /// Test exact capability/scope permission without treating prefixes as unrestricted authority.
    pub fn permits(self: Grants, id: []const u8, cap: Capability) bool {
        for (self.entries) |entry| if (std.mem.eql(u8, entry.id, id)) {
            for (entry.capabilities) |value| if (value.eql(cap)) return true;
        };
        return false;
    }
};
