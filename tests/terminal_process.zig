//! Zig parent holds the slave and observes termios BEFORE teardown. Python only
//! allocates the inherited PTY pair; it never repairs child terminal state.
const std = @import("std");
const fixture = @import("pty_fixture.zig");
const p = std.posix;
fn now(io: std.Io) i64 {
    return @intCast(std.Io.Clock.awake.now(io).toMilliseconds());
}
fn line(fd: p.fd_t, io: std.Io, timeout: i32) !void {
    var buf: [128]u8 = undefined;
    var len: usize = 0;
    const start = now(io);
    while (len < buf.len and now(io) - start < timeout) {
        var fds = [_]p.pollfd{.{ .fd = fd, .events = p.POLL.IN, .revents = 0 }};
        const rc = p.system.poll(&fds, 1, 25);
        if (p.errno(rc) == .INTR) continue;
        if (p.errno(rc) != .SUCCESS) return error.Poll;
        if (rc == 0) continue;
        const n = p.system.read(fd, buf[len..].ptr, 1);
        if (p.errno(n) != .SUCCESS or n == 0) return error.ChildControlEOF;
        if (buf[len] == '\n') {
            const message = buf[0..len];
            if (!std.mem.eql(u8, message, "READY") and !std.mem.eql(u8, message, "BLOCK_NEXT") and !std.mem.eql(u8, message, "RESTORED") and !std.mem.eql(u8, message, "RESIZED") and !std.mem.eql(u8, message, "EOF")) {
                std.debug.print("unexpected control: {s}\n", .{message});
                return error.ChildControl;
            }
            return;
        }
        len += 1;
    }
    return error.ControlTimeout;
}
fn waitBounded(child: *std.process.Child, io: std.Io, timeout: i64) !u32 {
    const start = now(io);
    while (now(io) - start < timeout) {
        var status: c_int = 0;
        const rc = std.c.waitpid(child.id.?, &status, p.W.NOHANG);
        if (rc == child.id.?) {
            child.id = null;
            if (child.stderr) |file| file.close(io);
            child.stderr = null;
            return @bitCast(status);
        }
        if (rc < 0) return error.Wait;
        try std.Io.sleep(io, .fromMilliseconds(5), .awake);
    }
    return error.ChildExitTimeout;
}
fn scenario(io: std.Io, exe: []const u8, mode: []const u8, signal: ?p.SIG) !void {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    const slave: std.Io.File = .{ .handle = pair.slave, .flags = .{ .nonblocking = false } };
    var child = try std.process.spawn(io, .{ .argv = &.{ exe, mode }, .stdin = .{ .file = slave }, .stdout = .{ .file = slave }, .stderr = .pipe });
    defer child.kill(io);
    try line(child.stderr.?.handle, io, 3000);
    if (signal) |sig| {
        if ((try pair.settings()).lflag.ICANON) return error.NotRaw;
        if (std.mem.eql(u8, mode, "blocked")) {
            // No reading from master: prove the child remains blocked before signal.
            var fds = [_]p.pollfd{.{ .fd = child.stderr.?.handle, .events = p.POLL.IN, .revents = 0 }};
            if (p.system.poll(&fds, 1, 150) != 0) return error.ChildWasNotBlocked;
        }
        const start = now(io);
        try p.kill(child.id.?, sig);
        const status = try waitBounded(&child, io, 2000);
        if (!p.W.IFSIGNALED(status) or p.W.TERMSIG(status) != sig) return error.WrongSignalTermination;
        if (!fixture.equal(before, try pair.settings())) return error.NotRestoredBeforeTeardown;
        std.debug.print("PTY {s} {t}: signaled exit/restored before teardown in {d}ms\n", .{ mode, sig, now(io) - start });
    } else {
        if (std.mem.eql(u8, mode, "resize")) {
            // Only dimensions of this owned slave are changed. No restoration wrapper.
            var stty = try std.process.spawn(io, .{ .argv = &.{ "/bin/stty", "-f", std.mem.sliceTo(&pair.name, 0), "rows", "9", "cols", "41" }, .stdin = .ignore, .stdout = .ignore, .stderr = .inherit });
            defer stty.kill(io);
            if (!(try stty.wait(io)).success()) return error.SttyFailed;
            try p.kill(child.id.?, .WINCH);
            try line(child.stderr.?.handle, io, 2000);
        } else if (!std.mem.eql(u8, mode, "normal") and !std.mem.eql(u8, mode, "write-fail") and !std.mem.eql(u8, mode, "plain")) try line(child.stderr.?.handle, io, 2500);
        const status = try waitBounded(&child, io, 2500);
        if (!p.W.IFEXITED(status) or p.W.EXITSTATUS(status) != 0) return error.ChildFailed;
        if (!fixture.equal(before, try pair.settings())) return error.NotRestoredBeforeTeardown;
        if (std.mem.eql(u8, mode, "normal")) {
            var buf: [256]u8 = undefined;
            const n = try p.read(pair.master, &buf);
            if (std.mem.indexOf(u8, buf[0..n], "DELIVERED") == null) return error.NotDelivered;
        }
        if (std.mem.eql(u8, mode, "plain")) {
            var buf: [256]u8 = undefined;
            const n = try p.read(pair.master, &buf);
            if (!std.mem.eql(u8, buf[0..n], "plain result\r\n")) return error.BadPlainBytes;
        }
        std.debug.print("PTY {s}: exited/restored before teardown\n", .{mode});
    }
}
fn eofScenario(io: std.Io, exe: []const u8) !void {
    var pair = try fixture.Pair.open();
    defer pair.close();
    const slave: std.Io.File = .{ .handle = pair.slave, .flags = .{ .nonblocking = false } };
    var child = try std.process.spawn(io, .{ .argv = &.{ exe, "eof" }, .stdin = .{ .file = slave }, .stdout = .{ .file = slave }, .stderr = .pipe });
    defer child.kill(io);
    try line(child.stderr.?.handle, io, 3000);
    const original = try std.fmt.parseInt(p.fd_t, std.mem.span(std.c.getenv("GAMA_TEST_PTY_MASTER").?), 10);
    _ = p.system.close(original);
    _ = p.system.close(pair.master);
    pair.master = -1;
    try line(child.stderr.?.handle, io, 2000);
    const status = try waitBounded(&child, io, 2000);
    if (!p.W.IFEXITED(status) or p.W.EXITSTATUS(status) != 0) return error.ChildFailed;
    std.debug.print("PTY eof: bounded EOF/hangup error and release; master closed so no settings-restoration claim\n", .{});
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for ([_]p.SIG{ .TERM, .HUP, .INT, .QUIT }) |sig| try scenario(init.io, args[1], "signal", sig);
    try scenario(init.io, args[1], "blocked", .TERM);
    for ([_][]const u8{ "normal", "close-full", "error-full", "resize", "write-fail", "plain" }) |mode| try scenario(init.io, args[1], mode, null);
    try eofScenario(init.io, args[1]);
    std.debug.print("All 12 PTY process scenarios passed\n", .{});
}
