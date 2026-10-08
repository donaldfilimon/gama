const std = @import("std");
const g = @import("gama");
const a = std.testing.allocator;
test "MLIR escaping matches immutable baseline" {
    const bytes = try g.mlir.lower(a, .{ .text = .{ .content = "q:\" b:\\ n:\n t:\t end" } }, "parity");
    defer a.free(bytes);
    try std.testing.expectEqualStrings(@embedFile("parity/swift-baseline/escaping.mlir"), bytes);
}
fn fixtureNode(ctx: *g.BuildContext) !g.Node {
    const row = [_]g.Node{ .{ .text = .{ .content = "x" } }, .{ .spacer = 1 }, .{ .text = .{ .content = "end" } } };
    const column = [_]g.Node{ .{ .text = .{ .content = "A<&中", .style = .{ .attributes = g.style.Attributes.bold } } }, .{ .stack = .{ .axis = .horizontal, .spacing = 1, .alignment = .top_leading, .children = &row } } };
    return ctx.retain(.{ .border = .{ .style = .rounded, .title = "T", .text_style = .{ .foreground = .red }, .child = &.{ .padding = .{ .insets = .{ .top = 1, .leading = 1, .bottom = 1, .trailing = 1 }, .child = &.{ .stack = .{ .axis = .vertical, .spacing = 1, .alignment = .top_leading, .children = &column } } } } } });
}
fn produce(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, name, "escaping")) return g.mlir.lower(allocator, .{ .text = .{ .content = "q:\" b:\\ n:\n t:\t end" } }, "parity");
    if (std.mem.eql(u8, name, "controls")) return g.mlir.lower(allocator, .{ .text = .{ .content = "\x00\x01\x08\x0b\x0c\r\n\x1b\x1f\x7f\"\\中é" } }, "quote\"\r\n\\");
    if (std.mem.eql(u8, name, "vocabulary")) return g.mlir.lower(allocator, .{ .group = &.{
        .empty,                                                                                              .{ .overlay = .{ .children = &.{} } },
        .{ .divider = .{} },                                                                                 .{ .divider = .{ .axis = .vertical } },
        .{ .frame = .{ .width = 12, .height = 3, .child = &.empty } },                                       .{ .flex_frame = .{ .min_width = 2, .max_width = std.math.maxInt(i64), .min_height = 1, .max_height = 5, .child = &.empty } },
        .{ .background = .{ .color = .blue, .child = &.empty } },                                            .{ .styled = .{ .style = .{ .attributes = 255 }, .child = &.empty } },
        .{ .interactive = .{ .id = .{ .raw = 0xffffffffffffffff }, .focusable = false, .child = &.empty } },
    } }, "vocabulary");
    if (std.mem.startsWith(u8, name, "plugins-")) {
        const x: g.Node = .{ .interactive = .{ .id = .{ .raw = 8565616715163743237 }, .focusable = true, .child = &.{ .text = .{ .content = "a" } } } };
        const y: g.Node = .{ .interactive = .{ .id = .{ .raw = 8565616715163743238 }, .focusable = true, .child = &.{ .text = .{ .content = "b" } } } };
        return g.mlir.lower(allocator, .{ .group = if (std.mem.eql(u8, name, "plugins-before")) &.{ x, y } else if (std.mem.eql(u8, name, "plugins-after")) &.{y} else &.{ y, x } }, "plugins");
    }
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var storage = g.FrameStorage.init(arena.allocator());
    defer storage.deinit();
    var ctx = storage.context();
    const node = try fixtureNode(&ctx);
    if (std.mem.eql(u8, name, "structural")) return g.mlir.lower(allocator, node, "parity");
    const size: g.geometry.Size = if (std.mem.eql(u8, name, "layout-16x8")) .{ .width = 16, .height = 8 } else .{ .width = 9, .height = 5 };
    return g.mlir.lowerLaid(allocator, try g.layout.place(arena.allocator(), node, .{ .size = size }, .{}), "parity");
}
const names = .{ "escaping", "structural", "layout-16x8", "layout-9x5", "plugins-before", "plugins-after", "plugins-reinstall" };
test "all seven immutable MLIR goldens and repeat determinism" {
    inline for (names) |name| {
        const bytes = try produce(a, name);
        defer a.free(bytes);
        try std.testing.expectEqualStrings(@embedFile("parity/swift-baseline/" ++ name ++ ".mlir"), bytes);
        const again = try produce(a, name);
        defer a.free(again);
        try std.testing.expectEqualSlices(u8, bytes, again);
    }
}
test "control bytes and CRLF use valid byte escapes and preserve Unicode" {
    const bytes = try produce(a, "controls");
    defer a.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\\00\\01\\08\\0B\\0C\\0D\\n\\1B\\1F\\7F\\\"\\\\中é") != null);
}
test "full vocabulary dimensions before alignment and signed 64-bit ID" {
    const bytes = try produce(a, "vocabulary");
    defer a.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "id = -1 : i64, focusable = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "min_width = 2 : i64, max_width = -1 : i64, min_height = 1 : i64, max_height = 5 : i64, halign") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "width = 12 : i64, height = 3 : i64, halign") != null);
}
fn oom(allocator: std.mem.Allocator) !void {
    const bytes = try produce(allocator, "structural");
    defer allocator.free(bytes);
}
test "allocation failures release partial MLIR output" {
    try std.testing.checkAllAllocationFailures(a, oom, .{});
}
/// Independent parser harness consumes actual emitted bytes through a build output.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.ExpectedCaseAndOutput;
    const bytes = try produce(init.gpa, args[1]);
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = bytes });
}

test "i64 boundaries survive NodeID bit patterns and laid group frames" {
    inline for (.{ @as(u64, 1) << 40, @as(u64, 1) << 63, std.math.maxInt(u64) }, .{ "1099511627776", "-9223372036854775808", "-1" }) |id, spelling| {
        const bytes = try g.mlir.lower(a, .{ .interactive = .{ .id = .{ .raw = id }, .focusable = true, .child = &.empty } }, "id64");
        defer a.free(bytes);
        try std.testing.expect(std.mem.indexOf(u8, bytes, "id = " ++ spelling ++ " : i64") != null);
    }
    const bytes = try g.mlir.lowerLaid(a, .{ .node = .{ .group = &.{} }, .frame = .{ .origin = .{ .x = std.math.minInt(i64), .y = std.math.maxInt(i64) }, .size = .{ .width = 3, .height = 4 } }, .children = &.{.{ .node = .{ .divider = .{ .style = .plain, .axis = .horizontal } }, .frame = .{ .size = .{ .width = 3, .height = 1 } } }} }, "laid");
    defer a.free(bytes);
    try std.testing.expectEqualStrings("\"gama.module\"() ({\n" ++
        "  \"gama.group\"() ({\n" ++
        "    \"gama.divider\"() {fg = \"default\", bg = \"default\", sgr = 0 : i64, axis = \"h\", x = 0 : i64, y = 0 : i64, w = 3 : i64, h = 1 : i64} : () -> ()\n" ++
        "  }) {x = -9223372036854775808 : i64, y = 9223372036854775807 : i64, w = 3 : i64, h = 4 : i64} : () -> ()\n" ++
        "}) {sym_name = \"laid\"} : () -> ()\n", bytes);
}
