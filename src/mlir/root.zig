//! Deterministic generic MLIR text. Output is allocator-owned; no dialect or
//! lowering implementation is implied. Traversal preserves structural order.
const std = @import("std");
const Node = @import("../core/node.zig").Node;
const LaidNode = @import("../core/layout.zig").LaidNode;
const geo = @import("../core/geometry.zig");
const style = @import("../core/style.zig");
const E = error{
    /// Allocator could not reserve storage required by the operation.
    OutOfMemory,
};
/// Emit pre-layout IR; the caller frees the returned bytes.
pub fn lower(a: std.mem.Allocator, node: Node, name: []const u8) E![]u8 {
    return module(a, node, null, name);
}
/// Emit layout IR with absolute x/y/w/h after structural attributes; free returned bytes with a.
pub fn lowerLaid(a: std.mem.Allocator, node: LaidNode, name: []const u8) E![]u8 {
    return module(a, node.node, node, name);
}
fn module(a: std.mem.Allocator, node: Node, laid: ?LaidNode, name: []const u8) E![]u8 {
    var b: Builder = .{ .a = a };
    errdefer b.out.deinit(a);
    try b.add("\"gama.module\"() ({\n");
    try b.emit(node, laid, 1);
    try b.add("}) {sym_name = ");
    try b.string(name);
    try b.add("} : () -> ()\n");
    return b.out.toOwnedSlice(a);
}
const Builder = struct {
    /// Allocator backing the emitter's temporary byte list.
    a: std.mem.Allocator,

    /// Owned in-progress MLIR text; moved to the caller on successful emission.
    out: std.ArrayList(u8) = .empty,
    fn add(b: *Builder, s: []const u8) E!void {
        try b.out.appendSlice(b.a, s);
    }
    fn print(b: *Builder, comptime fmt: []const u8, args: anytype) E!void {
        var buf: [128]u8 = undefined;
        try b.add(std.fmt.bufPrint(&buf, fmt, args) catch unreachable);
    }
    fn indent(b: *Builder, n: usize) E!void {
        for (0..n) |_| try b.add("  ");
    }
    fn string(b: *Builder, s: []const u8) E!void {
        try b.add("\"");
        for (s) |c| switch (c) {
            '"' => try b.add("\\\""),
            '\\' => try b.add("\\\\"),
            '\n' => try b.add("\\n"),
            '\t' => try b.add("\\t"),
            0...8, 11...31, 127 => {
                const hex = "0123456789ABCDEF";
                try b.add(&.{ '\\', hex[c >> 4], hex[c & 15] });
            },
            else => try b.out.append(b.a, c),
        };
        try b.add("\"");
    }
    fn key(b: *Builder, first: *bool, name: []const u8) E!void {
        try b.add(if (first.*) " {" else ", ");
        first.* = false;
        try b.add(name);
        try b.add(" = ");
    }
    fn int(b: *Builder, first: *bool, name: []const u8, n: i64) E!void {
        try b.key(first, name);
        try b.print("{d} : i64", .{n});
    }
    fn str(b: *Builder, first: *bool, name: []const u8, s: []const u8) E!void {
        try b.key(first, name);
        try b.string(s);
    }
    fn color(b: *Builder, first: *bool, name: []const u8, c: style.Color) E!void {
        try b.key(first, name);
        if (c.is_default) try b.string("default") else try b.print("dense<[{d}, {d}, {d}]> : tensor<3xi8>", .{ c.r, c.g, c.b });
    }
    fn textStyle(b: *Builder, first: *bool, s: style.TextStyle) E!void {
        try b.color(first, "fg", s.foreground);
        try b.color(first, "bg", s.background);
        try b.int(first, "sgr", s.attributes);
    }
    fn alignment(b: *Builder, first: *bool, v: geo.Alignment) E!void {
        try b.str(first, "halign", @tagName(v.horizontal));
        try b.str(first, "valign", @tagName(v.vertical));
    }
    fn emit(b: *Builder, n: Node, laid: ?LaidNode, depth: usize) E!void {
        const op = switch (n) {
            .flex_frame => "frame",
            else => @tagName(n),
        };
        const region = switch (n) {
            .empty, .text, .spacer, .divider => false,
            else => true,
        };
        try b.indent(depth);
        try b.add("\"gama.");
        try b.add(op);
        try b.add("\"()");
        if (region) {
            try b.add(" ({\n");
            if (laid) |l| {
                for (l.children) |c| try b.emit(c.node, c, depth + 1);
            } else switch (n) {
                .group => |cs| {
                    for (cs) |c| try b.emit(c, null, depth + 1);
                },
                inline .stack, .overlay => |v| {
                    for (v.children) |c| try b.emit(c, null, depth + 1);
                },
                inline .padding, .border, .background, .frame, .flex_frame, .styled, .interactive => |v| try b.emit(v.child.*, null, depth + 1),
                else => unreachable,
            }
            try b.indent(depth);
            try b.add("})");
        }
        var first = true;
        switch (n) {
            .empty, .group => {},
            .text => |v| {
                try b.str(&first, "text", v.content);
                try b.textStyle(&first, v.style);
            },
            .spacer => |v| try b.int(&first, "min", v),
            .divider => |v| {
                try b.textStyle(&first, v.style);
                if (v.axis) |axis| try b.str(&first, "axis", if (axis == .horizontal) "h" else "v");
            },
            .stack => |v| {
                try b.str(&first, "axis", if (v.axis == .horizontal) "h" else "v");
                try b.int(&first, "spacing", v.spacing);
                try b.alignment(&first, v.alignment);
            },
            .overlay => |v| try b.alignment(&first, v.alignment),
            .padding => |v| {
                inline for (.{ "top", "leading", "bottom", "trailing" }) |key_name| try b.int(&first, key_name, @field(v.insets, key_name));
            },
            .border => |v| {
                try b.str(&first, "style", @tagName(v.style));
                try b.color(&first, "fg", v.text_style.foreground);
                if (v.title) |t| try b.str(&first, "title", t);
            },
            .background => |v| try b.color(&first, "color", v.color),
            .frame => |v| {
                if (v.width) |w| try b.int(&first, "width", w);
                if (v.height) |h| try b.int(&first, "height", h);
                try b.alignment(&first, v.alignment);
            },
            .flex_frame => |v| {
                inline for (.{ "min_width", "max_width", "min_height", "max_height" }) |k| if (@field(v, k)) |value| {
                    try b.int(&first, k, if (std.mem.startsWith(u8, k, "max_") and value == std.math.maxInt(i64)) -1 else value);
                };
                try b.alignment(&first, v.alignment);
            },
            .styled => |v| try b.textStyle(&first, v.style),
            .interactive => |v| {
                try b.int(&first, "id", @bitCast(v.id.raw));
                try b.key(&first, "focusable");
                try b.add(if (v.focusable) "true" else "false");
            },
        }
        if (laid) |l| {
            try b.int(&first, "x", l.frame.origin.x);
            try b.int(&first, "y", l.frame.origin.y);
            try b.int(&first, "w", l.frame.size.width);
            try b.int(&first, "h", l.frame.size.height);
        }
        if (!first) try b.add("}");
        try b.add(" : () -> ()\n");
    }
};
