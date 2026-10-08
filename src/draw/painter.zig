//! Shared painter clips work to the raster, never to ancestors.
const geo = @import("../core/geometry.zig");
const style = @import("../core/style.zig");
const LaidNode = @import("../core/layout.zig").LaidNode;
const Buffer = @import("cells.zig").CellBuffer;
const Error = @import("../core/state.zig").Error;
/// Paint a laid-out tree into pending cells; publication remains caller-controlled.
pub fn paint(buffer: *Buffer, tree: LaidNode) Error!void {
    if (buffer.back.cells.len == 0) return;
    try draw(buffer, tree, .plain);
}
fn draw(b: *Buffer, tree: LaidNode, inherited: style.TextStyle) Error!void {
    const r = tree.frame;
    var child_style = inherited;
    switch (tree.node) {
        .empty, .spacer => return,
        .text => |v| {
            try b.putText(r.minX(), r.minY(), v.content, v.style.merging(inherited), @max(1, r.size.width));
            return;
        },
        .styled => |v| {
            child_style = v.style.merging(inherited);
            if (!child_style.background.is_default) b.fillBackground(r, child_style.background);
        },
        .background => |v| b.fillBackground(r, v.color),
        .divider => |v| {
            const s = inherited.merging(v.style);
            const vertical = if (v.axis) |axis| axis == .horizontal else r.size.height > r.size.width;
            if (vertical) try verticalLine(b, r.minX(), r.minY(), r.maxY(), "│", s) else try horizontalLine(b, r.minY(), r.minX(), r.maxX(), "─", s);
            return;
        },
        .border => |v| try border(b, r, v.style, inherited.merging(v.text_style), v.title),
        else => {},
    }
    for (tree.children) |child| try draw(b, child, child_style);
}
fn horizontalLine(b: *Buffer, y: i64, first: i64, end: i64, glyph: []const u8, s: style.TextStyle) Error!void {
    if (y < 0 or y >= b.size.height) return;
    var x = @max(0, first);
    const limit = @min(b.size.width, end);
    while (x < limit) : (x += 1) try b.put(x, y, glyph, s);
}
fn verticalLine(b: *Buffer, x: i64, first: i64, end: i64, glyph: []const u8, s: style.TextStyle) Error!void {
    if (x < 0 or x >= b.size.width) return;
    var y = @max(0, first);
    const limit = @min(b.size.height, end);
    while (y < limit) : (y += 1) try b.put(x, y, glyph, s);
}
fn border(b: *Buffer, r: geo.Rect, kind: style.BorderStyle, s: style.TextStyle, title: ?[]const u8) Error!void {
    if (r.size.width < 2 or r.size.height < 2) return;
    const g = kind.glyphs();
    const right = r.maxX() -| 1;
    const bottom = r.maxY() -| 1;
    try b.put(r.minX(), r.minY(), g.top_left, s);
    try b.put(right, r.minY(), g.top_right, s);
    try b.put(r.minX(), bottom, g.bottom_left, s);
    try b.put(right, bottom, g.bottom_right, s);
    try horizontalLine(b, r.minY(), r.minX() +| 1, right, g.top, s);
    try horizontalLine(b, bottom, r.minX() +| 1, right, g.bottom, s);
    try verticalLine(b, r.minX(), r.minY() +| 1, bottom, g.left, s);
    try verticalLine(b, right, r.minY() +| 1, bottom, g.right, s);
    if (title) |value| if (value.len > 0 and r.size.width >= try style.borderTitleWidth(value)) {
        const padded = try @import("std").fmt.allocPrint(b.allocator, " {s} ", .{value});
        defer b.allocator.free(padded);
        var title_style = s;
        title_style.attributes |= style.Attributes.bold;
        try b.putText(r.minX() +| 1, r.minY(), padded, title_style, @max(1, r.size.width -| 2));
    };
}
