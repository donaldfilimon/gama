//! Installed-host pull state. Frame pointer/length refer only to the most recent
//! successful frame call; clean/failed frame clears the exposed borrow. Failed
//! init expires the borrow but preserves the installed host and its publication.
const std = @import("std");
const shared = @import("context.zig");
/// Caller-owned pull wrapper managing a Context pointer and rejecting callback reentry.
pub const Pull = struct {
    /// Owned installed Context pointer; init replaces it transactionally and shutdown destroys it.
    context: ?*shared.Context = null,

    /// Output borrowed from the last successful frame; cleared by frame/init/shutdown.
    bytes: []const u8 = &.{},

    /// After owner preflight, expire output and transactionally replace the context; allocation failure retains the old host. Retain allocator until shutdown.
    pub fn init(self: *Pull, a: std.mem.Allocator, columns: i32, rows: i32) i32 {
        if (self.context) |old| {
            old.host.checkExecutor() catch |e| return shared.status(e);
            if (old.busy) return -1;
        }
        self.bytes = &.{};
        const next = shared.Context.create(a, columns, rows) catch |e| return shared.status(e);
        if (self.context) |old| old.destroy() catch |e| {
            next.destroy() catch unreachable;
            return shared.status(e);
        };
        self.context = next;
        return 0;
    }

    /// Destroy the context and clear output after successful owner preflight; on error leave both unchanged.
    pub fn shutdown(self: *Pull) void {
        if (self.context) |ctx| ctx.destroy() catch return;
        self.context = null;
        self.bytes = &.{};
    }

    /// After successful owner preflight, expire the previous borrow and attempt one frame.
    /// Return 1 with borrowed bytes, 0 when clean, or a negative status with an empty exposed slice.
    /// A preflight failure returns its negative status before changing the previous borrow.
    pub fn frame(self: *Pull) i32 {
        if (self.context) |ctx| {
            ctx.host.checkExecutor() catch |e| return shared.status(e);
            if (ctx.busy) return -1;
        }
        self.bytes = &.{};
        const ctx = self.context orelse return -1;
        self.bytes = (ctx.frame(false) catch |e| return shared.status(e)) orelse return 0;
        return 1;
    }

    /// Validate and dispatch a semantic ABI key to the installed context.
    pub fn key(self: *Pull, code: i32, scalar: i32, shift: i32, control: i32) i32 {
        const ctx = self.context orelse return -1;
        ctx.key(code, scalar, shift, control) catch |e| return shared.status(e);
        return 0;
    }

    /// Forward signed cell coordinates as a press when pressed is nonzero, otherwise release.
    /// Return 0 or a mapped negative status; -1 means no installed context or owner failure.
    pub fn pointer(self: *Pull, column: i32, row: i32, pressed: i32) i32 {
        const ctx = self.context orelse return -1;
        ctx.pointer(column, row, pressed) catch |e| return shared.status(e);
        return 0;
    }

    /// Forward clamped dimensions to the installed context without replacing the output borrow.
    /// Return 0 on success, -1 without a context, or a mapped error; frame performs drawing admission.
    pub fn resize(self: *Pull, columns: i32, rows: i32) i32 {
        const ctx = self.context orelse return -1;
        ctx.resize(columns, rows) catch |e| return shared.status(e);
        return 0;
    }

    /// Return 1 when dirty, 0 when clean, or a mapped negative status for missing context/owner errors.
    pub fn needsFrame(self: *Pull) i32 {
        const ctx = self.context orelse return -1;
        return @intFromBool(ctx.needsFrame() catch |e| return shared.status(e));
    }
};
