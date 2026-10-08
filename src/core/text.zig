//! Grapheme-offset editing and baseline terminal-width/wrapping policy.
//! UTF8 input is borrowed and validated. Edits and Wrapped own allocator memory.
const std = @import("std");
const unicode = @import("unicode.zig");
const geometry = @import("geometry.zig");
/// UTF-8, allocation and text-operation validation failures.
pub const Error = unicode.Error || std.mem.Allocator.Error || error{
    /// Character input is not an admitted scalar or exactly one extended grapheme.
    InvalidCharacter,
    /// Edited/encoded text length exceeds the destination integer or wire representation.
    TextTooLarge,
};
/// Selection endpoints in grapheme indices; anchor may lie on either side of head.
pub const Selection = struct {
    /// Fixed end of the selection in grapheme indices.
    anchor: i64 = 0,

    /// Moving cursor end of the selection in grapheme indices.
    head: i64 = 0,

    /// Return whether the selection endpoints coincide.
    pub fn collapsed(self: Selection) bool {
        return self.anchor == self.head;
    }

    /// Clamp each endpoint independently to 0...min(length, maxInt(i64)).
    pub fn clamped(self: Selection, length: usize) Selection {
        const n: i64 = @intCast(@min(length, std.math.maxInt(i64)));
        return .{ .anchor = @max(0, @min(self.anchor, n)), .head = @max(0, @min(self.head, n)) };
    }

    /// Return the smaller selection endpoint.
    pub fn lower(self: Selection) i64 {
        return @min(self.anchor, self.head);
    }

    /// Return the larger selection endpoint.
    pub fn upper(self: Selection) i64 {
        return @max(self.anchor, self.head);
    }
};
/// Grapheme cursor movement, with home/end relative to the entire string.
pub const Movement = enum {
    /// Move one grapheme toward the beginning.
    left,
    /// Move one grapheme toward the end.
    right,
    /// Move to grapheme index zero.
    home,
    /// Move to the final grapheme boundary.
    end,
};
/// Move the editing cursor by grapheme boundaries while preserving selection rules.
pub fn move(value: []const u8, selection: Selection, movement: Movement) unicode.Error!Selection {
    const n = try unicode.count(value);
    const s = selection.clamped(n);
    return switch (movement) {
        .left => if (s.head == 0) s else .{ .anchor = s.head - 1, .head = s.head - 1 },
        .right => if (s.head == n) s else .{ .anchor = s.head + 1, .head = s.head + 1 },
        .home => .{},
        .end => .{ .anchor = @intCast(n), .head = @intCast(n) },
    };
}
/// Allocated edited UTF-8 plus its resulting selection; caller frees the byte slice.
pub const Edit = struct {
    /// Owned edited UTF-8 bytes; release with the allocator passed to the edit function.
    value: []u8,

    /// Selection after applying the edit, in grapheme indices.
    selection: Selection,

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *Edit, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
        self.* = undefined;
    }
};
fn byteOffset(value: []const u8, cluster: i64) usize {
    var it = unicode.Graphemes.init(value) catch unreachable;
    var i: i64 = 0;
    while (i < cluster) : (i += 1) _ = it.next().?;
    return it.offset;
}
fn replace(allocator: std.mem.Allocator, value: []const u8, start: i64, end: i64, inserted: []const u8, cursor: i64) Error!Edit {
    const a = byteOffset(value, start);
    const b = byteOffset(value, end);
    const length = std.math.add(usize, value.len - (b - a), inserted.len) catch return error.TextTooLarge;
    if (length > std.math.maxInt(i64)) return error.TextTooLarge;
    const out = try allocator.alloc(u8, length);
    @memcpy(out[0..a], value[0..a]);
    @memcpy(out[a..][0..inserted.len], inserted);
    @memcpy(out[a + inserted.len ..], value[b..]);
    return .{ .value = out, .selection = .{ .anchor = cursor, .head = cursor } };
}
/// Insert exactly one extended grapheme; output cursor preserves pre-resegmentation arithmetic.
pub fn insert(allocator: std.mem.Allocator, value: []const u8, selection: Selection, character: []const u8) Error!Edit {
    const s = selection.clamped(try unicode.count(value));
    if (try unicode.count(character) != 1) return error.InvalidCharacter;
    return replace(allocator, value, s.lower(), s.upper(), character, s.lower() + 1);
}
/// Direction used when deleting at a collapsed selection.
pub const Deletion = enum {
    /// Delete the preceding grapheme.
    backward,
    /// Delete the following grapheme.
    forward,
};
/// Delete the selection or adjacent grapheme without splitting a cluster.
pub fn delete(allocator: std.mem.Allocator, value: []const u8, selection: Selection, direction: Deletion) Error!?Edit {
    const n = try unicode.count(value);
    const s = selection.clamped(n);
    if (!s.collapsed()) return try replace(allocator, value, s.lower(), s.upper(), "", s.lower());
    return switch (direction) {
        .backward => if (s.head == 0) null else try replace(allocator, value, s.head - 1, s.head, "", s.head - 1),
        .forward => if (s.head == n) null else try replace(allocator, value, s.head, s.head + 1, "", s.head),
    };
}
/// Baseline TextField input filter: C0 and DEL reject; C1 and format scalars are accepted.
pub fn acceptsCharacter(character: []const u8) unicode.Error!bool {
    if (try unicode.count(character) != 1) return false;
    var it = (std.unicode.Utf8View.init(character) catch unreachable).iterator();
    while (it.nextCodepoint()) |cp| {
        if (cp < 0x20 or cp == 0x7f) return false;
    }
    return true;
}
const Span = [2]u21;
const zero_width = [_]Span{
    .{ 0x0000, 0x001f }, .{ 0x007f, 0x009f }, .{ 0x0300, 0x036f }, .{ 0x0483, 0x0489 }, .{ 0x0591, 0x05bd }, .{ 0x05bf, 0x05bf }, .{ 0x05c1, 0x05c2 },   .{ 0x05c4, 0x05c5 }, .{ 0x05c7, 0x05c7 },
    .{ 0x0610, 0x061a }, .{ 0x064b, 0x065f }, .{ 0x0670, 0x0670 }, .{ 0x06d6, 0x06ed }, .{ 0x0711, 0x0711 }, .{ 0x0730, 0x074a }, .{ 0x07a6, 0x07b0 },   .{ 0x07eb, 0x07f3 }, .{ 0x0816, 0x082d },
    .{ 0x0859, 0x085b }, .{ 0x08d3, 0x0902 }, .{ 0x093a, 0x093c }, .{ 0x0941, 0x0948 }, .{ 0x094d, 0x094d }, .{ 0x0951, 0x0957 }, .{ 0x0962, 0x0963 },   .{ 0x1ab0, 0x1aff }, .{ 0x1dc0, 0x1dff },
    .{ 0x200b, 0x200d }, .{ 0x202a, 0x202e }, .{ 0x2060, 0x206f }, .{ 0x20d0, 0x20ff }, .{ 0xfe00, 0xfe0f }, .{ 0xfeff, 0xfeff }, .{ 0xe0100, 0xe01ef },
};
const wide = [_]Span{
    .{ 0x1100, 0x115f }, .{ 0x231a, 0x231b }, .{ 0x2329, 0x232a }, .{ 0x23e9, 0x23ec }, .{ 0x23f0, 0x23f0 }, .{ 0x23f3, 0x23f3 }, .{ 0x2e80, 0x303e }, .{ 0x3040, 0xa4cf }, .{ 0xac00, 0xd7a3 }, .{ 0xf900, 0xfaff }, .{ 0xfe10, 0xfe19 }, .{ 0xfe30, 0xfe6f }, .{ 0xff00, 0xff60 }, .{ 0xffe0, 0xffe6 }, .{ 0x1f1e6, 0x1f1ff }, .{ 0x1f300, 0x1faff }, .{ 0x20000, 0x3fffd },
};
fn inSpans(cp: u21, spans: []const Span) bool {
    for (spans) |r| {
        if (cp < r[0]) return false;
        if (cp <= r[1]) return true;
    }
    return false;
}
fn clusterWidthValidated(character: []const u8) i64 {
    var width: i64 = 0;
    var vs16 = false;
    var it = (std.unicode.Utf8View.init(character) catch unreachable).iterator();
    while (it.nextCodepoint()) |cp| {
        if (cp == 0xfe0f) vs16 = true;
        if (inSpans(cp, &zero_width)) continue;
        width = @max(width, if (inSpans(cp, &wide)) @as(i64, 2) else 1);
    }
    return if (vs16 and width > 0) 2 else width;
}
/// Apply the separately pinned terminal-cell width policy to one grapheme.
pub fn clusterWidth(character: []const u8) (unicode.Error || error{
    /// Character input is not an admitted scalar or exactly one extended grapheme.
    InvalidCharacter,
})!i64 {
    if (try unicode.count(character) != 1) return error.InvalidCharacter;
    return clusterWidthValidated(character);
}
/// Sum terminal widths over validated extended grapheme clusters.
pub fn displayWidth(value: []const u8) unicode.Error!i64 {
    var it = try unicode.Graphemes.init(value);
    var width: i64 = 0;
    while (it.next()) |cluster| width +|= clusterWidthValidated(cluster);
    return width;
}
/// Owned wrapped lines; deinit frees every line and the outer slice.
pub const Wrapped = struct {
    /// Individually allocated UTF-8 lines owned by this result.
    lines: [][]u8,

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *Wrapped, allocator: std.mem.Allocator) void {
        for (self.lines) |line| allocator.free(line);
        allocator.free(self.lines);
        self.* = undefined;
    }
};
fn appendLine(out: *std.ArrayList([]u8), allocator: std.mem.Allocator, line: []const u8) std.mem.Allocator.Error!void {
    const copy = try allocator.dupe(u8, line);
    errdefer allocator.free(copy);
    try out.append(allocator, copy);
}
fn wrapLine(allocator: std.mem.Allocator, raw: []const u8, width: i64, out: *std.ArrayList([]u8)) Error!void {
    if (width <= 0 or try displayWidth(raw) <= width) {
        try appendLine(out, allocator, raw);
        return;
    }
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);
    var current_width: i64 = 0;
    // Character equality, not byte/scalar whitespace: a space plus combining mark is a word.
    var words = try unicode.Graphemes.init(raw);
    var word_start: usize = 0;
    while (true) {
        var word_end = raw.len;
        while (words.next()) |cluster| {
            if (std.mem.eql(u8, cluster, " ")) {
                word_end = words.offset - 1;
                break;
            }
        }
        const word = raw[word_start..word_end];
        const word_width = try displayWidth(word);
        if (word_width > width) {
            if (current.items.len > 0) {
                try appendLine(out, allocator, current.items);
                current.clearRetainingCapacity();
            }
            current_width = 0;
            var clusters = try unicode.Graphemes.init(word);
            while (clusters.next()) |cluster| {
                const cw = clusterWidthValidated(cluster);
                // Compare without overflowing counters; every cluster is at most two cells.
                if (current.items.len > 0 and cw > width - current_width) {
                    try appendLine(out, allocator, current.items);
                    current.clearRetainingCapacity();
                    current_width = 0;
                }
                try current.appendSlice(allocator, cluster);
                current_width += cw;
                if (current_width >= width) {
                    try appendLine(out, allocator, current.items);
                    current.clearRetainingCapacity();
                    current_width = 0;
                }
            }
        } else if (current.items.len == 0) {
            try current.appendSlice(allocator, word);
            current_width = word_width;
        } else if (current_width < width and word_width <= width - current_width - 1) {
            try current.append(allocator, ' ');
            try current.appendSlice(allocator, word);
            current_width += 1 + word_width;
        } else {
            try appendLine(out, allocator, current.items);
            current.clearRetainingCapacity();
            try current.appendSlice(allocator, word);
            current_width = word_width;
        }
        if (word_end == raw.len) break;
        word_start = words.offset;
    }
    if (current.items.len > 0 or raw.len == 0) try appendLine(out, allocator, current.items);
}
/// Split only an LF grapheme. CRLF remains one unsplit baseline Character.
pub fn wrap(allocator: std.mem.Allocator, value: []const u8, width: i64) Error!Wrapped {
    var it = try unicode.Graphemes.init(value);
    var out: std.ArrayList([]u8) = .empty;
    errdefer {
        for (out.items) |line| allocator.free(line);
        out.deinit(allocator);
    }
    var start: usize = 0;
    while (it.next()) |cluster| {
        if (std.mem.eql(u8, cluster, "\n")) {
            try wrapLine(allocator, value[start .. it.offset - 1], width, &out);
            start = it.offset;
        }
    }
    try wrapLine(allocator, value[start..], width, &out);
    if (out.items.len == 0) try appendLine(&out, allocator, "");
    return .{ .lines = try out.toOwnedSlice(allocator) };
}
/// Measure wrapped UTF-8 text in cells; null width disables wrapping, a supplied width bounds the result.
/// Temporary lines use allocator and are released before returning the inline Size.
pub fn size(allocator: std.mem.Allocator, value: []const u8, width: ?i64) Error!geometry.Size {
    var lines = try wrap(allocator, value, width orelse 0);
    defer lines.deinit(allocator);
    var maximum: i64 = 0;
    for (lines.lines) |line| maximum = @max(maximum, try displayWidth(line));
    if (width) |w| maximum = @min(maximum, @max(0, w));
    return .{ .width = maximum, .height = @intCast(lines.lines.len) };
}
