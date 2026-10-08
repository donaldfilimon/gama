//! Optional std.Io adapter. Stable adapter and borrowed Io backend outlive every callback.
//! Bounded bytes, synchronous direct writes (may truncate/partially write on failure).
//! Lexical path containment only: follows symlinks, no atomicity, durability or sandbox.
const std = @import("std");
const p = @import("../plugins/root.zig");
const Error = @import("../core/state.zig").Error;
const Guard = @import("native_guard.zig").NativeGuard;
/// Executor-confined std.Io service adapter; keep its address stable after obtaining callbacks.
pub const HostedServices = struct {
    /// Borrowed standard-library I/O backend; it must outlive all operations.
    io: std.Io,

    /// Executor/reentrancy guard; callers must use checked methods instead of changing it.
    guard: Guard,

    /// Reentry guard around synchronous service callbacks; do not mutate while borrowed.
    busy: bool = false,

    /// Per-operation byte bounds validated at initialization.
    limits: Limits,

    /// Whether the awake clock reported a positive resolution at initialization.
    clock_available: bool,

    /// Caller-selected byte limits; initialization rejects any value above 64 MiB.
    pub const Limits = struct {
        /// Read limit supplied to bounded file allocation; overlong input reports LimitExceeded.
        read_bytes: usize = 16 * 1024 * 1024,
        /// Maximum write payload length in bytes.
        write_bytes: usize = 16 * 1024 * 1024,
        /// Maximum combined plugin-ID and log-message byte length.
        log_bytes: usize = 64 * 1024,
        /// Maximum path byte length after scope authorization.
        path_bytes: usize = 4096,
    };
    /// Finite bounds cannot exceed 64 MiB. Read bound is inclusive, including zero.
    pub fn init(io: std.Io, limits: Limits) Error!HostedServices {
        if (limits.read_bytes > 64 * 1024 * 1024 or limits.write_bytes > 64 * 1024 * 1024 or limits.log_bytes > 64 * 1024 * 1024 or limits.path_bytes > 64 * 1024 * 1024) return error.InvalidLimit;
        const resolution = std.Io.Clock.awake.resolution(io) catch null;
        return .{ .io = io, .guard = Guard.init(), .limits = limits, .clock_available = if (resolution) |r| r.nanoseconds > 0 else false };
    }
    /// Obtain callbacks only after this adapter reaches its final stable address.
    pub fn services(self: *HostedServices) Error!p.Services {
        try self.guard.check();
        return .{ .userdata = self, .log = log, .clock = if (self.clock_available) clock else null, .read = read, .write = write };
    }
    fn enter(self: *HostedServices) Error!void {
        try self.guard.check();
        if (self.busy) return error.Reentrant;
        self.busy = true;
    }
    fn owner(raw: ?*anyopaque) *HostedServices {
        return @ptrCast(@alignCast(raw.?));
    }
    fn log(raw: ?*anyopaque, id: []const u8, message: []const u8) Error!void {
        const self = owner(raw);
        try self.enter();
        defer self.busy = false;
        if (id.len > self.limits.log_bytes or message.len > self.limits.log_bytes - id.len) return error.LimitExceeded;
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.File.stderr().writerStreaming(self.io, &buffer);
        writer.interface.print("[{s}] {s}\n", .{ id, message }) catch return mapError(writer.err orelse error.WriteFailed);
        writer.flush() catch |err| return mapError(err);
    }

    /// Convert nanoseconds to truncated whole milliseconds without I/O; reject negative or u64-overflow results.
    pub fn timestampMillis(nanoseconds: i96) Error!u64 {
        if (nanoseconds < 0) return error.InvalidClock;
        const millis = @divTrunc(nanoseconds, 1_000_000);
        if (millis > std.math.maxInt(u64)) return error.InvalidClock;
        return @intCast(millis);
    }
    fn clock(raw: ?*anyopaque) Error!u64 {
        const self = owner(raw);
        try self.enter();
        defer self.busy = false;
        if (!self.clock_available) return error.ServiceUnavailable;
        return timestampMillis(std.Io.Clock.awake.now(self.io).nanoseconds);
    }
    fn pathCheck(self: *HostedServices, path: []const u8, scope: p.Scope, writing: bool) Error!void {
        if (!scope.permits(path, writing)) return error.AccessDenied;
        if (path.len > self.limits.path_bytes) return error.LimitExceeded;
    }
    fn read(raw: ?*anyopaque, a: std.mem.Allocator, path: []const u8, scope: p.Scope) Error![]u8 {
        const self = owner(raw);
        try self.enter();
        defer self.busy = false;
        try self.pathCheck(path, scope, false);
        // This snapshot rejects length == limit. +1 preserves inclusive advertised bound.
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, a, .limited(self.limits.read_bytes + 1)) catch |err| return mapError(err);
    }
    fn write(raw: ?*anyopaque, path: []const u8, bytes: []const u8, scope: p.Scope) Error!void {
        const self = owner(raw);
        try self.enter();
        defer self.busy = false;
        try self.pathCheck(path, scope, true);
        if (bytes.len > self.limits.write_bytes) return error.LimitExceeded;
        std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = bytes }) catch |err| return mapError(err);
    }
    fn mapError(err: anyerror) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Canceled => error.Canceled,
            error.StreamTooLong => error.LimitExceeded,
            else => error.IOFailure,
        };
    }
};
