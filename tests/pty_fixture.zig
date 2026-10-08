//! Fixture alone owns these PTYs; teardown never applies terminal settings.
const std = @import("std");
const p = std.posix;
pub const Pair = struct {
    master: p.fd_t,
    slave: p.fd_t,
    name: [16]u8,
    pub fn open() !Pair {
        const master_env = std.c.getenv("GAMA_TEST_PTY_MASTER") orelse return error.MissingPTYAllocator;
        const slave_env = std.c.getenv("GAMA_TEST_PTY_SLAVE") orelse return error.MissingPTYAllocator;
        const name_env = std.c.getenv("GAMA_TEST_PTY_NAME") orelse return error.MissingPTYAllocator;
        const m = try std.fmt.parseInt(p.fd_t, std.mem.span(master_env), 10);
        const s = try std.fmt.parseInt(p.fd_t, std.mem.span(slave_env), 10);
        // Extra allocator-owned descriptors stay only in the Zig parent.
        if (p.errno(p.system.fcntl(m, p.F.SETFD, @as(usize, p.FD_CLOEXEC))) != .SUCCESS or p.errno(p.system.fcntl(s, p.F.SETFD, @as(usize, p.FD_CLOEXEC))) != .SUCCESS) return error.FixtureFlags;
        const master = p.system.fcntl(m, p.F.DUPFD_CLOEXEC, @as(usize, 0));
        if (p.errno(master) != .SUCCESS) return error.FixtureDup;
        errdefer _ = p.system.close(master);
        const slave = p.system.fcntl(s, p.F.DUPFD_CLOEXEC, @as(usize, 0));
        if (p.errno(slave) != .SUCCESS) return error.FixtureDup;
        errdefer _ = p.system.close(slave);
        const flags = p.system.fcntl(master, p.F.GETFL, @as(usize, 0));
        if (p.errno(flags) != .SUCCESS) return error.FixtureFlags;
        const nonblock: u32 = @bitCast(p.O{ .NONBLOCK = true });
        if (p.errno(p.system.fcntl(master, p.F.SETFL, @as(usize, @intCast(flags)) | nonblock)) != .SUCCESS) return error.FixtureFlags;
        var drain: [4096]u8 = undefined;
        while (true) {
            const n = p.system.read(master, &drain, drain.len);
            if (p.errno(n) != .SUCCESS or n == 0) break;
        }
        var name: [16]u8 = @splat(0);
        const actual_name = std.mem.span(name_env);
        if (actual_name.len >= name.len) return error.FixtureName;
        @memcpy(name[0..actual_name.len], actual_name);
        return .{ .master = master, .slave = slave, .name = name };
    }
    pub fn close(self: Pair) void {
        _ = p.system.close(self.slave);
        _ = p.system.close(self.master);
    }
    pub fn settings(self: Pair) !p.termios {
        return try p.tcgetattr(self.slave);
    }
};
pub fn equal(a: p.termios, b: p.termios) bool {
    // Darwin sets PENDIN when ICANON is restored; this kernel retype latch is not a saved mode.
    var al = a.lflag;
    var bl = b.lflag;
    al.PENDIN = false;
    bl.PENDIN = false;
    return std.meta.eql(a.iflag, b.iflag) and std.meta.eql(a.oflag, b.oflag) and
        std.meta.eql(a.cflag, b.cflag) and std.meta.eql(al, bl) and
        std.mem.eql(u8, &a.cc, &b.cc) and a.ispeed == b.ispeed and a.ospeed == b.ospeed;
}
pub fn write(fd: p.fd_t, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const n = p.system.write(fd, bytes.ptr + offset, bytes.len - offset);
        if (p.errno(n) == .INTR) continue;
        if (p.errno(n) != .SUCCESS or n == 0) return error.FixtureWrite;
        offset += @intCast(n);
    }
}
