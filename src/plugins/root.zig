/// Lexical filesystem prefix with separate read/write permissions; not an OS sandbox.
pub const Scope = @import("capability.zig").Scope;
/// Cooperative log, clock or scoped-filesystem authority.
pub const Capability = @import("capability.zig").Capability;
/// Borrowed plugin ID and allowed capabilities, copied by runtime creation.
pub const Grant = @import("capability.zig").Grant;
/// Borrowed per-plugin grant table; empty denies every capability.
pub const Grants = @import("capability.zig").Grants;
/// Borrowed host callback table; caller keeps userdata alive during runtime use.
pub const Services = @import("handles.zig").Services;
/// Borrowed preflight/notification hooks for marking a host dirty.
pub const Invalidation = @import("handles.zig").Invalidation;
/// Copyable revocable installation handle borrowing runtime-retained lease storage.
pub const Context = @import("handles.zig").Context;
/// Revocable logging handle that rechecks the live installation on every write.
pub const LogAccess = @import("handles.zig").LogAccess;
/// Revocable monotonic-millisecond clock handle.
pub const ClockAccess = @import("handles.zig").ClockAccess;
/// Revocable scoped file access; read results use the caller's allocator.
pub const FilesystemAccess = @import("handles.zig").FilesystemAccess;
/// Revocable command handle; perform validates installation and runtime reentry.
pub const Command = @import("handles.zig").Command;
/// Plugin ID, informational version, ABI and required/optional capabilities.
pub const Manifest = @import("runtime.zig").Manifest;
/// Plugin-local command name/title and callback, bound during installation.
pub const CommandDefinition = @import("runtime.zig").CommandDefinition;
/// Auxiliary scene contribution with borrowed name/title and rendering callback.
pub const SceneDefinition = @import("runtime.zig").SceneDefinition;
/// Revocable installed auxiliary scene with namespaced ID and retained metadata.
pub const Scene = @import("runtime.zig").Scene;
/// Specialize the heap-owned plugin runtime for its executor guard type.
pub const Implementation = @import("runtime.zig").Implementation;
