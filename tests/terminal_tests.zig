const std = @import("std");
const g = @import("gama");
const t = g.tui;
const a = std.testing.allocator;

test "adaptive selection uses stdout and last recognized flag" {
    try std.testing.expectEqual(t.Mode.plain, t.select(false, &.{}));
    try std.testing.expectEqual(t.Mode.interactive, t.select(true, &.{}));
    try std.testing.expectEqual(t.Mode.plain, t.select(true, &.{ "--gama-tui", "ignored", "--gama-plain" }));
    try std.testing.expectEqual(t.Mode.interactive, t.select(false, &.{ "--gama-plain", "--gama-tui" }));
    try std.testing.expectEqual(@as(i64, 80), t.default_size.width);
    try std.testing.expectEqual(@as(i64, 24), t.default_size.height);
}
test "fragmented keys scalar unicode lone escape and bounded recovery" {
    var d: t.Decoder = .{};
    try d.feed("\x1b[");
    try std.testing.expectEqual(@as(?g.Event, null), d.next(0));
    try d.feed("A");
    try std.testing.expect(d.next(1).?.key == .up);
    try d.feed("\xf0\x9f");
    try std.testing.expectEqual(@as(?g.Event, null), d.next(2));
    try d.feed("\x98\x80");
    try std.testing.expectEqualStrings("😀", d.next(3).?.key.character);
    try d.feed("\x1b");
    try std.testing.expectEqual(@as(?g.Event, null), d.next(10));
    try std.testing.expectEqual(@as(?g.Event, null), d.next(34));
    try std.testing.expect(d.next(35).?.key == .escape);
    var hostile: [t.Decoder.capacity]u8 = @splat('1');
    hostile[0] = 27;
    hostile[1] = '[';
    try d.feed(&hostile);
    try std.testing.expectEqual(@as(?g.Event, null), d.next(40));
    try d.feed("q");
    try std.testing.expectEqualStrings("q", d.next(41).?.key.character);
}
const App = struct {
    value: []const u8 = "hello",
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), _: *g.BuildContext) g.Error!g.Node {
        return .{ .text = .{ .content = self.value } };
    }
};
const Fake = struct {
    output: std.ArrayList(u8) = .empty,
    polls: usize = 0,
    ends: usize = 0,
    fail: bool = false,
    pub fn begin(_: *@This()) g.Error!void {}
    pub fn end(self: *@This()) g.Error!void {
        self.ends += 1;
    }
    pub fn extent(_: *@This()) g.Error!g.geometry.Size {
        return t.default_size;
    }
    pub fn waitsForInput(_: *@This()) bool {
        return false;
    }
    pub fn next(self: *@This(), _: i32) g.Error!?g.Event {
        self.polls += 1;
        return null;
    }
    pub fn write(self: *@This(), bytes: []const u8) g.Error!void {
        if (self.fail) {
            try self.output.appendSlice(a, bytes[0..@min(2, bytes.len)]);
            return error.IOFailure;
        }
        try self.output.appendSlice(a, bytes);
    }
};
test "plain loop quiescence semantic replacement one drain completion and cleanup" {
    var app: App = .{};
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    var surface: Fake = .{};
    defer surface.output.deinit(a);
    try host.emit("semantic");
    const result = try t.run(host, &surface);
    try std.testing.expect(!result.declared and result.completion.succeeded());
    try std.testing.expectEqualStrings("semantic\n", surface.output.items);
    try std.testing.expectEqual(@as(usize, 1), surface.polls);
    try std.testing.expectEqual(@as(usize, 1), surface.ends);
    try std.testing.expectEqual(@as(usize, 0), (try host.pendingLines()).len);
    try host.complete(.failure(7, "failed"));
    try host.complete(.success());
    const declared = try t.run(host, &surface);
    try std.testing.expect(declared.declared);
    try std.testing.expectEqual(@as(i32, 7), declared.completion.code);
    try std.testing.expectEqualStrings("semantic\nhello\n", surface.output.items);
}
test "partial transport aborts host candidate and raster while preserving retry and lines" {
    var app: App = .{};
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.handle(.{ .resize = .{ .width = 8, .height = 1 } });
    var draw = try g.DrawingPump(App).init(a, host, .plain);
    defer draw.deinit();
    var surface: Fake = .{};
    defer surface.output.deinit(a);
    _ = try draw.advanceDelivered(&surface, Fake.write, &.{});
    const old = (try host.currentTree()).?;
    app.value = "goodbye";
    try host.emit("announcement");
    surface.fail = true;
    try std.testing.expectError(error.IOFailure, draw.advanceDelivered(&surface, Fake.write, try host.pendingLines()));
    try std.testing.expect((try host.currentTree()).? == old);
    try std.testing.expect(try host.needsFrame());
    try std.testing.expectEqualStrings("h", draw.buffer.front.cells[0].glyph);
    try std.testing.expectEqual(@as(usize, 1), (try host.pendingLines()).len);
    surface.fail = false;
    _ = try draw.advanceDelivered(&surface, Fake.write, try host.pendingLines());
    try std.testing.expectEqualStrings("g", draw.buffer.front.cells[0].glyph);
}
// Force semantic analysis of the real POSIX adapter before PTY runtime tests.
test "terminal invalid descriptor unwinds ownership before reacquisition" {
    try std.testing.expectError(error.IOFailure, t.Terminal.acquire(std.testing.io, -1, -1));
    try std.testing.expectError(error.IOFailure, t.Terminal.acquire(std.testing.io, -1, -1));
    var surface = t.Surface.init(std.testing.io, .plain);
    surface.output = .{ .handle = -1, .flags = .{ .nonblocking = false } };
    try surface.begin();
    try std.testing.expectError(error.IOFailure, surface.write("x"));
    try surface.end();
}
const fixture = @import("pty_fixture.zig");
const posix = std.posix;
test "native PTY raw ownership keys resize restoration and reacquire" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    var terminal = try t.Terminal.acquire(std.testing.io, pair.slave, pair.slave);
    defer terminal.close() catch unreachable;
    try std.testing.expect(!(try pair.settings()).lflag.ICANON);
    try std.testing.expectError(error.TerminalBusy, t.Terminal.acquire(std.testing.io, pair.slave, pair.slave));
    try fixture.write(pair.master, "\x1b[A");
    try std.testing.expect((try terminal.next(100)).?.key == .up);
    try fixture.write(pair.master, "\x1b[<-;3;5M");
    try std.testing.expectEqual(g.geometry.Point{ .x = 2, .y = 4 }, (try terminal.next(100)).?.pointer);
    try posix.raise(.WINCH);
    try posix.raise(.WINCH);
    try std.testing.expect((try terminal.next(0)).? == .resize);
    try std.testing.expectEqual(@as(?g.Event, null), try terminal.next(0));
    try std.testing.expect(!(try pair.settings()).lflag.ICANON);
    try terminal.write("delivered");
    var bytes: [128]u8 = undefined;
    const n = try posix.read(pair.master, &bytes);
    try std.testing.expectEqualStrings("delivered", bytes[0..n]);
    try terminal.close();
    try std.testing.expect(fixture.equal(before, try pair.settings()));
    var next = try t.Terminal.acquire(std.testing.io, pair.slave, pair.slave);
    try next.close();
    try std.testing.expect(fixture.equal(before, try pair.settings()));
}
var called = std.atomic.Value(u32).init(0);
var mask_ok = std.atomic.Value(bool).init(false);
fn returning(_: posix.SIG) callconv(.c) void {
    var mask: posix.sigset_t = undefined;
    posix.sigprocmask(posix.SIG.SETMASK, null, &mask);
    mask_ok.store(posix.sigismember(&mask, .USR1), .seq_cst);
    _ = called.fetchAdd(1, .seq_cst);
}
test "displaced returning mask flags errno and retired callback during later lease" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    var old: posix.Sigaction = undefined;
    var mask = posix.sigemptyset();
    posix.sigaddset(&mask, .USR1);
    const action: posix.Sigaction = .{ .handler = .{ .handler = returning }, .mask = mask, .flags = posix.SA.RESTART };
    const default: posix.Sigaction = .{ .handler = .{ .handler = posix.SIG.DFL }, .mask = posix.sigemptyset(), .flags = 0 };
    posix.sigaction(.TERM, &default, &old);
    defer posix.sigaction(.TERM, &old, null);
    var first = try t.Terminal.acquire(std.testing.io, pair.slave, pair.slave);
    var retired: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &retired);
    try first.close();
    posix.sigaction(.TERM, &action, null);
    var second = try t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{.{ .signal = .TERM, .action = action }});
    defer second.close() catch unreachable;
    called.store(0, .seq_cst);
    std.c._errno().* = 73;
    retired.handler.handler.?(.TERM);
    try std.testing.expectEqual(@as(c_int, 73), std.c._errno().*);
    try std.testing.expectEqual(@as(u32, 1), called.load(.seq_cst));
    try std.testing.expect(mask_ok.load(.seq_cst));
    try std.testing.expect(fixture.equal(before, try pair.settings()));
    var actual: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &actual);
    try std.testing.expectEqual(action.handler.handler, actual.handler.handler);
    try std.testing.expectEqual(action.flags, actual.flags);
    try std.testing.expect(posix.sigismember(&actual.mask, .USR1));
    try std.testing.expectError(error.TerminalInterrupted, second.write("x"));
    try second.close();
}
test "one-shot displaced disposition remains reset after normal close" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    var old: posix.Sigaction = undefined;
    const action: posix.Sigaction = .{ .handler = .{ .handler = returning }, .mask = posix.sigemptyset(), .flags = posix.SA.RESETHAND };
    posix.sigaction(.TERM, &action, &old);
    defer posix.sigaction(.TERM, &old, null);
    var terminal = try t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{.{ .signal = .TERM, .action = action }});
    called.store(0, .seq_cst);
    try posix.raise(.TERM);
    try terminal.close();
    var after: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &after);
    try std.testing.expectEqual(posix.SIG.DFL, after.handler.handler);
}
test "all keyboard mappings bounded malformed input and mouse compatibility" {
    const cases = .{
        .{ "\r", g.Key.enter },     .{ "\n", g.Key.enter },        .{ "\t", g.Key.tab },         .{ "\x7f", g.Key.backspace },  .{ "\x08", g.Key.backspace },
        .{ "\x1b[B", g.Key.down },  .{ "\x1b[C", g.Key.right },    .{ "\x1b[D", g.Key.left },    .{ "\x1b[5A", g.Key.up },      .{ "\x1b[H", g.Key.home },
        .{ "\x1b[F", g.Key.end },   .{ "\x1b[Z", g.Key.back_tab }, .{ "\x1b[3~", g.Key.delete }, .{ "\x1b[5~", g.Key.page_up }, .{ "\x1b[6~", g.Key.page_down },
        .{ "\x1b[1~", g.Key.home }, .{ "\x1b[8~", g.Key.end },
    };
    inline for (cases) |case| {
        var d: t.Decoder = .{};
        try d.feed(case[0]);
        try std.testing.expectEqual(case[1], d.next(0).?.key);
    }
    for ([_]u8{ 1, 2, 3, 4, 5, 6, 7, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26 }) |byte| {
        var d: t.Decoder = .{};
        try d.feed(&.{byte});
        try std.testing.expectEqual(@as(u21, 'a' + byte - 1), d.next(0).?.key.shortcut.codepoint);
    }
    for ([_][]const u8{ "\x1b[11~", "\x1b[12~", "\x1b[13~", "\x1b[14~", "\x1b[15~", "\x1b[17~", "\x1b[18~", "\x1b[19~", "\x1b[20~", "\x1b[21~", "\x1b[23~", "\x1b[24~" }, 1..) |bytes, number| {
        var d: t.Decoder = .{};
        for (bytes[0 .. bytes.len - 1]) |byte| {
            try d.feed(&.{byte});
            try std.testing.expectEqual(@as(?g.Event, null), d.next(0));
        }
        try d.feed(bytes[bytes.len - 1 ..]);
        try std.testing.expectEqual(@as(u8, @intCast(number)), d.next(1).?.key.function);
    }
    var d: t.Decoder = .{};
    try d.feed("\x1bO");
    try std.testing.expectEqual(@as(?g.Event, null), d.next(0));
    try d.feed("S");
    try std.testing.expectEqual(@as(u8, 4), d.next(1).?.key.function);
    try d.feed("\x1bq");
    try std.testing.expect(d.next(0).?.key == .escape);
    try std.testing.expectEqualStrings("q", d.next(1).?.key.character);
    try d.feed("\xffx");
    try std.testing.expectEqual(@as(?g.Event, null), d.next(0));
    try std.testing.expectEqualStrings("x", d.next(1).?.key.character);
    try d.feed("\xf0");
    try std.testing.expectEqual(@as(?g.Event, null), d.next(0));
    try std.testing.expectEqual(@as(?g.Event, null), d.next(250));
    try std.testing.expectEqual(@as(usize, 0), d.len);
    try d.feed("\x1b[<64;1;2M");
    try std.testing.expectEqual(g.geometry.Point{ .x = 0, .y = 1 }, d.next(0).?.pointer);
    try d.feed("\x1b[<-;1;2m");
    try std.testing.expect(d.next(0).? == .pointer_release);
    try d.feed("\x1b[<0;-9223372036854775808;2M");
    try std.testing.expectEqual(@as(?g.Event, null), d.next(0));
    var large: [t.Decoder.capacity + 1]u8 = @splat('x');
    try std.testing.expectError(error.InputFull, d.feed(&large));
}
fn stageBytes(_: void, _: g.Host(App).Preparation) g.Error![]const u8 {
    return "frame";
}
test "staged tokens reject repeats stale copies thread crossing and delivery reentry" {
    var app: App = .{};
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    const candidate = (try host.prepare(.{ .width = 3, .height = 1 })).?;
    const C = struct {
        token: g.Host(App).PreparedFrame,
        fn send(self: *@This(), bytes: []const u8) g.Error!void {
            std.testing.expectEqualStrings("frame", bytes) catch unreachable;
            std.testing.expectError(error.Reentrant, self.token.abort()) catch unreachable;
            std.testing.expectError(error.Reentrant, self.token.commit()) catch unreachable;
            std.testing.expectError(error.Reentrant, self.token.deliver(self, send)) catch unreachable;
            std.testing.expectError(error.Reentrant, self.token.owner.destroy()) catch unreachable;
        }
        fn other(token: g.Host(App).PreparedFrame) void {
            std.testing.expectError(error.WrongThread, token.stage({}, stageBytes)) catch unreachable;
            var context: @This() = .{ .token = token };
            std.testing.expectError(error.WrongThread, token.deliver(&context, send)) catch unreachable;
        }
    };
    var context: C = .{ .token = candidate };
    try std.testing.expectError(error.InvalidTransaction, candidate.deliver(&context, C.send));
    try candidate.stage({}, stageBytes);
    try std.testing.expectError(error.InvalidTransaction, candidate.stage({}, stageBytes));
    const thread = try std.Thread.spawn(.{}, C.other, .{candidate});
    thread.join();
    try candidate.deliver(&context, C.send);
    try std.testing.expectError(error.InvalidTransaction, candidate.deliver(&context, C.send));
    try std.testing.expectError(error.InvalidTransaction, candidate.abort());
}
fn deliverySweep(allocator: std.mem.Allocator) !void {
    var app: App = .{};
    const host = try g.Host(App).create(allocator, &app);
    defer host.destroy() catch unreachable;
    try host.handle(.{ .resize = .{ .width = 8, .height = 2 } });
    var draw = try g.DrawingPump(App).init(allocator, host, .plain);
    defer draw.deinit();
    const Transport = struct {
        called: usize = 0,
        fn write(self: *@This(), _: []const u8) g.Error!void {
            self.called += 1;
        }
    };
    var transport: Transport = .{};
    _ = draw.advanceDelivered(&transport, Transport.write, &.{}) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), transport.called);
        try std.testing.expectEqual(@as(?g.Node, null), try host.currentNode());
        try std.testing.expect(try host.needsFrame());
        return err;
    };
    try std.testing.expectEqual(@as(usize, 1), transport.called);
}
test "all host raster serialization final-copy OOM precedes first transport byte" {
    try std.testing.checkAllAllocationFailures(a, deliverySweep, .{});
}
test "decoded scalar input keeps grapheme cursor deletion intact in shared host" {
    const Editor = struct {
        ref: ?g.StateRef(g.String) = null,
        pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
        fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
            self.ref = try ctx.state(g.String, 1, .{ .bytes = "" });
            const field: g.authoring.TextField = .{ .value = (try self.ref.?.read()).bytes, .binding = self.ref.?.token };
            return field.render(ctx);
        }
    };
    var app: Editor = .{};
    const host = try g.Host(Editor).create(a, &app);
    defer host.destroy() catch unreachable;
    const size: g.geometry.Size = .{ .width = 40, .height = 1 };
    try host.rebuild(size);
    var decoder: t.Decoder = .{};
    for ("é👩‍🚀") |byte| {
        try decoder.feed(&.{byte});
        if (decoder.next(0)) |event| {
            try host.handle(event);
            try host.rebuild(size);
        }
    }
    try std.testing.expectEqualStrings("é👩‍🚀", (try app.ref.?.read()).bytes);
    try decoder.feed("\x1b[D\x7f");
    try host.handle(decoder.next(0).?);
    try host.rebuild(size);
    try host.handle(decoder.next(0).?);
    try host.rebuild(size);
    try std.testing.expectEqualStrings("👩‍🚀", (try app.ref.?.read()).bytes);
}
test "terminal lifecycle and IO reject foreign thread in native modes" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    var terminal = try t.Terminal.acquire(std.testing.io, pair.slave, pair.slave);
    defer terminal.close() catch unreachable;
    const Other = struct {
        fn check(term: *t.Terminal) void {
            std.testing.expectError(error.WrongThread, term.close()) catch unreachable;
            std.testing.expectError(error.WrongThread, term.write("x")) catch unreachable;
            std.testing.expectError(error.WrongThread, term.next(0)) catch unreachable;
            std.testing.expectError(error.WrongThread, term.size()) catch unreachable;
        }
    };
    const thread = try std.Thread.spawn(.{}, Other.check, .{&terminal});
    thread.join();
    try std.testing.expect(!(try pair.settings()).lflag.ICANON);
}
test "returning process-directed signal overlaps normal release and reacquisition" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    const action: posix.Sigaction = .{ .handler = .{ .handler = returning }, .mask = posix.sigemptyset(), .flags = 0 };
    var old: posix.Sigaction = undefined;
    posix.sigaction(.TERM, &action, &old);
    defer posix.sigaction(.TERM, &old, null);
    const Sender = struct {
        fn send() void {
            _ = posix.system.kill(std.c.getpid(), .TERM);
        }
    };
    for (0..32) |_| {
        var terminal = try t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{.{ .signal = .TERM, .action = action }});
        const thread = try std.Thread.spawn(.{}, Sender.send, .{});
        try terminal.close();
        thread.join();
        try std.testing.expect(fixture.equal(before, try pair.settings()));
    }
}
test "Darwin custom dispositions fail closed unless exact caller records validate" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    const action: posix.Sigaction = .{ .handler = .{ .handler = returning }, .mask = posix.sigemptyset(), .flags = posix.SA.RESETHAND };
    var old: posix.Sigaction = undefined;
    posix.sigaction(.TERM, &action, &old);
    defer posix.sigaction(.TERM, &old, null);
    try std.testing.expectError(error.UnverifiableDisposition, t.Terminal.acquire(std.testing.io, pair.slave, pair.slave));
    const record: t.Terminal.Disposition = .{ .signal = .TERM, .action = action };
    try std.testing.expectError(error.InvalidDisposition, t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{ record, record }));
    var bad = record;
    bad.signal = .USR1;
    try std.testing.expectError(error.InvalidDisposition, t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{bad}));
    bad = record;
    bad.action.handler.handler = posix.SIG.IGN;
    try std.testing.expectError(error.InvalidDisposition, t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{bad}));
    bad = record;
    posix.sigaddset(&bad.action.mask, .USR1);
    try std.testing.expectError(error.InvalidDisposition, t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{bad}));
    bad = record;
    bad.action.flags |= posix.SA.RESTART;
    try std.testing.expectError(error.InvalidDisposition, t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{bad}));
    try std.testing.expect(fixture.equal(before, try pair.settings()));
    // The original one-shot action was not overwritten by any failed preflight.
    try posix.raise(.TERM);
    var after: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &after);
    try std.testing.expectEqual(posix.SIG.DFL, after.handler.handler);
}
test "ignored disposition preserves entry errno and termios" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    const action: posix.Sigaction = .{ .handler = .{ .handler = posix.SIG.IGN }, .mask = posix.sigemptyset(), .flags = 0 };
    var old: posix.Sigaction = undefined;
    posix.sigaction(.TERM, &action, &old);
    defer posix.sigaction(.TERM, &old, null);
    var terminal = try t.Terminal.acquire(std.testing.io, pair.slave, pair.slave);
    defer terminal.close() catch unreachable;
    std.c._errno().* = 61;
    try posix.raise(.TERM);
    try std.testing.expectEqual(@as(c_int, 61), std.c._errno().*);
    try std.testing.expect(fixture.equal(before, try pair.settings()));
    var after: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &after);
    try std.testing.expectEqual(posix.SIG.IGN, after.handler.handler);
}
test "runtime reports transport failure and still ends surface without draining semantic lines" {
    var app: App = .{};
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    var surface: Fake = .{ .fail = true };
    defer surface.output.deinit(a);
    try host.emit("retain");
    try std.testing.expectError(error.IOFailure, t.run(host, &surface));
    try std.testing.expectEqual(@as(usize, 1), surface.ends);
    try std.testing.expectEqual(@as(usize, 1), (try host.pendingLines()).len);
    try std.testing.expect(try host.needsFrame());
}
test "final returned-byte copy failure never reaches transport and keeps old publication" {
    var failing = std.testing.FailingAllocator.init(a, .{});
    var app: App = .{};
    const host = try g.Host(App).create(failing.allocator(), &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{ .width = 3, .height = 1 });
    const previous = (try host.currentTree()).?;
    try host.invalidate();
    const candidate = (try host.prepare(.{ .width = 3, .height = 1 })).?;
    const Prepare = struct {
        var large: [65536]u8 = @splat('x');
        fn copy(allocator: *std.testing.FailingAllocator, _: g.Host(App).Preparation) g.Error![]const u8 {
            allocator.fail_index = allocator.alloc_index;
            return &large;
        }
    };
    try std.testing.expectError(error.OutOfMemory, candidate.stage(&failing, Prepare.copy));
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expect((try host.currentTree()).? == previous);
    try std.testing.expect(try host.needsFrame());
    try std.testing.expectError(error.InvalidTransaction, candidate.commit());
}
test "copied closed lease rejects descriptor reuse without affecting later owner" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    var first = try t.Terminal.acquire(std.testing.io, pair.slave, pair.slave);
    var stale = first;
    try first.close();
    var second = try t.Terminal.acquire(std.testing.io, pair.slave, pair.slave);
    defer second.close() catch unreachable;
    try std.testing.expectError(error.InvalidHandle, stale.close());
    try std.testing.expectError(error.InvalidHandle, stale.size());
    try std.testing.expect(!(try pair.settings()).lflag.ICANON);
}
const CaptureRace = struct {
    var fail_after_first: bool = false;
    fn deliver() void {
        var mask = posix.sigemptyset();
        posix.sigaddset(&mask, .WINCH);
        posix.sigprocmask(posix.SIG.UNBLOCK, &mask, null);
        posix.raise(.WINCH) catch unreachable;
    }
    fn beforeReplace(index: usize) bool {
        if (index == 0) {
            // Acquisition has captured metadata and blocked only its own thread.
            // This new thread explicitly unblocks and consumes the real one-shot.
            const thread = std.Thread.spawn(.{}, deliver, .{}) catch unreachable;
            thread.join();
            var live: posix.Sigaction = undefined;
            posix.sigaction(.WINCH, null, &live);
            std.testing.expectEqual(@as(u32, 1), called.load(.seq_cst)) catch unreachable;
            std.testing.expectEqual(posix.SIG.DFL, live.handler.handler) catch unreachable;
        }
        return !(fail_after_first and index == 1);
    }
    fn check(fail: bool) !void {
        const pair = try fixture.Pair.open();
        defer pair.close();
        const before = try pair.settings();
        var old: posix.Sigaction = undefined;
        const action: posix.Sigaction = .{ .handler = .{ .handler = returning }, .mask = posix.sigemptyset(), .flags = posix.SA.RESETHAND };
        posix.sigaction(.WINCH, &action, &old);
        defer posix.sigaction(.WINCH, &old, null);
        called.store(0, .seq_cst);
        fail_after_first = fail;
        t.Terminal.TestHooks.before_replace = beforeReplace;
        defer t.Terminal.TestHooks.before_replace = null;
        if (fail) {
            try std.testing.expectError(error.IOFailure, t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{.{ .signal = .WINCH, .action = action }}));
        } else {
            var terminal = try t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{.{ .signal = .WINCH, .action = action }});
            try terminal.close();
        }
        var live: posix.Sigaction = undefined;
        posix.sigaction(.WINCH, null, &live);
        // Default WINCH is harmless, so real repeat delivery can prove no second
        // callback without killing the test runner (TERM's default would do so).
        try posix.raise(.WINCH);
        std.debug.print("capture race partial={any}: callback count={d}, remains-default={any}\n", .{ fail, called.load(.seq_cst), live.handler.handler == posix.SIG.DFL });
        try std.testing.expectEqual(@as(u32, 1), called.load(.seq_cst));
        try std.testing.expectEqual(posix.SIG.DFL, live.handler.handler);
        try std.testing.expect(fixture.equal(before, try pair.settings()));
    }
};
test "capture-to-replacement one-shot consumption never resurrects on close" {
    try CaptureRace.check(false);
}
test "partial-install rollback preserves independently consumed uninstalled one-shot" {
    try CaptureRace.check(true);
}
const InstallingSignal = struct {
    fn deliver() void {
        var mask = posix.sigemptyset();
        posix.sigaddset(&mask, .TERM);
        posix.sigprocmask(posix.SIG.UNBLOCK, &mask, null);
        posix.raise(.TERM) catch unreachable;
    }
    fn afterReplace(index: usize) void {
        if (index != 0) return;
        // Real callback arrives after replacement, before its returned old action
        // has been copied into rescue state. It must remain pending-only.
        const thread = std.Thread.spawn(.{}, deliver, .{}) catch unreachable;
        thread.join();
        std.testing.expectEqual(@as(u32, 0), called.load(.seq_cst)) catch unreachable;
    }
    fn failSecond(index: usize) bool {
        return index == 0;
    }
};
test "installing callbacks wait for authoritative actions before success or rollback delivery" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    var old: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &old);
    defer posix.sigaction(.TERM, &old, null);
    const action: posix.Sigaction = .{ .handler = .{ .handler = returning }, .mask = posix.sigemptyset(), .flags = posix.SA.RESETHAND };
    t.Terminal.TestHooks.after_replace = InstallingSignal.afterReplace;
    defer t.Terminal.TestHooks.after_replace = null;
    defer t.Terminal.TestHooks.before_replace = null;
    for ([_]bool{ false, true }) |fail| {
        posix.sigaction(.TERM, &action, null);
        called.store(0, .seq_cst);
        t.Terminal.TestHooks.before_replace = if (fail) InstallingSignal.failSecond else null;
        if (fail) {
            try std.testing.expectError(error.IOFailure, t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{.{ .signal = .TERM, .action = action }}));
        } else {
            var terminal = try t.Terminal.acquireWithActions(std.testing.io, pair.slave, pair.slave, &.{.{ .signal = .TERM, .action = action }});
            try std.testing.expectError(error.TerminalInterrupted, terminal.write("x"));
            try terminal.close();
        }
        try std.testing.expectEqual(@as(u32, 1), called.load(.seq_cst));
        var live: posix.Sigaction = undefined;
        posix.sigaction(.TERM, null, &live);
        try std.testing.expectEqual(posix.SIG.DFL, live.handler.handler);
        try std.testing.expect(fixture.equal(before, try pair.settings()));
    }
}
test "immutable rescue slots exhaust before any terminal or disposition mutation" {
    const pair = try fixture.Pair.open();
    defer pair.close();
    const before = try pair.settings();
    var old: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &old);
    var successful: usize = 0;
    while (successful < 256) : (successful += 1) {
        var terminal = t.Terminal.acquire(std.testing.io, pair.slave, pair.slave) catch |err| {
            try std.testing.expectEqual(error.GenerationExhausted, err);
            break;
        };
        try terminal.close();
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = posix.system.read(pair.master, &buf, buf.len);
            if (posix.errno(n) != .SUCCESS or n == 0) break;
        }
    }
    try std.testing.expect(successful > 0);
    try std.testing.expectError(error.GenerationExhausted, t.Terminal.acquire(std.testing.io, -1, -1));
    try std.testing.expectError(error.GenerationExhausted, t.Terminal.acquire(std.testing.io, pair.slave, pair.slave));
    try std.testing.expect(fixture.equal(before, try pair.settings()));
    var after: posix.Sigaction = undefined;
    posix.sigaction(.TERM, null, &after);
    try std.testing.expectEqual(old.handler.handler, after.handler.handler);
    try std.testing.expectEqual(old.flags, after.flags);
    try std.testing.expectEqual(old.mask, after.mask);
}
