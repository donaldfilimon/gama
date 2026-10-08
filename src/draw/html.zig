//! Legacy HTML content serialization, including exact-grapheme escaping.
//! Decorated punctuation is preserved; this is not a general HTML sanitizer.
const std = @import("std");
const cells = @import("cells.zig");
const style = @import("../core/style.zig");
const unicode = @import("../core/unicode.zig");
const A = std.mem.Allocator;
const Error = @import("../core/state.zig").Error;
/// Non-mutating HTML cell serializer; escapes text and returns allocator-owned bytes.
pub const HTMLSerializer = struct {
    /// Serialize visible styled runs as HTML without changing planes; free returned bytes with a.
    /// Escape exact &, < and > graphemes; decorated graphemes are preserved, not sanitized.
    pub fn serialize(a: A, buffer: *const cells.CellBuffer) Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        var current: ?i64 = null;
        var runs = buffer.runs();
        while (runs.next()) |run| {
            if (current == null or current.? != run.row) {
                if (current != null) try out.appendSlice(a, "</pre>");
                try out.appendSlice(a, "<pre class=\"gama-row\">");
                current = run.row;
            }
            try out.appendSlice(a, "<span style=\"");
            try css(&out, a, run.style);
            try out.appendSlice(a, "\">");
            var joined: std.ArrayList(u8) = .empty;
            defer joined.deinit(a);
            for (run.cells) |c| if (!c.continuation) {
                try joined.appendSlice(a, c.glyph);
            };
            var it = try unicode.Graphemes.init(joined.items);
            while (it.next()) |glyph| try out.appendSlice(a, if (std.mem.eql(u8, glyph, "&")) "&amp;" else if (std.mem.eql(u8, glyph, "<")) "&lt;" else if (std.mem.eql(u8, glyph, ">")) "&gt;" else glyph);
            try out.appendSlice(a, "</span>");
        }
        if (current != null) try out.appendSlice(a, "</pre>");
        return out.toOwnedSlice(a);
    }
};
fn css(out: *std.ArrayList(u8), a: A, s: style.TextStyle) Error!void {
    var fg = s.foreground;
    var bg = s.background;
    if (s.attributes & style.Attributes.inverse != 0) std.mem.swap(style.Color, &fg, &bg);
    inline for (.{ .{ fg, "color" }, .{ bg, "background" } }) |entry| if (!entry[0].is_default) {
        const value = try std.fmt.allocPrint(a, "{s}:rgb({d},{d},{d});", .{ entry[1], entry[0].r, entry[0].g, entry[0].b });
        defer a.free(value);
        try out.appendSlice(a, value);
    };
    inline for (.{ .{ style.Attributes.bold, "font-weight:bold;" }, .{ style.Attributes.dim, "opacity:.6;" }, .{ style.Attributes.italic, "font-style:italic;" } }) |entry| if (s.attributes & entry[0] != 0) {
        try out.appendSlice(a, entry[1]);
    };
    const under = s.attributes & style.Attributes.underline != 0;
    const strike = s.attributes & style.Attributes.strikethrough != 0;
    if (under or strike) {
        try out.appendSlice(a, "text-decoration:");
        if (under) try out.appendSlice(a, "underline");
        if (under and strike) try out.append(a, ' ');
        if (strike) try out.appendSlice(a, "line-through");
        try out.append(a, ';');
    }
}
