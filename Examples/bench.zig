//! Retained portable benchmark; dispatch and explicit invalidation precede timing.
const std = @import("std");
const g = @import("gama");
const v = g.authoring;
const App = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn noop(_: *const u8, _: *anyopaque) g.Error!void {}
    fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        const action = try ctx.action(@as(u8, 0), noop);
        const content = v.vStack(v.tuple(.{
            v.foregroundColor((v.Text{ .content = "Gama benchmark surface" }).bold(), g.rgb("#c8dcff")),
            v.hStack(v.tuple(.{
                v.border(v.vStack(v.tuple(.{
                    v.foregroundColor(v.Text{ .content = "alpha" }, g.rgb("#ff5050")),
                    v.foregroundColor(v.Text{ .content = "bravo" }, g.rgb("#50ff50")),
                    v.foregroundColor(v.Text{ .content = "charlie" }, g.rgb("#5050ff")),
                    (v.Text{ .content = "delta" }).italic(),
                    (v.Text{ .content = "echo" }).underline(),
                }), .{}), .{ .style = .rounded, .title = "left" }),
                v.border(v.vStack(v.tuple(.{
                    try v.buttonTitle(ctx, "First action", action),                           try v.buttonTitle(ctx, "Second action", action), try v.buttonTitle(ctx, "Third action", action),
                    v.foregroundColor(v.Text{ .content = "status: idle" }, g.rgb("#787878")),
                }), .{}), .{ .title = "right" }),
            }), .{ .spacing = 1 }),
            v.background(v.Text{ .content = "footer row with a longer stretch of plain text to merge" }, g.rgb("#141428")),
        }), .{});
        return content.render(ctx);
    }
};
const events = [_]g.Event{ .{ .key = .tab }, .{ .key = .tab }, .{ .key = .enter }, .{ .pointer = .{ .x = 12, .y = 4 } }, .pointer_release, .{ .key = .back_tab }, .{ .key = .{ .character = "x" } }, .{ .key = .escape } };
const names = [_][]const u8{ "paint (pump + clearBack + CellPainter)", "forEachRun via DrawList.from (80x24)", "presentDiff (ANSI diff, 80x24)", "resize loop (80x24 <-> 160x48, painted)" };
fn elapsed(io: std.Io, start: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
}
fn paint(host: *g.Host(App), buffer: *g.draw.CellBuffer, size: g.geometry.Size) !void {
    const frame = (try host.prepare(size)) orelse return error.ExpectedDirtyFrame;
    errdefer frame.abort() catch {};
    buffer.clearBack();
    try g.draw.paint(buffer, (try frame.tree()).*);
    try frame.commit();
}
const Summary = struct { median: u64, p95: u64 };
fn summarize(samples: []u64) Summary {
    if (samples.len == 0) return .{ .median = 0, .p95 = 0 };
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    return .{ .median = samples[samples.len / 2], .p95 = samples[(samples.len * 95 + 99) / 100 - 1] };
}
test "benchmark uses upper-middle median and nearest-rank p95" {
    var values = [_]u64{ 4, 1, 3, 2 };
    const result = summarize(&values);
    try std.testing.expectEqual(@as(u64, 3), result.median);
    try std.testing.expectEqual(@as(u64, 4), result.p95);
    var twenty: [20]u64 = undefined;
    for (&twenty, 0..) |*value, index| value.* = 20 - index;
    try std.testing.expectEqual(@as(u64, 19), summarize(&twenty).p95);
}
test "benchmark retains exact script and initial pointer semantics" {
    try std.testing.expectEqual(@as(usize, 8), events.len);
    try std.testing.expectEqual(g.Key.tab, events[0].key);
    try std.testing.expectEqual(g.Key.tab, events[1].key);
    try std.testing.expectEqual(g.geometry.Point{ .x = 12, .y = 4 }, events[3].pointer);
    try std.testing.expect(events[4] == .pointer_release);
}
pub fn main(init: std.process.Init) !void {
    const a = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var runs: usize = 5;
    var frames: usize = 2000;
    var warmup: usize = 200;
    var i: usize = 1;
    while (i < args.len) : (i += 2) {
        if (i + 1 >= args.len) return error.MissingValue;
        const n = try std.fmt.parseInt(usize, args[i + 1], 10);
        if (std.mem.eql(u8, args[i], "--runs")) {
            if (n == 0 or n > 100) return error.InvalidLimit;
            runs = n;
        } else if (std.mem.eql(u8, args[i], "--frames")) {
            if (n == 0 or n > 100000) return error.InvalidLimit;
            frames = n;
        } else if (std.mem.eql(u8, args[i], "--warmup")) {
            if (n > 100000) return error.InvalidLimit;
            warmup = n;
        } else return error.UnknownArgument;
    }
    var samples: [4]std.ArrayList(u64) = @splat(.empty);
    defer for (&samples) |*s| s.deinit(a);
    var output = std.Io.File.stdout().writer(io, &.{});
    try output.interface.print("Portable benchmark runs={d} frames={d} warmup={d}; 80x24 / 160x48; color depth unknown\n", .{ runs, frames, warmup });
    var expected: ?u64 = null;
    for (0..runs) |run| {
        var app: App = .{};
        const host = try g.Host(App).create(a, &app);
        defer host.destroy() catch unreachable;
        var buffer = try g.draw.CellBuffer.init(a, .{ .width = 80, .height = 24 });
        defer buffer.deinit();
        try host.handle(.{ .lifecycle = .{ .kind = .did_launch } });
        var digest = std.hash.Fnv1a_64.init();
        for (0..warmup + frames) |frame_index| {
            try host.handle(events[frame_index % events.len]);
            try host.invalidate();
            var start = std.Io.Clock.awake.now(io);
            try paint(host, &buffer, .{ .width = 80, .height = 24 });
            const paint_ns = elapsed(io, start);
            start = std.Io.Clock.awake.now(io);
            var list = try g.draw.DrawList.from(a, &buffer);
            const vector_ns = elapsed(io, start);
            defer list.deinit();
            std.mem.doNotOptimizeAway(list.commands.len);
            start = std.Io.Clock.awake.now(io);
            const ansi = try g.draw.AnsiPresenter.present(a, &buffer);
            const diff_ns = elapsed(io, start);
            defer a.free(ansi);
            std.mem.doNotOptimizeAway(ansi.len);
            // Added content digest is outside all retained timed phases.
            const wire = try list.encode(a);
            defer a.free(wire);
            digest.update(wire);
            digest.update(ansi);
            if (frame_index >= warmup) {
                try samples[0].append(a, paint_ns);
                try samples[1].append(a, vector_ns);
                try samples[2].append(a, diff_ns);
            }
        }
        for (0..@max(1, frames / 20)) |resize_index| {
            const size: g.geometry.Size = if (resize_index % 2 == 0) .{ .width = 160, .height = 48 } else .{ .width = 80, .height = 24 };
            try host.invalidate();
            const start = std.Io.Clock.awake.now(io);
            try buffer.resizeIfNeeded(size);
            try paint(host, &buffer, size);
            const ansi = try g.draw.AnsiPresenter.present(a, &buffer);
            std.mem.doNotOptimizeAway(ansi.len);
            const ns = elapsed(io, start);
            defer a.free(ansi);
            digest.update(ansi);
            try samples[3].append(a, ns);
        }
        const hash = digest.final();
        if (expected) |want| {
            if (hash != want) return error.NondeterministicOutput;
        } else expected = hash;
        try output.interface.print("DIGEST\t{d}\t{x}\n", .{ run, hash });
        try host.handle(.{ .lifecycle = .{ .kind = .will_terminate } });
    }
    for (&samples, names) |*s, name| {
        const stats = summarize(s.items);
        const n = s.items.len;
        try output.interface.print("BENCH\t{s}\t{d}\t{d}\t{d}\n", .{ name, n, stats.median, stats.p95 });
    }
    try output.interface.writeAll("Memory: framework allocations inside phases; harness samples/digest outside; no process RSS comparison.\n");
}
