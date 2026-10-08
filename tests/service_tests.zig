const std = @import("std");
const g = @import("gama");
const p = g.plugins;
const a = std.testing.allocator;
const io = std.testing.io;
const Hosted = g.HostedServices;
fn temporaryPath(temp: *std.testing.TmpDir) ![]u8 {
    const base = try temp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(base);
    return std.fmt.allocPrint(a, "{s}/payload", .{base});
}
test "injected hosted filesystem inclusive limits zero bound checked writes and real clock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try temporaryPath(&tmp);
    defer a.free(path);
    const prefix = std.fs.path.dirname(path).?;
    const scope = p.Scope{ .prefix = prefix, .writable = true };
    var hosted = try Hosted.init(io, .{ .read_bytes = 4, .write_bytes = 4 });
    const services = try hosted.services();
    try std.testing.expect(services.clock != null);
    const t1 = try services.clock.?(services.userdata);
    const t2 = try services.clock.?(services.userdata);
    try std.testing.expect(t2 >= t1);
    for ([_][]const u8{ "", "abc", "abcd" }) |bytes| {
        try services.write.?(services.userdata, path, bytes, scope);
        const actual = try services.read.?(services.userdata, a, path, scope);
        defer a.free(actual);
        try std.testing.expectEqualStrings(bytes, actual);
    }
    try std.testing.expectError(error.LimitExceeded, services.write.?(services.userdata, path, "abcde", scope));
    const unchanged = try services.read.?(services.userdata, a, path, scope);
    defer a.free(unchanged);
    try std.testing.expectEqualStrings("abcd", unchanged);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "abcde" });
    try std.testing.expectError(error.LimitExceeded, services.read.?(services.userdata, a, path, scope));
    var zero = try Hosted.init(io, .{ .read_bytes = 0, .write_bytes = 0 });
    const z = try zero.services();
    try z.write.?(z.userdata, path, "", scope);
    const empty = try z.read.?(z.userdata, a, path, scope);
    a.free(empty);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "x" });
    try std.testing.expectError(error.LimitExceeded, z.read.?(z.userdata, a, path, scope));
    try std.testing.expectError(error.LimitExceeded, z.write.?(z.userdata, path, "x", scope));
}
test "hosted validation before failing backend and explicit unavailability" {
    var hosted = try Hosted.init(std.Io.failing, .{ .read_bytes = 4, .write_bytes = 4, .log_bytes = 4, .path_bytes = 8 });
    const s = try hosted.services();
    try std.testing.expect(s.clock == null);
    try std.testing.expectError(error.AccessDenied, s.read.?(s.userdata, a, "/ab", .{ .prefix = "/a" }));
    try std.testing.expectError(error.AccessDenied, s.write.?(s.userdata, "/a", "x", .{ .prefix = "/a" }));
    try std.testing.expectError(error.LimitExceeded, s.write.?(s.userdata, "/a", "abcde", .{ .prefix = "/a", .writable = true }));
    try std.testing.expectError(error.LimitExceeded, s.read.?(s.userdata, a, "/a/longlong", .{ .prefix = "/a" }));
    try std.testing.expectError(error.LimitExceeded, s.log.?(s.userdata, "id", "long"));
    try std.testing.expectError(error.IOFailure, s.write.?(s.userdata, "/a", "x", .{ .prefix = "/a", .writable = true }));
    try std.testing.expectError(error.IOFailure, s.read.?(s.userdata, a, "/a", .{ .prefix = "/a" }));
    try std.testing.expectError(error.InvalidLimit, Hosted.init(io, .{ .read_bytes = std.math.maxInt(usize) }));
    try std.testing.expectError(error.InvalidLimit, Hosted.init(io, .{ .write_bytes = std.math.maxInt(usize) }));
    try std.testing.expectError(error.InvalidClock, Hosted.timestampMillis(-1));
    try std.testing.expectError(error.InvalidClock, Hosted.timestampMillis(std.math.maxInt(i96)));
    try std.testing.expectEqual(@as(u64, 0), try Hosted.timestampMillis(0));
    try std.testing.expectEqual(@as(u64, 7), try Hosted.timestampMillis(7_999_999));
}
const Plugin = struct {
    saved: *?p.Context,
    path: []const u8,
    pub fn manifest(_: *Plugin) p.Manifest {
        return .{ .id = "disk", .requires = &.{ .log, .clock, .{ .filesystem = .{ .prefix = "/", .writable = true } } } };
    }
    pub fn activate(self: *Plugin, ctx: p.Context) g.Error!void {
        self.saved.* = ctx;
        const fs = (try ctx.filesystem()).?;
        try fs.write(self.path, "real bytes");
        const bytes = try fs.read(a, self.path);
        defer a.free(bytes);
        if (!std.mem.eql(u8, bytes, "real bytes")) return error.IOFailure;
        _ = try (try ctx.clock()).?.nowMillis();
    }
};
test "real hosted services injected through runtime and revoked handles" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try temporaryPath(&tmp);
    defer a.free(path);
    var hosted = try Hosted.init(io, .{});
    const s = try hosted.services();
    const runtime = try g.PluginRuntime.create(a, .{ .entries = &.{.{ .id = "disk", .capabilities = &.{ .log, .clock, .{ .filesystem = .{ .prefix = "/", .writable = true } } } }} }, s);
    defer runtime.destroy() catch unreachable;
    var saved: ?p.Context = null;
    try runtime.install(Plugin{ .saved = &saved, .path = path });
    const fs = (try saved.?.filesystem()).?;
    try runtime.uninstall("disk");
    try std.testing.expectError(error.InvalidHandle, fs.write(path, "revoked"));
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(100));
    defer a.free(bytes);
    try std.testing.expectEqualStrings("real bytes", bytes);
}
fn allocationRead(allocator: std.mem.Allocator, services: p.Services, path: []const u8) !void {
    const bytes = try services.read.?(services.userdata, allocator, path, .{ .prefix = "/" });
    defer allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 10000), bytes.len);
}
test "hosted read OOM sweep closes files and frees partially allocated bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try temporaryPath(&tmp);
    defer a.free(path);
    const data: [10000]u8 = @splat('x');
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &data });
    var hosted = try Hosted.init(io, .{});
    const s = try hosted.services();
    try std.testing.checkAllAllocationFailures(a, allocationRead, .{ s, path });
}

