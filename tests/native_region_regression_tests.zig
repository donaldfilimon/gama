const std = @import("std");
const g = @import("gama");
const App = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        const children = try ctx.allocator.alloc(g.Node, 2);
        for (children, 0..) |*child, i| {
            const id = ctx.id.child(@intCast(i));
            try ctx.register(.{ .native_region = .{ .id = id, .region_id = "old" } });
            try ctx.register(.{ .native_region = .{ .id = id, .region_id = "same" } });
            child.* = .{ .interactive = .{ .id = id, .focusable = false, .child = try ctx.box(.{ .spacer = 1 }) } };
        }
        return .{ .stack = .{ .axis = .horizontal, .alignment = .top_leading, .children = children } };
    }
};
test "M1 latest NodeID registration and last visual region are the sole publication" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{ .width = 2, .height = 1 });
    const regions = try host.nativeRegions();
    try std.testing.expectEqual(@as(usize, 1), regions.len);
    try std.testing.expectEqualStrings("same", regions[0].region_id);
    try std.testing.expectEqual(g.NodeID.root.child(1), regions[0].id);
    try std.testing.expectEqual(@as(i64, 1), regions[0].frame.origin.x);
}
