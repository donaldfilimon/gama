//! Adaptive runtime policy over the shared host and transactional drawing engine.
//! Returned completion borrows Host; no process exit is performed. Quiescent plain
//! fallback is distinct from an application-declared result. Completion does not
//! keep an inputless clean loop alive awaiting future asynchronous work.
const std = @import("std");
const Error = @import("../core/state.zig").Error;
const geo = @import("../core/geometry.zig");
const host_module = @import("../core/host.zig");
const root = @import("root.zig");
const Guard = @import("../services/native_guard.zig").NativeGuard;
/// Run-loop completion and whether the application explicitly declared that result.
pub const Result = struct {
    /// Application status or quiescent fallback; process exit remains caller-owned.
    completion: host_module.Completion,
    /// True only when the application explicitly set completion.
    declared: bool,
};
/// Run the shared host loop over a checked surface and return completion to the caller.
pub fn run(host: anytype, surface: anytype) Error!Result {
    try host.checkExecutor();
    try surface.begin();
    const result = runBody(host, surface) catch |err| {
        host.handle(.{ .lifecycle = .{ .kind = .will_terminate } }) catch {};
        surface.end() catch {};
        return err;
    };
    const lifecycle_result = host.handle(.{ .lifecycle = .{ .kind = .will_terminate } });
    const end_result = surface.end();
    try lifecycle_result;
    try end_result;
    return result;
}
fn runBody(host: anytype, surface: anytype) Error!Result {
    const Host = @typeInfo(@TypeOf(host)).pointer.child;
    const Adapter = @typeInfo(@TypeOf(surface)).pointer.child;
    const Pump = @import("../core/pump.zig").Implementation(Host);
    const Drawing = @import("../draw/pump.zig").Implementation(Host, Pump);
    var drawing = try Drawing.init(host.allocator, host, if (surface.waitsForInput()) .ansi else .plain);
    defer drawing.deinit();
    try host.handle(.{ .lifecycle = .{ .kind = .did_launch } });
    try host.handle(.{ .resize = try surface.extent() });
    while (!(try host.wantsQuit())) {
        const size = try surface.extent();
        if (!std.meta.eql(size, try host.currentSize())) try host.handle(.{ .resize = size });
        const lines = try host.pendingLines();
        const count = lines.len;
        const outcome = try drawing.advanceDelivered(surface, Adapter.write, lines);
        if (outcome.produced) try host.consumeLines(count);
        if (try host.completionStatus()) |completion| return .{ .completion = completion, .declared = true };
        if (!surface.waitsForInput() and !outcome.produced) break;
        if (try surface.next(if (outcome.follow_up) 0 else 250)) |event| try host.handle(event);
    }
    return .{ .completion = (try host.completionStatus()) orelse .success(), .declared = (try host.completionStatus()) != null };
}
/// Caller-owned Io backend outlives this surface. Move into stable storage before
/// begin; end is idempotent. Plain mode never instantiates POSIX on Windows.
pub const Surface = struct {
    /// Borrowed standard-library I/O backend; it must outlive all operations.
    io: std.Io,

    /// Executor/reentrancy guard; callers must use checked methods instead of changing it.
    guard: Guard,

    /// Chosen plain or interactive strategy; set before begin.
    mode: root.Mode,

    /// Borrowed output file handle; caller retains it through end and all writes.
    output: std.Io.File,

    /// Input stream owned or borrowed according to the adapter constructor.
    input: std.Io.File,

    /// Owned acquired terminal when interactive; absent in plain mode and unavailable on Windows.
    terminal: if (@import("builtin").os.tag == .windows) void else ?root.Terminal = if (@import("builtin").os.tag == .windows) {} else null,

    /// Caller-owned exact installed-action records; Darwin custom handlers require these.
    dispositions: if (@import("builtin").os.tag == .windows) void else []const root.Terminal.Disposition = if (@import("builtin").os.tag == .windows) {} else &.{},

    /// Whether begin completed and end is required; maintained by the surface lifecycle.
    begun: bool = false,

    /// Borrow io and standard input/output handles, capture thread affinity; begin acquires terminal state.
    pub fn init(io: std.Io, mode: root.Mode) Surface {
        return .{ .io = io, .guard = .init(), .mode = mode, .output = .stdout(), .input = .stdin() };
    }

    /// Select terminal/plain mode from stdout capability and explicit arguments.
    pub fn adaptive(io: std.Io, args: []const []const u8) Surface {
        const tty = if (@import("builtin").os.tag == .windows) false else @import("terminal.zig").stdoutIsTerminal();
        return init(io, root.select(tty, args));
    }

    /// Report whether the surface is interactive rather than quiescent plain output.
    pub fn waitsForInput(self: *const Surface) bool {
        return self.mode == .interactive;
    }

    /// Begin once until end; interactive mode acquires a terminal and hides the cursor, plain mode does no I/O.
    /// Executor validation and acquisition/output errors propagate; repeated begin is idempotent.
    pub fn begin(self: *Surface) Error!void {
        try self.guard.check();
        if (self.begun) return;
        if (self.mode == .interactive) {
            if (@import("builtin").os.tag == .windows) return error.Unavailable else {
                self.terminal = try root.Terminal.acquireWithActions(self.io, self.input.handle, self.output.handle, self.dispositions);
                self.terminal.?.write("\x1b[?25l") catch |err| {
                    self.terminal.?.close() catch {};
                    self.terminal = null;
                    return err;
                };
            }
        }
        self.begun = true;
    }

    /// Close the active surface and restore terminal state; repeated end is idempotent.
    pub fn end(self: *Surface) Error!void {
        try self.guard.check();
        if (!self.begun) return;
        defer self.begun = false;
        if (@import("builtin").os.tag != .windows) if (self.terminal) |*terminal| {
            defer self.terminal = null;
            try terminal.close();
        };
    }

    /// Query the current surface cell extent, using the plain default when no terminal is owned.
    pub fn extent(self: *Surface) Error!geo.Size {
        try self.guard.check();
        if (@import("builtin").os.tag != .windows) if (self.terminal) |*terminal| return terminal.size();
        return root.default_size;
    }

    /// Read one semantic event with a millisecond timeout; plain mode returns null immediately.
    pub fn next(self: *Surface, timeout: i32) Error!?host_module.Event {
        try self.guard.check();
        if (@import("builtin").os.tag != .windows) if (self.terminal) |*terminal| return terminal.next(timeout);
        return null;
    }

    /// Write all bytes to the selected output; external partial writes cannot be rolled back.
    pub fn write(self: *Surface, bytes: []const u8) Error!void {
        try self.guard.check();
        if (!self.begun) return error.InvalidHandle;
        if (@import("builtin").os.tag != .windows) if (self.terminal) |*terminal| return terminal.write(bytes);
        var writer = self.output.writer(self.io, &.{});
        writer.interface.writeAll(bytes) catch return error.IOFailure;
    }
};
/// Standard-stream convenience. The caller owns the Host and chooses whether to
/// turn the returned status into a process exit. Declared messages go to stderr.
pub fn runAdaptive(host: anytype, io: std.Io, args: []const []const u8) Error!Result {
    var surface = Surface.adaptive(io, args);
    const result = try run(host, &surface);
    if (result.completion.message) |message| {
        var writer = std.Io.File.stderr().writer(io, &.{});
        writer.interface.writeAll(message) catch return error.IOFailure;
        writer.interface.writeAll("\n") catch return error.IOFailure;
    }
    return result;
}