const LogProbe = struct {
    bytes: std.ArrayList(u8) = .empty,
    canceled: bool = false,
    calls: usize = 0,
    fn operate(raw: ?*anyopaque, operation: std.Io.Operation) std.Io.Cancelable!std.Io.Operation.Result {
        const self: *LogProbe = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.canceled) return error.Canceled;
        switch (operation) {
            .file_write_streaming => |w| {
                self.bytes.appendSlice(a, w.header) catch unreachable;
                var count = w.header.len;
                for (w.data, 0..) |bytes, i| {
                    const repeats: usize = if (i + 1 == w.data.len) w.splat else 1;
                    for (0..repeats) |_| {
                        self.bytes.appendSlice(a, bytes) catch unreachable;
                        count += bytes.len;
                    }
                }
                return .{ .file_write_streaming = count };
            },
            else => unreachable,
        }
    }
};
test "injected log byte format cancellation and bound checked before backend" {
    var probe: LogProbe = .{};
    defer probe.bytes.deinit(a);
    var table = std.Io.failing.vtable.*;
    table.operate = LogProbe.operate;
    var hosted = try Hosted.init(.{ .userdata = &probe, .vtable = &table }, .{ .log_bytes = 16 });
    const s = try hosted.services();
    try s.log.?(s.userdata, "a", "hello\nworld");
    try std.testing.expectEqualStrings("[a] hello\nworld\n", probe.bytes.items);
    const calls = probe.calls;
    try std.testing.expectError(error.LimitExceeded, s.log.?(s.userdata, "a", "this message is oversized"));
    try std.testing.expectEqual(calls, probe.calls);
    probe.canceled = true;
    try std.testing.expectError(error.Canceled, s.log.?(s.userdata, "a", "x"));
    probe.canceled = false;
    try s.log.?(s.userdata, "a", "retry");
}
const CancelProbe = struct {
    var closes: usize = 0;
    fn read(_: ?*anyopaque, _: std.Io.File, _: []const []u8, _: u64) std.Io.File.ReadPositionalError!usize {
        return error.Canceled;
    }
    fn close(raw: ?*anyopaque, files: []const std.Io.File) void {
        closes += files.len;
        io.vtable.fileClose(raw, files);
    }
    fn operate(_: ?*anyopaque, _: std.Io.Operation) std.Io.Cancelable!std.Io.Operation.Result {
        return error.Canceled;
    }
};
test "real open canceled read and direct write release file resources with explicit partial write limits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try temporaryPath(&tmp);
    defer a.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "old content" });
    var table = io.vtable.*;
    table.fileReadPositional = CancelProbe.read;
    table.fileClose = CancelProbe.close;
    table.operate = CancelProbe.operate;
    var hosted = try Hosted.init(.{ .userdata = io.userdata, .vtable = &table }, .{});
    const s = try hosted.services();
    CancelProbe.closes = 0;
    try std.testing.expectError(error.Canceled, s.read.?(s.userdata, a, path, .{ .prefix = "/" }));
    try std.testing.expectEqual(@as(usize, 1), CancelProbe.closes);
    try std.testing.expectError(error.Canceled, s.write.?(s.userdata, path, "new", .{ .prefix = "/", .writable = true }));
    try std.testing.expectEqual(@as(usize, 2), CancelProbe.closes);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(100));
    defer a.free(bytes);
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
}
const ServiceForeign = struct {
    hosted: *Hosted,
    services: p.Services,
    failure: ?anyerror = null,
    fn run(self: *ServiceForeign) void {
        self.check() catch |err| {
            self.failure = err;
        };
    }
    fn check(self: *ServiceForeign) !void {
        const s = self.services;
        try std.testing.expectError(error.WrongThread, self.hosted.services());
        try std.testing.expectError(error.WrongThread, s.log.?(s.userdata, "a", "x"));
        try std.testing.expectError(error.WrongThread, s.clock.?(s.userdata));
        try std.testing.expectError(error.WrongThread, s.read.?(s.userdata, a, "/x", .{ .prefix = "/" }));
        try std.testing.expectError(error.WrongThread, s.write.?(s.userdata, "/x", "x", .{ .prefix = "/", .writable = true }));
    }
};
test "hosted adapter rejects foreign thread before I/O" {
    var hosted = try Hosted.init(io, .{});
    var foreign = ServiceForeign{ .hosted = &hosted, .services = try hosted.services() };
    const thread = try std.Thread.spawn(.{}, ServiceForeign.run, .{&foreign});
    thread.join();
    if (foreign.failure) |err| return err;
}
test "lexically allowed symlink may escape prefix documented limitation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "granted", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "outside", .data = "outside bytes" });
    try tmp.dir.symLink(io, "../outside", "granted/link", .{});
    const prefix = try tmp.dir.realPathFileAlloc(io, "granted", a);
    defer a.free(prefix);
    const path = try std.fmt.allocPrint(a, "{s}/link", .{prefix});
    defer a.free(path);
    var hosted = try Hosted.init(io, .{});
    const s = try hosted.services();
    const bytes = try s.read.?(s.userdata, a, path, .{ .prefix = prefix });
    defer a.free(bytes);
    try std.testing.expectEqualStrings("outside bytes", bytes);
}
