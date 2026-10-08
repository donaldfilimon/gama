const std = @import("std");
const g = @import("gama");
const EmptyApp = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
        return .empty;
    }
};
test "C baseline oversized dimensions serialize a zero-size grid" {
    var app: EmptyApp = .{};
    const host = try g.Host(EmptyApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    var drawing = try g.DrawingPump(EmptyApp).init(std.testing.allocator, host, .draw_list);
    defer drawing.deinit();
    try host.handle(.{ .resize = .{ .width = std.math.maxInt(i32), .height = std.math.maxInt(i32) } });
    _ = try drawing.advanceNormalized({}, Sink.accept);
    const bytes = try host.currentOutput();
    try std.testing.expectEqual(@as(usize, 20), bytes.len);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, bytes[8..12], .little));
}

const Sink = struct {
    fn accept(_: void, _: []const u8) g.Error!void {}
};
const a = std.testing.allocator;
const Context = g.abi.Context;
const c = g.abi.c;
const initial = @embedFile("parity/swift-baseline/c-embed-initial.gama");
const increment = @embedFile("parity/swift-baseline/c-embed-increment.gama");
test "diagnostic shared host direct Enter exact C goldens and clean borrow" {
    const ctx = try Context.create(a, 24, 6);
    defer ctx.destroy() catch unreachable;
    try std.testing.expect(try ctx.needsFrame());
    try ctx.key(5, -1, 0, 0); // no registered target before first frame
    try std.testing.expectEqualSlices(u8, initial, (try ctx.frame(true)).?);
    const copied = try a.dupe(u8, (try ctx.host.currentOutput()));
    defer a.free(copied);
    try std.testing.expect(!(try ctx.needsFrame()));
    try std.testing.expectEqual(@as(?[]const u8, null), try ctx.frame(true));
    try ctx.key(5, -1, -1, -1);
    try std.testing.expectEqualSlices(u8, increment, (try ctx.frame(true)).?);
    try std.testing.expectEqualSlices(u8, initial, copied);
    try std.testing.expectEqual(@as(?[]const u8, null), try ctx.frame(true));
}
test "C null precedence nullable length exact mapping dimensions and pointer behavior" {
    try std.testing.expectEqual(@as(i32, 1), c.gama_embed_v1_abi_version());
    try std.testing.expectEqual(@as(i32, -1), c.gama_embed_v1_key(null, -1, -1, 0, 0));
    try std.testing.expectEqual(@as(i32, -1), c.gama_embed_v1_pointer(null, 0, 0, 1));
    try std.testing.expectEqual(@as(i32, -1), c.gama_embed_v1_resize(null, 0, 0));
    try std.testing.expectEqual(@as(i32, -1), c.gama_embed_v1_needs_frame(null));
    var n: i32 = 9;
    try std.testing.expect(c.gama_embed_v1_frame(null, &n) == null);
    try std.testing.expectEqual(@as(i32, -1), n);
    try std.testing.expect(c.gama_embed_v1_frame(null, null) == null);
    c.gama_embed_v1_context_destroy(null);
    const ctx = try Context.create(a, 24, 6);
    defer ctx.destroy() catch unreachable;
    try std.testing.expect(c.gama_embed_v1_frame(ctx, null) != null);
    try std.testing.expect(c.gama_embed_v1_frame(ctx, &n) == null);
    try std.testing.expectEqual(@as(i32, 0), n);
    try std.testing.expectEqual(@as(i32, -2), c.gama_embed_v1_key(ctx, 99, 0, 0, 0));
    for ([_]i32{ -1, 0xd800, 0xdfff, 0x110000 }) |cp| try std.testing.expectEqual(@as(i32, -2), c.gama_embed_v1_key(ctx, 0, cp, 0, 0));
    for ([_]i32{ 0, 0xffff, 0x10ffff, 'x' }) |cp| try std.testing.expectEqual(@as(i32, 0), c.gama_embed_v1_key(ctx, 0, cp, 0, 0));
    try std.testing.expect(!(try ctx.needsFrame()));
    for ([_][3]i32{ .{ -1, 1, 1 }, .{ 11, 1, 1 }, .{ 1, 0, 1 }, .{ 1, 1, 0 } }) |v| {
        try ctx.pointer(v[0], v[1], v[2]);
        try std.testing.expect(!(try ctx.needsFrame()));
    }
    try ctx.pointer(0, 1, -99);
    try std.testing.expectEqualSlices(u8, increment, (try ctx.frame(true)).?);
    try ctx.resize(std.math.maxInt(i32), std.math.maxInt(i32));
    const empty = (try ctx.frame(true)).?;
    try std.testing.expectEqual(@as(usize, 20), empty.len);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, empty[8..]);
    try std.testing.expect(!(try ctx.needsFrame()));
    try std.testing.expectEqual(@as(?[]const u8, null), try ctx.frame(true));
    try ctx.resize(24, 6);
    try std.testing.expectEqualSlices(u8, increment, (try ctx.frame(true)).?);
    try ctx.resize(-1, 0);
    const clamped = (try ctx.frame(true)).?;
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, clamped[8..12], .little));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, clamped[12..16], .little));
}
test "decoder modifiers full Unicode controls code ranges and scalar-only validation" {
    inline for (.{ 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13 }, .{ g.Key.up, g.Key.down, g.Key.left, g.Key.right, g.Key.enter, g.Key.escape, g.Key.backspace, g.Key.delete, g.Key.home, g.Key.end, g.Key.page_up, g.Key.page_down }) |code, key| {
        var decoded = try g.abi.input.decode(code, -1, -1, -1);
        try std.testing.expectEqual(@as(std.meta.Tag(g.Key), key), std.meta.activeTag(decoded.key().?));
    }
    for (100..113) |code| {
        var decoded = try g.abi.input.decode(@intCast(code), -1, 0, 0);
        try std.testing.expectEqual(@as(u8, @intCast(code - 99)), decoded.key().?.function);
    }
    for ([_]i32{ -1, 14, 99, 113, std.math.maxInt(i32) }) |code| try std.testing.expectError(error.InvalidCharacter, g.abi.input.decode(code, 0, 0, 0));
    var shifted = try g.abi.input.decode(7, -1, std.math.minInt(i32), 0);
    try std.testing.expect(shifted.key().? == .back_tab);
    var capital = try g.abi.input.decode(0, 'Q', 0, -9);
    try std.testing.expectEqual(@as(u21, 'q'), capital.key().?.shortcut.codepoint);
    var space = try g.abi.input.decode(0, ' ', 0, -1);
    try std.testing.expectEqualStrings(" ", space.key().?.character);
    var greek = try g.abi.input.decode(0, 0x03a3, 0, 1);
    try std.testing.expectEqual(@as(u21, 0x03c3), greek.key().?.shortcut.codepoint);
    var dotted = try g.abi.input.decode(0, 0x0130, 0, 1);
    try std.testing.expectEqualStrings("i\u{307}", dotted.bytes[0..dotted.len]);
    try std.testing.expect(dotted.key() == null);
}
fn allocations(a_: std.mem.Allocator) !void {
    const ctx = try Context.create(a_, 24, 6);
    defer ctx.destroy() catch unreachable;
    _ = try ctx.frame(true);
    try ctx.key(5, 0, 0, 0);
    _ = try ctx.frame(true);
    try ctx.resize(std.math.maxInt(i32), std.math.maxInt(i32));
    _ = try ctx.frame(true);
}
test "every allocation failure cleans context Signal Host raster and candidate" {
    try std.testing.checkAllAllocationFailures(a, allocations, .{});
}
test "C OOM length leaves prior publication planes and dirty retry" {
    var failing = std.testing.FailingAllocator.init(a, .{});
    const ctx = try Context.create(failing.allocator(), 24, 6);
    defer ctx.destroy() catch unreachable;
    _ = try ctx.frame(true);
    try ctx.key(5, 0, 0, 0);
    const old_ptr = (try ctx.host.currentOutput()).ptr;
    failing.fail_index = failing.alloc_index;
    var n: i32 = 0;
    try std.testing.expect(c.gama_embed_v1_frame(ctx, &n) == null);
    try std.testing.expectEqual(@as(i32, -4), n);
    try std.testing.expect(try ctx.needsFrame());
    try std.testing.expectEqual(old_ptr, (try ctx.host.currentOutput()).ptr);
    try std.testing.expectEqualSlices(u8, initial, try ctx.host.currentOutput());
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqualSlices(u8, increment, (try ctx.frame(true)).?);
    try std.testing.expectError(error.FrameTooLarge, g.abi.admitLength(@as(usize, std.math.maxInt(i32)) + 1));
    try g.abi.admitLength(std.math.maxInt(i32));
}
test "installed pull failures preserve host publication clean state and accepted model" {
    var pull: g.abi.Pull = .{};
    defer pull.shutdown();
    try std.testing.expectEqual(@as(i32, -1), pull.frame());
    try std.testing.expectEqual(@as(i32, -1), pull.key(-1, -1, 0, 0));
    try std.testing.expectEqual(@as(i32, 0), pull.init(a, 24, 6));
    try std.testing.expectEqual(@as(i32, 1), pull.frame());
    try std.testing.expectEqualSlices(u8, initial, pull.bytes);
    const prior = pull.context.?;
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectEqual(@as(i32, -4), pull.init(failing.allocator(), 1, 1));
    try std.testing.expectEqual(prior, pull.context.?);
    try std.testing.expectEqual(@as(usize, 0), pull.bytes.len);
    try std.testing.expectEqual(@as(i32, 0), pull.frame());
    try std.testing.expectEqual(@as(i32, 0), pull.key(5, 0, 0, 0));
    try std.testing.expectEqual(@as(i32, 1), pull.frame());
    try std.testing.expectEqualSlices(u8, increment, pull.bytes);
    try std.testing.expectEqual(@as(i32, 0), pull.resize(std.math.maxInt(i32), std.math.maxInt(i32)));
    try std.testing.expectEqual(@as(i32, -3), pull.frame());
    try std.testing.expectEqual(@as(usize, 0), pull.bytes.len);
    try std.testing.expectEqualSlices(u8, increment, try prior.host.currentOutput());
    try std.testing.expectEqual(@as(i32, 1), pull.needsFrame());
    try std.testing.expectEqual(@as(i32, 0), pull.resize(24, 6));
    try std.testing.expectEqual(@as(i32, 1), pull.frame());
    try std.testing.expectEqualSlices(u8, increment, pull.bytes);
    try std.testing.expectEqual(@as(i32, 0), pull.init(a, 24, 6));
    try std.testing.expectEqual(@as(i32, 1), pull.frame());
    try std.testing.expectEqualSlices(u8, initial, pull.bytes);
    pull.shutdown();
    pull.shutdown();
    try std.testing.expectEqual(@as(i32, -1), pull.needsFrame());
}
test "native executor and reentry reject mutation and destroy" {
    const ctx = try Context.create(a, 24, 6);
    defer ctx.destroy() catch unreachable;
    const Wrong = struct {
        fn run(value: *Context) void {
            std.testing.expectEqual(@as(i32, -1), c.gama_embed_v1_key(value, 5, 0, 0, 0)) catch @panic("wrong-thread key");
            std.testing.expectEqual(@as(i32, -1), c.gama_embed_v1_needs_frame(value)) catch @panic("wrong-thread query");
            c.gama_embed_v1_context_destroy(value);
        }
    };
    const thread = try std.Thread.spawn(.{}, Wrong.run, .{ctx});
    thread.join();
    ctx.busy = true;
    try std.testing.expectEqual(@as(i32, -1), c.gama_embed_v1_resize(ctx, 1, 1));
    var n: i32 = 0;
    try std.testing.expect(c.gama_embed_v1_frame(ctx, &n) == null);
    try std.testing.expectEqual(@as(i32, -1), n);
    c.gama_embed_v1_context_destroy(ctx);
    ctx.busy = false;
    try std.testing.expectEqualSlices(u8, initial, (try ctx.frame(true)).?);
}
test "every staged rendering OOM retains old frame and retries accepted model including normalized C grid" {
    for ([_]bool{ false, true }) |oversized| {
        var failures: usize = 0;
        for (0..256) |offset| {
            var failing = std.testing.FailingAllocator.init(a, .{});
            const ctx = try Context.create(failing.allocator(), 24, 6);
            defer ctx.destroy() catch unreachable;
            _ = try ctx.frame(true);
            try ctx.key(5, 0, 0, 0);
            if (oversized) try ctx.resize(std.math.maxInt(i32), std.math.maxInt(i32));
            failing.fail_index = failing.alloc_index + offset;
            const result = ctx.frame(true);
            if (result) |_| {
                try std.testing.expect(failures > 0);
                std.debug.print("render OOM rollback sweep (normalized={any}): {d} allocation failures\n", .{ oversized, failures });
                break;
            } else |err| {
                try std.testing.expectEqual(error.OutOfMemory, err);
                failures += 1;
                try std.testing.expect(try ctx.needsFrame());
                try std.testing.expectEqualSlices(u8, initial, try ctx.host.currentOutput());
                try std.testing.expectEqual(@as(i64, 24), ctx.drawing.buffer.size.width);
                try std.testing.expectEqual(@as(u64, 1), (try ctx.app.count.read()).*);
                failing.fail_index = std.math.maxInt(usize);
                const retry = (try ctx.frame(true)).?;
                if (oversized) try std.testing.expectEqual(@as(usize, 20), retry.len) else try std.testing.expectEqualSlices(u8, increment, retry);
            }
            if (offset == 255) return error.UnboundedAllocationSweep;
        }
    }
}
test "each failed replacement allocation preserves installed owner and C creation returns null" {
    var pull: g.abi.Pull = .{};
    defer pull.shutdown();
    try std.testing.expectEqual(@as(i32, 0), pull.init(a, 24, 6));
    try std.testing.expectEqual(@as(i32, 1), pull.frame());
    const prior = pull.context.?;
    var failures: usize = 0;
    for (0..128) |offset| {
        var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = offset });
        const code = pull.init(failing.allocator(), 24, 6);
        if (code == 0) {
            // Allocator state must outlive its context; remove before loop-local storage dies.
            pull.shutdown();
            try std.testing.expect(failures > 3);
            break;
        }
        try std.testing.expectEqual(@as(i32, -4), code);
        failures += 1;
        try std.testing.expectEqual(prior, pull.context.?);
        try std.testing.expectEqualSlices(u8, initial, try prior.host.currentOutput());
        try std.testing.expectEqual(@as(i32, 0), pull.needsFrame());
        if (offset == 127) return error.UnboundedAllocationSweep;
    }
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expect(c.create(failing.allocator(), 24, 6) == null);
}
test "actual signal callback cannot reenter adapter frame input resize or destroy" {
    const ctx = try Context.create(a, 24, 6);
    defer ctx.destroy() catch unreachable;
    _ = try ctx.frame(true);
    const Observer = struct {
        fn callback(raw: *const anyopaque, _: g.SignalRef(u64)) g.Error!void {
            const owner: *Context = @ptrCast(@alignCast(@constCast(raw)));
            if (c.gama_embed_v1_key(owner, 5, 0, 0, 0) != -1) return error.Unavailable;
            if (c.gama_embed_v1_resize(owner, 1, 1) != -1) return error.Unavailable;
            var n: i32 = 0;
            if (c.gama_embed_v1_frame(owner, &n) != null or n != -1) return error.Unavailable;
            c.gama_embed_v1_context_destroy(owner);
        }
    };
    _ = try ctx.app.count.observeOwner(ctx, Observer.callback);
    try ctx.key(5, 0, 0, 0);
    try std.testing.expectEqualSlices(u8, increment, (try ctx.frame(true)).?);
}
test "frozen structured C statuses retain post-consumption dirty meaning" {
    const fixture = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/embed-statuses.json"), .{});
    defer fixture.deinit();
    const expected = fixture.value.object;
    const ctx = try Context.create(a, 24, 6);
    defer ctx.destroy() catch unreachable;
    var initial_len: i32 = 0;
    _ = c.gama_embed_v1_frame(ctx, &initial_len);
    var initial_clean: i32 = -99;
    _ = c.gama_embed_v1_frame(ctx, &initial_clean);
    const initial_dirty = c.gama_embed_v1_needs_frame(ctx);
    const enter = c.gama_embed_v1_key(ctx, 5, 0, 0, 0);
    var increment_len: i32 = 0;
    _ = c.gama_embed_v1_frame(ctx, &increment_len);
    var increment_clean: i32 = -99;
    _ = c.gama_embed_v1_frame(ctx, &increment_clean);
    const actual = .{ .abi = c.gama_embed_v1_abi_version(), .enter = enter, .initialLength = initial_len, .incrementLength = increment_len, .initialCleanLength = initial_clean, .incrementCleanLength = increment_clean, .initialDirty = initial_dirty, .incrementDirty = c.gama_embed_v1_needs_frame(ctx), .invalidKey = c.gama_embed_v1_key(ctx, 999, 0, 0, 0), .nullKey = c.gama_embed_v1_key(null, 5, 0, 0, 0) };
    inline for (@typeInfo(@TypeOf(actual)).@"struct".field_names) |name| try std.testing.expectEqual(expected.get(name).?.integer, @as(i64, @field(actual, name)));
}
