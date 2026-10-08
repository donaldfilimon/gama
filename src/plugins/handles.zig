//! Every handle borrows its runtime, which must outlive all handle/frame invocation.
//! Inert frame storage may be released after runtime teardown; its cleanup never reads leases.
//! Installation leases remain as tombstones until runtime destruction. No authority revives.
const std = @import("std");
const s = @import("../core/state.zig");
const c = @import("../core/context.zig");
const signal_module = @import("../core/signal.zig");
const cap = @import("capability.zig");
/// Shared state/service/lifecycle error set used by revocable plugin handles.
pub const Error = s.Error;
/// Borrowed host-service callbacks; runtime copies the table but does not own userdata.
pub const Services = struct {
    /// Caller-owned callback payload; keep its address stable throughout callback use.
    userdata: ?*anyopaque = null,

    /// Log a plugin ID and message; callback borrows both slices for the call.
    log: ?*const fn (?*anyopaque, []const u8, []const u8) Error!void = null,

    /// Read monotonic milliseconds; null means no clock service is available.
    clock: ?*const fn (?*anyopaque) Error!u64 = null,

    /// Read within the supplied scope and return bytes owned by the caller's allocator.
    read: ?*const fn (?*anyopaque, std.mem.Allocator, []const u8, cap.Scope) Error![]u8 = null,

    /// Write borrowed bytes to a scoped path; callback retains neither slice.
    write: ?*const fn (?*anyopaque, []const u8, []const u8, cap.Scope) Error!void = null,

    /// Report callback availability; filesystem requires both read and write. Does not check grants.
    pub fn available(self: Services, capability: cap.Capability) bool {
        return switch (capability) {
            .log => self.log != null,
            .clock => self.clock != null,
            .filesystem => self.read != null and self.write != null,
        };
    }
};
/// Stable application-owned target; notify may run while a host prepares or handles input.
pub const Invalidation = struct {
    /// Caller-owned callback payload; keep its address stable throughout callback use.
    userdata: ?*anyopaque = null,

    /// Notify the rendering host after successful invalidation preflight.
    notify: ?*const fn (?*anyopaque) void = null,

    /// Optional executor/availability check before calling notify.
    check: ?*const fn (?*anyopaque) Error!void = null,

    /// Invoke the optional preflight callback, propagating its error; no check means success.
    pub fn preflight(self: Invalidation) Error!void {
        if (self.check) |f| try f(self.userdata);
    }

    /// Invoke the optional notification directly; the caller must first complete preflight.
    pub fn call(self: Invalidation) void {
        if (self.notify) |f| f(self.userdata);
    }

    /// Borrow a stable host as an invalidation target; it must outlive all callback use.
    /// Preflight checks its executor before notification calls notifyInvalidation.
    pub fn host(value: anytype) Invalidation {
        return .{ .userdata = value, .notify = struct {
            fn call(raw: ?*anyopaque) void {
                @as(@TypeOf(value), @ptrCast(@alignCast(raw.?))).notifyInvalidation() catch unreachable;
            }
        }.call, .check = struct {
            fn check(raw: ?*anyopaque) Error!void {
                try @as(@TypeOf(value), @ptrCast(@alignCast(raw.?))).checkExecutor();
            }
        }.check };
    }
};
const Observation = struct {
    /// Borrowed signal owner; detached callback marks the record when that owner disappears.
    source: *anyopaque,

    /// Owner-issued binding token; use the issuing owner and preserve its generation.
    token: signal_module.Token,

    /// Whether the observer is still attached to its signal owner.
    attached: bool = true,

    /// Owner-maintained liveness flag; callers must use validation methods.
    active: bool = true,

    /// Cancel the recorded signal token after preflight succeeds.
    cancel: *const fn (*anyopaque, signal_module.Token) Error!void,

    /// Check whether the observer can detach without violating snapshot delivery.
    check: *const fn (*anyopaque, signal_module.Token) Error!void,

    /// Check whether the source currently permits cancellation work.
    can_cancel: *const fn (*anyopaque) Error!void,
};
/// Internal lease storage. Public APIs issue handles; direct field forgery is unsupported cooperative code.
pub const Lease = struct {
    /// Runtime allocator owning observation records; retain until runtime destruction.
    allocator: std.mem.Allocator,

    /// Borrowed runtime confinement guard; all live handles check it.
    executor: s.Executor,

    /// Installed plugin ID backed by the retained entry arena.
    id: []const u8,

    /// Owner-maintained liveness flag; callers must use validation methods.
    active: bool = true,

    /// Owner-managed guard while observation/invalidation state is being changed.
    editing: bool = false,

    /// Owner-managed guard while a host-service callback is active.
    servicing: bool = false,

    /// Owner-managed guard while withPlugin lends the mutable plugin payload.
    borrowing_payload: bool = false,

    /// Borrowed installed payload; cleared on revocation before payload destruction.
    payload: ?*anyopaque = null,

    /// Static type name used to validate withPlugin's requested payload type.
    payload_type: []const u8 = "",

    /// Borrowed host-service table copied from the runtime at installation.
    services: Services,

    /// Borrowed host invalidation callbacks copied at installation.
    invalidation: Invalidation,

    /// Installed required and granted optional capabilities, backed by the entry arena.
    capabilities: []const cap.Capability,

    /// Owned signal observation records; cancel through Context, not direct mutation.
    observations: std.ArrayList(Observation) = .empty,

    /// Borrowed owning runtime used for enter/leave callbacks.
    runtime: *anyopaque,

    /// Enter the runtime's checked non-reentrant operation scope.
    enter: *const fn (*anyopaque) Error!void,

    /// Leave a previously entered runtime operation scope.
    leave: *const fn (*anyopaque) void,

    /// Check executor and active installation; caller must keep the runtime/lease storage alive.
    pub fn check(self: *Lease) Error!void {
        try self.executor.check();
        if (!self.active) return error.InvalidHandle;
    }

    /// Validate detachment before changing an observation's ownership.
    pub fn detachCheck(self: *Lease) Error!void {
        for (self.observations.items) |o| if (o.attached) try o.check(o.source, o.token);
    }

    /// Validate cancellation before touching subscription storage.
    pub fn cancelCheck(self: *Lease) Error!void {
        for (self.observations.items) |o| if (o.attached) try o.can_cancel(o.source);
    }

    /// Owner-only cancellation hook; callers must use checked public cancellation.
    pub fn cancelInternal(self: *Lease) void {
        for (self.observations.items) |*o| if (o.active) {
            o.active = false;
            o.cancel(o.source, o.token) catch unreachable;
        };
    }
};
/// Copyable revocable installation handle; runtime storage must outlive every copy.
pub const Context = struct {
    /// Borrowed installation lease; every use must validate it before accessing payloads.
    lease: *Lease,
    /// Synchronously borrow the installed plugin value. The pointer cannot outlive callback.
    /// Type/lease/executor checks precede access, and lifecycle mutation is blocked until return.
    pub fn withPlugin(self: Context, comptime P: type, comptime callback: fn (*P, Context) Error!void) Error!void {
        const l = self.lease;
        try l.check();
        if (!std.mem.eql(u8, l.payload_type, @typeName(P))) return error.InvalidHandle;
        if (l.borrowing_payload or l.servicing or l.editing) return error.Reentrant;
        const payload = l.payload orelse return error.InvalidHandle;
        l.borrowing_payload = true;
        defer l.borrowing_payload = false;
        try callback(@ptrCast(@alignCast(payload)), self);
    }

    /// Borrow the stable live installation identifier.
    pub fn pluginID(self: Context) Error![]const u8 {
        try self.lease.check();
        return self.lease.id;
    }

    /// Mark the associated live host dirty for a subsequent frame.
    pub fn invalidate(self: Context) Error!void {
        const l = self.lease;
        try l.check();
        if (l.editing or l.servicing) return error.Reentrant;
        l.editing = true;
        defer l.editing = false;
        try l.invalidation.preflight();
        l.invalidation.call();
    }

    /// Return checked logging access only when the exact capability was granted.
    pub fn log(self: Context) Error!?LogAccess {
        try self.lease.check();
        for (self.lease.capabilities) |v| if (v == .log) return .{ .context = self };
        return null;
    }

    /// Return a clock handle when the live lease grants it; nowMillis checks provider availability.
    pub fn clock(self: Context) Error!?ClockAccess {
        try self.lease.check();
        for (self.lease.capabilities) |v| if (v == .clock) return .{ .context = self };
        return null;
    }

    /// Return checked filesystem access scoped to the exact granted lexical prefix.
    pub fn filesystem(self: Context) Error!?FilesystemAccess {
        try self.lease.check();
        for (self.lease.capabilities) |v| if (v == .filesystem) return .{ .context = self };
        return null;
    }

    /// Cancel every subscription owned by this live owner.
    pub fn cancelAll(self: Context) Error!void {
        const l = self.lease;
        try l.check();
        if (l.editing) return error.Reentrant;
        l.editing = true;
        defer l.editing = false;
        try l.cancelCheck();
        l.cancelInternal();
    }
    /// Independent per-installation invalidation observation, deduplicated by source.
    pub fn observe(self: Context, source: anytype) Error!void {
        const l = self.lease;
        try l.check();
        if (l.editing) return error.Reentrant;
        l.editing = true;
        defer l.editing = false;
        for (l.observations.items) |o| if (o.active and o.source == @as(*anyopaque, source)) return;
        const Source = @typeInfo(@TypeOf(source)).pointer.child;
        const T = @TypeOf(source.value);
        const Adapter = struct {
            fn notify(raw: *const anyopaque, _: signal_module.SignalRef(T)) Error!void {
                const owner: *Lease = @ptrCast(@alignCast(@constCast(raw)));
                try owner.executor.check();
                if (owner.active) {
                    try owner.invalidation.preflight();
                    owner.invalidation.call();
                }
            }
            fn detached(raw: *const anyopaque, value: *Source, token: signal_module.Token) void {
                const owner: *Lease = @ptrCast(@alignCast(@constCast(raw)));
                for (owner.observations.items) |*o| if (o.source == @as(*anyopaque, value) and o.token.generation == token.generation) {
                    o.active = false;
                    o.attached = false;
                };
            }
            fn check(raw: *anyopaque, token: signal_module.Token) Error!void {
                try @as(*Source, @ptrCast(@alignCast(raw))).canDetachOwner(token);
            }
            fn cancel(raw: *anyopaque, token: signal_module.Token) Error!void {
                try @as(*Source, @ptrCast(@alignCast(raw))).cancel(token);
            }
            fn canCancel(raw: *anyopaque) Error!void {
                try @as(*Source, @ptrCast(@alignCast(raw))).canObserveOwner();
            }
        };
        try source.canObserveOwner();
        try l.observations.ensureUnusedCapacity(l.allocator, 1);
        const token = try source.observeOwnerTracked(l, Adapter.notify, Adapter.detached);
        l.observations.appendAssumeCapacity(.{ .source = source, .token = token, .cancel = Adapter.cancel, .check = Adapter.check, .can_cancel = Adapter.canCancel });
    }
    fn beginService(self: Context) Error!void {
        try self.lease.check();
        if (self.lease.servicing or self.lease.editing) return error.Reentrant;
        self.lease.servicing = true;
    }
    fn endService(self: Context) void {
        self.lease.servicing = false;
    }
};
/// Revocable logging capability; each call rechecks the live lease and grant.
pub const LogAccess = struct {
    /// Revocable lease token; remains borrow-valid only while the runtime exists.
    context: Context,

    /// Validate log authority and call the host logger; external output may be partial on failure.
    pub fn write(self: LogAccess, message: []const u8) Error!void {
        if (try self.context.log() == null) return error.AccessDenied;
        try self.context.beginService();
        defer self.context.endService();
        const l = self.context.lease;
        try (l.services.log orelse return error.Unavailable)(l.services.userdata, l.id, message);
    }
};
/// Revocable monotonic-clock capability returning milliseconds.
pub const ClockAccess = struct {
    /// Revocable lease token checked before accessing the host clock.
    context: Context,

    /// Read provider clock milliseconds through the live installation guard.
    pub fn nowMillis(self: ClockAccess) Error!u64 {
        if (try self.context.clock() == null) return error.AccessDenied;
        try self.context.beginService();
        defer self.context.endService();
        const l = self.context.lease;
        return (l.services.clock orelse return error.Unavailable)(l.services.userdata);
    }
};
/// Revocable filesystem capability; every path is checked against installed scopes.
pub const FilesystemAccess = struct {
    /// Revocable lease token checked before scope and filesystem operations.
    context: Context,
    fn scope(self: FilesystemAccess, path: []const u8, writing: bool) Error!cap.Scope {
        try self.context.lease.check();
        for (self.context.lease.capabilities) |v| if (v == .filesystem and v.filesystem.permits(path, writing)) return v.filesystem;
        return error.AccessDenied;
    }

    /// Authorize the read path against the live lease and granted scope, then call the service.
    /// Return caller-owned bytes to free with a; propagate service errors, including allocation failure.
    pub fn read(self: FilesystemAccess, a: std.mem.Allocator, path: []const u8) Error![]u8 {
        const scope_value = try self.scope(path, false);
        try self.context.beginService();
        defer self.context.endService();
        const l = self.context.lease;
        return (l.services.read orelse return error.Unavailable)(l.services.userdata, a, path, scope_value);
    }

    /// Validate path/write authority, then call the host writer; partial external writes are not rolled back.
    pub fn write(self: FilesystemAccess, path: []const u8, bytes: []const u8) Error!void {
        const scope_value = try self.scope(path, true);
        try self.context.beginService();
        defer self.context.endService();
        const l = self.context.lease;
        try (l.services.write orelse return error.Unavailable)(l.services.userdata, path, bytes, scope_value);
    }
};
/// Snapshot command metadata and callback; borrows the runtime even after uninstall.
pub const Command = struct {
    /// Revocable installation lease checked by perform.
    context: Context,

    /// Namespaced command ID backed by the installation arena.
    id: []const u8,

    /// Command display title borrowed from the installation arena.
    title: []const u8,

    /// Installed command callback; perform supplies the validated context under the runtime guard.
    action: *const fn (Context) Error!void,

    /// Validate the installation and execute the command under the runtime reentry guard.
    pub fn perform(self: Command) Error!void {
        const l = self.context.lease;
        try l.check();
        try l.enter(l.runtime);
        defer l.leave(l.runtime);
        try self.action(self.context);
    }
};
/// Raw actions are frame-owned, this wrapper adds installation revocation to host dispatch.
pub fn wrapAction(ctx: *c.BuildContext, context: Context, action: c.Action) Error!c.Action {
    const Capture = struct {
        /// Installation lease carried into a frame-owned action wrapper.
        context: Context,
        /// Original frame-borrowed action invoked only after lease/reentry validation.
        action: c.Action,
    };
    const capture = try ctx.allocator.create(Capture);
    capture.* = .{ .context = context, .action = action };
    return .{ .capture = capture, .invoke_fn = struct {
        fn invoke(raw: *const anyopaque, host: *anyopaque) Error!void {
            const value: *const Capture = @ptrCast(@alignCast(raw));
            const l = value.context.lease;
            try l.check();
            try l.enter(l.runtime);
            defer l.leave(l.runtime);
            try value.action.invoke(host);
        }
    }.invoke };
}
/// Compare T with the five framework handle types at compile time; does not validate a value or lease.
pub fn canonical(comptime T: type) bool {
    return T == Context or T == Command or T == LogAccess or T == ClockAccess or T == FilesystemAccess;
}
