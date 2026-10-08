const std = @import("std");
const g = @import("gama");
const geo = g.geometry;
const a = std.testing.allocator;

test "sequential ceiling remainder preserves 4 3 3 and 4 4 3" {
    var storage = g.FrameStorage.init(a);
    defer storage.deinit();
    const children = [_]g.Node{ .{ .spacer = 0 }, .{ .spacer = 0 }, .{ .spacer = 0 } };
    const node: g.Node = .{ .stack = .{ .axis = .horizontal, .alignment = .top_leading, .children = &children } };
    for ([_]i64{ 10, 11 }, [_][3]i64{ .{ 4, 3, 3 }, .{ 4, 4, 3 } }) |width, expected| {
        const laid = try g.layout.place(storage.arena.allocator(), node, .{ .size = .{ .width = width, .height = 2 } }, .{});
        var x: i64 = 0;
        for (laid.children, expected) |child, w| {
            try std.testing.expectEqual(w, child.frame.size.width);
            try std.testing.expectEqual(x, child.frame.origin.x);
            x += w;
        }
    }
}

fn compareTree(tree: g.layout.LaidNode, json: std.json.Value) !void {
    const object = json.object;
    try std.testing.expectEqualStrings(object.get("kind").?.string, @tagName(tree.node));
    const frame = object.get("frame").?.array.items;
    const rect = [_]i64{ tree.frame.origin.x, tree.frame.origin.y, tree.frame.size.width, tree.frame.size.height };
    for (rect, frame) |actual, expected| try std.testing.expectEqual(expected.integer, actual);
    if (object.get("text")) |value| try std.testing.expectEqualStrings(value.string, tree.node.text.content);
    if (object.get("id")) |value| try std.testing.expectEqual(try std.fmt.parseInt(u64, value.string, 10), tree.node.interactive.id.raw);
    if (object.get("focusable")) |value| try std.testing.expectEqual(value.bool, tree.node.interactive.focusable);
    const children = object.get("children").?.array.items;
    try std.testing.expectEqual(children.len, tree.children.len);
    for (tree.children, children) |child, expected| try compareTree(child, expected);
}
fn fixtureNode(ctx: *g.BuildContext) !g.Node {
    const row = [_]g.Node{ .{ .text = .{ .content = "x" } }, .{ .spacer = 1 }, .{ .text = .{ .content = "end" } } };
    const column = [_]g.Node{ .{ .text = .{ .content = "A<&中", .style = .{ .attributes = g.style.Attributes.bold } } }, .{ .stack = .{ .axis = .horizontal, .spacing = 1, .alignment = .top_leading, .children = &row } } };
    return ctx.retain(.{ .border = .{ .style = .rounded, .title = "T", .text_style = .{ .foreground = .red }, .child = &.{ .padding = .{ .insets = .{ .top = 1, .leading = 1, .bottom = 1, .trailing = 1 }, .child = &.{ .stack = .{ .axis = .vertical, .spacing = 1, .alignment = .top_leading, .children = &column } } } } } });
}
test "independent frozen Swift layout corpus exact kinds text and every rectangle" {
    inline for (.{ .{ @embedFile("parity/swift-baseline/layout-16x8.json"), 16, 8 }, .{ @embedFile("parity/swift-baseline/layout-9x5.json"), 9, 5 } }) |fixture| {
        var storage = g.FrameStorage.init(a);
        defer storage.deinit();
        var ctx = storage.context();
        const node = try fixtureNode(&ctx);
        const tree = try g.layout.place(ctx.allocator, node, .{ .size = .{ .width = fixture[1], .height = fixture[2] } }, .{});
        const json = try std.json.parseFromSlice(std.json.Value, a, fixture[0], .{});
        defer json.deinit();
        try compareTree(tree, json.value.object.get("tree").?);
    }
}
test "per-axis flex fixed mask floors divider direct shortcut and overflow remain exact" {
    var storage = g.FrameStorage.init(a);
    defer storage.deinit();
    const alloc = storage.arena.allocator();
    const text: g.Node = .{ .text = .{ .content = "abcdefgh" } };
    const children = [_]g.Node{ text, .{ .spacer = 4 } };
    const stack: g.Node = .{ .stack = .{ .axis = .horizontal, .alignment = .top_leading, .children = &children } };
    const laid = try g.layout.place(alloc, stack, .{ .size = .{ .width = 10, .height = 2 } }, .{});
    try std.testing.expectEqual(@as(i64, 8), laid.children[1].frame.origin.x);
    try std.testing.expectEqual(@as(i64, 4), laid.children[1].frame.size.width);
    const flex: g.Node = .{ .flex_frame = .{ .max_width = std.math.maxInt(i64), .child = &text } };
    try std.testing.expectEqual(@as(u8, 0), flex.flexPriority(.vertical));
    try std.testing.expectEqual(@as(u8, 1), flex.flexPriority(.horizontal));
    const mask: g.Node = .{ .frame = .{ .child = &flex } };
    try std.testing.expectEqual(@as(u8, 0), mask.flexPriority(.horizontal));
    const divider: g.Node = .{ .divider = .{} };
    const row = [_]g.Node{ divider, .{ .styled = .{ .style = .plain, .child = &divider } } };
    const direct = try g.layout.place(alloc, .{ .stack = .{ .axis = .horizontal, .alignment = .top_leading, .children = &row } }, .{ .size = .{ .width = 10, .height = 6 } }, .{});
    try std.testing.expectEqual(@as(?geo.Axis, .horizontal), direct.children[0].node.divider.axis);
    try std.testing.expectEqual(@as(i64, 6), direct.children[0].frame.size.height);
    try std.testing.expectEqual(@as(?geo.Axis, null), direct.children[1].children[0].node.divider.axis);
    try std.testing.expectEqual(@as(i64, 1), direct.children[1].frame.size.height);
}
test "portable metrics convert edges independently and maximum sentinel bypasses units" {
    const Provider = struct {
        fn units(_: ?*const anyopaque, n: i64, axis: geo.Axis) i64 {
            return n *| n *| (if (axis == .horizontal) @as(i64, 2) else 3);
        }
        fn control(_: ?*const anyopaque, _: g.NodeID, _: geo.ProposedSize) ?geo.Size {
            return .{ .width = 7, .height = 4 };
        }
        fn text(_: ?*const anyopaque, _: std.mem.Allocator, _: []const u8, _: g.TextStyle, _: ?i64) g.Error!geo.Size {
            return .{ .width = 4, .height = 5 };
        }
    };
    const m: g.layout.Metrics = .{ .units_fn = Provider.units, .text_fn = Provider.text, .control_fn = Provider.control, .divider_thickness = 3 };
    const empty: g.Node = .empty;
    const padding: g.Node = .{ .padding = .{ .insets = .{ .leading = 1, .trailing = 2, .top = 1, .bottom = 2 }, .child = &empty } };
    try std.testing.expectEqual(geo.Size{ .width = 10, .height = 15 }, try g.layout.measure(a, padding, .{}, m));
    const text: g.Node = .{ .text = .{ .content = "ignored" } };
    try std.testing.expectEqual(geo.Size{ .width = 4, .height = 5 }, try g.layout.measure(a, text, .{}, m));
    const flex: g.Node = .{ .flex_frame = .{ .min_width = 3, .max_width = 2, .max_height = std.math.maxInt(i64), .child = &empty } };
    try std.testing.expectEqual(geo.Size{ .width = 18, .height = 11 }, try g.layout.measure(a, flex, .{ .height = 11 }, m));
    const control: g.Node = .{ .interactive = .{ .id = .root, .focusable = true, .child = &.{ .spacer = 0 } } };
    var storage = g.FrameStorage.init(a);
    defer storage.deinit();
    const laid = try g.layout.place(storage.arena.allocator(), .{ .stack = .{ .axis = .horizontal, .alignment = .top_leading, .spacing = 1, .children = &.{ control, .{ .spacer = 0 } } } }, .{ .size = .{ .width = 15, .height = 9 } }, m);
    try std.testing.expectEqual(@as(i64, 10), laid.children[0].frame.size.width);
    try std.testing.expectEqual(@as(i64, 3), laid.children[1].frame.size.width);
}
test "fixed and flex frames align independently group becomes leading overlay" {
    var storage = g.FrameStorage.init(a);
    defer storage.deinit();
    const alloc = storage.arena.allocator();
    const text: g.Node = .{ .text = .{ .content = "xx" } };
    const fixed: g.Node = .{ .frame = .{ .width = 6, .height = 4, .child = &text } };
    const tree = try g.layout.place(alloc, fixed, .{ .origin = .{ .x = 2, .y = 3 }, .size = .{ .width = 10, .height = 8 } }, .{});
    try std.testing.expectEqual(geo.Rect{ .origin = .{ .x = 4, .y = 5 }, .size = .{ .width = 6, .height = 4 } }, tree.frame);
    try std.testing.expectEqual(geo.Rect{ .origin = .{ .x = 6, .y = 6 }, .size = .{ .width = 2, .height = 1 } }, tree.children[0].frame);
    const grouped = try g.layout.place(alloc, .{ .group = &.{text} }, .{ .size = .{ .width = 10, .height = 8 } }, .{});
    try std.testing.expect(grouped.node == .overlay);
    try std.testing.expectEqual(geo.Point{}, grouped.children[0].frame.origin);
    const overlay = try g.layout.place(alloc, .{ .overlay = .{ .children = &.{text}, .alignment = .bottom_trailing } }, .{ .size = .{ .width = 10, .height = 8 } }, .{});
    try std.testing.expectEqual(geo.Point{ .x = 8, .y = 7 }, overlay.children[0].frame.origin);
}
test "negative spacing inset and extreme arithmetic bounded without compressing ordinary geometry" {
    var storage = g.FrameStorage.init(a);
    defer storage.deinit();
    const alloc = storage.arena.allocator();
    const row: g.Node = .{ .stack = .{ .axis = .horizontal, .spacing = -2, .alignment = .top_leading, .children = &.{ .{ .spacer = 3 }, .{ .spacer = 3 } } } };
    const laid = try g.layout.place(alloc, row, .{ .size = .{ .width = 2, .height = 1 } }, .{});
    try std.testing.expectEqual(@as(i64, 1), laid.children[1].frame.origin.x);
    const min = std.math.minInt(i64);
    const max = std.math.maxInt(i64);
    const hostile: g.Node = .{ .padding = .{ .insets = .{ .leading = min, .trailing = min, .top = max, .bottom = max }, .child = &.{ .stack = .{ .axis = .horizontal, .spacing = max, .alignment = .bottom_trailing, .children = &.{ .{ .spacer = max }, .{ .spacer = max }, .{ .spacer = min } } } } } };
    _ = try g.layout.measure(alloc, hostile, .{ .width = min, .height = max }, .{});
    const result = try g.layout.place(alloc, hostile, .{ .origin = .{ .x = max, .y = min }, .size = .{ .width = max, .height = max } }, .{});
    try std.testing.expectEqual(@as(i64, max), result.children[0].frame.size.width);
    try std.testing.expectEqual(@as(i64, 0), result.children[0].frame.size.height);
}
fn layoutOOM(allocator: std.mem.Allocator) !void {
    var storage = g.FrameStorage.init(allocator);
    defer storage.deinit();
    var ctx = storage.context();
    const node = try fixtureNode(&ctx);
    _ = try g.layout.measure(ctx.allocator, node, .{ .width = 9, .height = 5 }, .{});
    _ = try g.layout.place(ctx.allocator, node, .{ .size = .{ .width = 9, .height = 5 } }, .{});
}
test "measurement and placement OOM reclaims complete candidate arena" {
    try std.testing.checkAllAllocationFailures(a, layoutOOM, .{});
}
