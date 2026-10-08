const std = @import("std");
const g = @import("gama");
const p = std.posix;
fn control(bytes: []const u8) void {
    const n = p.system.write(2, bytes.ptr, bytes.len);
    if (p.errno(n) != .SUCCESS or n != bytes.len) std.process.exit(90);
}
fn fill(fd: p.fd_t) !void {
    const bytes: [4096]u8 = @splat('x');
    var total: usize = 0;
    while (total < 16 * 1024 * 1024) {
        const n = p.system.write(fd, &bytes, bytes.len);
        if (p.errno(n) == .AGAIN) return;
        if (p.errno(n) != .SUCCESS or n == 0) return error.FillFailure;
        total += @intCast(n);
    }
    return error.QueueNeverFilled;
}
const PlainApp = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
        return .{ .text = .{ .content = "plain result" } };
    }
};
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = args[1];
    if (std.mem.eql(u8, mode, "plain")) {
        var app: PlainApp = .{};
        const host = try g.Host(PlainApp).create(init.gpa, &app);
        defer host.destroy() catch unreachable;
        const result = try g.tui.runAdaptive(host, init.io, &.{ "--gama-tui", "--gama-plain" });
        if (result.declared or !result.completion.succeeded()) return error.BadPlainOutcome;
        control("RESTORED\n");
        return;
    }
    const default: p.Sigaction = .{ .handler = .{ .handler = p.SIG.DFL }, .mask = p.sigemptyset(), .flags = 0 };
    for ([_]p.SIG{ .TERM, .HUP, .INT, .QUIT, .WINCH }) |sig| p.sigaction(sig, &default, null);
    const read_only = if (std.mem.eql(u8, mode, "write-fail")) try p.openat(p.AT.FDCWD, "/dev/null", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0) else -1;
    defer if (read_only >= 0) {
        _ = p.system.close(read_only);
    };
    var terminal = try g.tui.Terminal.acquire(init.io, 0, if (read_only >= 0) read_only else 1);
    defer terminal.close() catch {};
    const raw = try p.tcgetattr(0);
    if (raw.lflag.ICANON or raw.lflag.ECHO or raw.lflag.ISIG) return error.NotRaw;
    if (std.mem.eql(u8, mode, "write-fail")) {
        terminal.write("x") catch |err| {
            if (err != error.IOFailure) return err;
            try terminal.close();
            control("RESTORED\n");
            return;
        };
        return error.ExpectedWriteFailure;
    }
    if (std.mem.eql(u8, mode, "blocked")) {
        try fill(1);
        const flags = p.system.fcntl(1, p.F.GETFL, @as(usize, 0));
        if (p.errno(flags) != .SUCCESS) return error.Flags;
        const nonblock: u32 = @bitCast(p.O{ .NONBLOCK = true });
        if (p.errno(p.system.fcntl(1, p.F.SETFL, @as(usize, @intCast(flags)) & ~@as(usize, nonblock))) != .SUCCESS) return error.Flags;
        control("BLOCK_NEXT\n");
        const bytes: [65536]u8 = @splat('y');
        _ = p.system.write(1, &bytes, bytes.len);
        control("UNEXPECTED_WRITE_RETURN\n");
        return error.WriteDidNotBlock;
    }
    if (std.mem.eql(u8, mode, "close-full") or std.mem.eql(u8, mode, "error-full")) {
        try fill(1);
        control("READY\n");
        if (std.mem.eql(u8, mode, "error-full")) {
            terminal.write("stalled") catch |err| {
                if (err != error.OutputStalled) return err;
                try terminal.close();
                control("RESTORED\n");
                return;
            };
            return error.ExpectedStall;
        }
        try terminal.close();
        control("RESTORED\n");
        return;
    }
    if (std.mem.eql(u8, mode, "resize")) {
        control("READY\n");
        while (true) if (try terminal.next(250)) |event| {
            if (event == .resize) {
                if (event.resize.width != 41 or event.resize.height != 9) return error.WrongSize;
                control("RESIZED\n");
                break;
            }
        };
        return;
    }
    if (std.mem.eql(u8, mode, "normal")) {
        try terminal.write("DELIVERED");
        try terminal.close();
        control("RESTORED\n");
        return;
    }
    control("READY\n");
    if (std.mem.eql(u8, mode, "eof")) {
        while (true) {
            _ = terminal.next(250) catch |err| {
                if (err != error.EndOfInput and err != error.IOFailure) return err;
                terminal.close() catch |close_error| {
                    if (close_error != error.IOFailure) return close_error;
                };
                control("EOF\n");
                return;
            };
        }
    }
    while (true) _ = try terminal.next(250);
}
