//! Prepare allocates output without mutation. Promote swaps without allocation.
//! Adapters must complete all preparation before output and promote only on success.
const std = @import("std");
const cells = @import("cells.zig");
const s = @import("../core/style.zig");
const text = @import("../core/text.zig");
const geo = @import("../core/geometry.zig");
const A = std.mem.Allocator;
const Error = @import("../core/state.zig").Error;
fn appendFmt(out: *std.ArrayList(u8), a: A, comptime fmt: []const u8, args: anytype) Error!void {
    const value = try std.fmt.allocPrint(a, fmt, args);
    defer a.free(value);
    try out.appendSlice(a, value);
}
/// ANSI diff encoder; prepare leaves planes unchanged and present promotes only after encoding succeeds.
pub const AnsiPresenter = struct {
    /// Allocate ANSI diff bytes without changing planes; free the returned slice with a.
    pub fn prepare(a: A, b: *const cells.CellBuffer) Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        var last: ?s.TextStyle = null;
        var cursor: ?geo.Point = null;
        for (b.back.cells, b.front.cells, 0..) |cell, front, i| {
            if ((!b.force_full and cell.eql(front)) or cell.continuation) continue;
            const w: usize = @intCast(b.size.width);
            const x: i64 = @intCast(i % w);
            const y: i64 = @intCast(i / w);
            if (cursor == null or cursor.?.x != x or cursor.?.y != y) try appendFmt(&out, a, "\x1b[{d};{d}H", .{ y + 1, x + 1 });
            if (last == null or !std.meta.eql(last.?, cell.style)) {
                try out.appendSlice(a, "\x1b[0");
                inline for (.{ .{ s.Attributes.bold, 1 }, .{ s.Attributes.dim, 2 }, .{ s.Attributes.italic, 3 }, .{ s.Attributes.underline, 4 }, .{ s.Attributes.inverse, 7 }, .{ s.Attributes.strikethrough, 9 } }) |pair| if (cell.style.attributes & pair[0] != 0) {
                    try appendFmt(&out, a, ";{d}", .{pair[1]});
                };
                try color(&out, a, cell.style.foreground, true, b.color_depth);
                try color(&out, a, cell.style.background, false, b.color_depth);
                try out.append(a, 'm');
                last = cell.style;
            }
            try out.appendSlice(a, cell.glyph);
            cursor = .{ .x = x + @max(1, try text.displayWidth(cell.glyph)), .y = y };
        }
        return out.toOwnedSlice(a);
    }

    /// Swap completed planes without allocating.
    pub fn promote(b: *cells.CellBuffer) void {
        b.promote();
    }

    /// Allocate ANSI bytes then promote planes; no transport write occurs. Free returned bytes with a.
    pub fn present(a: A, b: *cells.CellBuffer) Error![]u8 {
        const out = try prepare(a, b);
        promote(b);
        return out;
    }
};
fn color(out: *std.ArrayList(u8), a: A, c: s.Color, foreground: bool, depth: cells.ColorDepth) Error!void {
    if (c.is_default) return;
    const base: u8 = if (foreground) 38 else 48;
    switch (depth) {
        .unknown, .monochrome => {},
        .true_color => try appendFmt(out, a, ";{d};2;{d};{d};{d}", .{ base, c.r, c.g, c.b }),
        .ansi256 => try appendFmt(out, a, ";{d};5;{d}", .{ base, c.xterm256() }),
        .ansi16 => {
            const i = nearestAnsi16(c);
            const code: u8 = (if (foreground) @as(u8, 30) else 40) + (if (i < 8) i else i - 8 + 60);
            try appendFmt(out, a, ";{d}", .{code});
        },
    }
}
/// Select the nearest retained ANSI-16 RGB palette entry.
pub fn nearestAnsi16(c: s.Color) u8 {
    const palette = [_][3]i32{ .{ 0, 0, 0 }, .{ 205, 0, 0 }, .{ 0, 205, 0 }, .{ 205, 205, 0 }, .{ 0, 0, 238 }, .{ 205, 0, 205 }, .{ 0, 205, 205 }, .{ 229, 229, 229 }, .{ 127, 127, 127 }, .{ 255, 0, 0 }, .{ 0, 255, 0 }, .{ 255, 255, 0 }, .{ 92, 92, 255 }, .{ 255, 0, 255 }, .{ 0, 255, 255 }, .{ 255, 255, 255 } };
    var best: u8 = 0;
    var distance: i32 = std.math.maxInt(i32);
    for (palette, 0..) |p, i| {
        const r = @as(i32, c.r) - p[0];
        const g = @as(i32, c.g) - p[1];
        const b = @as(i32, c.b) - p[2];
        const d = r * r + g * g + b * b;
        if (d < distance) {
            distance = d;
            best = @intCast(i);
        }
    }
    return best;
}
/// Owned stream lines; caller must deinit with the allocator used to create them.
pub const Lines = struct {
    /// Individually allocated UTF-8 lines plus the owned outer slice.
    items: [][]u8,

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *Lines, a: A) void {
        for (self.items) |line| a.free(line);
        a.free(self.items);
        self.* = undefined;
    }
};
/// Plain-text row presenter; prepare is non-mutating and present promotes after success.
pub const StreamPresenter = struct {
    /// Allocate nonempty changed rows without changing planes; release the result with Lines.deinit(a).
    pub fn prepare(a: A, b: *const cells.CellBuffer) Error!Lines {
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| a.free(line);
            lines.deinit(a);
        }
        // No iteration over hostile Nx0 or 0xN shapes.
        if (b.back.cells.len != 0) {
            var y: i64 = 0;
            while (y < b.size.height) : (y += 1) if (b.rowChanged(y)) {
                const line = try b.rowText(a, y);
                if (line.len == 0) a.free(line) else {
                    errdefer a.free(line);
                    try lines.append(a, line);
                }
            };
        }
        return .{ .items = try lines.toOwnedSlice(a) };
    }

    /// Swap completed planes without allocating.
    pub fn promote(b: *cells.CellBuffer) void {
        b.promote();
    }

    /// Allocate changed lines then promote planes; no transport write occurs. Release with Lines.deinit(a).
    pub fn present(a: A, b: *cells.CellBuffer) Error!Lines {
        const lines = try prepare(a, b);
        promote(b);
        return lines;
    }
};
