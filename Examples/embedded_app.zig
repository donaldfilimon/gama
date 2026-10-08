//! Shared caller-bounded embedded workload, also executed by native tests.
const std = @import("std");
const g = @import("gama");
const App = struct {
    state: ?g.StateRef(u32) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "embedded", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.state = try ctx.state(u32, 0, 1);
        return .{ .text = .{ .content = if ((try self.state.?.read()).* == 1) "first" else "second" } };
    }
};
/// Run two publications and a clean poll entirely within caller storage.
/// The freestanding entry supplies 64 KiB; smaller buffers fail explicitly.
pub fn run(memory: []u8) i32 {
    var fixed = std.heap.FixedBufferAllocator.init(memory);
    var app: App = .{};
    const host = g.Host(App).create(fixed.allocator(), &app) catch return -1;
    defer host.destroy() catch {};
    host.handle(.{ .resize = .{ .width = 8, .height = 2 } }) catch return -2;
    var pump = g.DrawingPump(App).init(fixed.allocator(), host, .draw_list) catch return -3;
    defer pump.deinit();
    const first = pump.advance() catch return -4;
    if (!first.produced) return -5;
    app.state.?.set(2) catch return -6;
    const second = pump.advance() catch return -7;
    if (!second.produced) return -8;
    const clean = pump.advance() catch return -9;
    if (clean.produced) return -10;
    return @intCast((host.currentOutput() catch return -11).len);
}

test "same embedded workload publishes two frames then settles within caller arena" {
    var storage: [65536]u8 = undefined;
    try std.testing.expect(run(&storage) > 0);
}
test "embedded workload reports allocation failure from exhausted caller storage" {
    var storage: [32]u8 = undefined;
    try std.testing.expectEqual(@as(i32, -1), run(&storage));
}
