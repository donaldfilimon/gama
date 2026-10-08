const std = @import("std");
const gama = @import("gama");
const geo = gama.geometry;
const uni = gama.unicode;
const text = gama.text;

test "signed saturating geometry and exact stable identity" {
    const hi = std.math.maxInt(i64);
    const lo = std.math.minInt(i64);
    try std.testing.expectEqual(hi, geo.satAdd(hi, 1));
    try std.testing.expectEqual(lo, geo.satSub(lo, 1));
    try std.testing.expectEqual(hi, geo.satSub(0, lo));
    try std.testing.expectEqual(@as(u64, 8565616715163743236), gama.NodeID.root.child(-1).raw);
}

test "grapheme segmentation rejects malformed UTF8 and respects Unicode17 Indic" {
    try std.testing.expectError(error.InvalidUtf8, uni.Graphemes.init("\xff"));
    var it = try uni.Graphemes.init("e\u{301}🇺🇸👩‍👩‍👧‍👦က္က");
    var count: usize = 0;
    while (it.next() != null) count += 1;
    try std.testing.expectEqual(@as(usize, 4), count);
}

test "selection moves relative to head and edit resegmentation keeps arithmetic cursor" {
    const left = try text.move("abc", .{ .anchor = 2, .head = 0 }, .left);
    try std.testing.expectEqual(text.Selection{ .anchor = 2, .head = 0 }, left);
    var result = try text.insert(std.testing.allocator, "e", .{ .anchor = 1, .head = 1 }, "\u{301}");
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("e\u{301}", result.value);
    try std.testing.expectEqual(@as(i64, 2), result.selection.head);
    try std.testing.expectEqual(@as(usize, 1), try uni.count(result.value));
}

fn parseJson(comptime T: type, bytes: []const u8) !std.json.Parsed(T) {
    return std.json.parseFromSlice(T, std.testing.allocator, bytes, .{});
}
fn point(raw: [2]i64) geo.Point {
    return .{ .x = raw[0], .y = raw[1] };
}
fn rect(raw: [4]i64) geo.Rect {
    return .{ .origin = .{ .x = raw[0], .y = raw[1] }, .size = .{ .width = raw[2], .height = raw[3] } };
}
fn selection(raw: [2]i64) text.Selection {
    return .{ .anchor = raw[0], .head = raw[1] };
}
const GeometryFixture = struct {
    clamped: [2]i64,
    ids: []const struct { path: []const i64, raw: []const u8 },
    points: []const struct { a: [2]i64, b: [2]i64, add: [2]i64, subtract: [2]i64 },
    rects: []const struct { input: [4]i64, edges: [4]i64, inset: [4]i64, intersection: [4]i64, originContained: bool },
};
test "frozen Swift geometry identity fixture parity" {
    const fixture = try parseJson(GeometryFixture, @embedFile("../parity/swift-baseline/geometry-identity.json"));
    defer fixture.deinit();
    for (fixture.value.ids) |row| {
        var id = gama.NodeID.root;
        for (row.path) |index| id = id.child(index);
        try std.testing.expectEqual(try std.fmt.parseInt(u64, row.raw, 10), id.raw);
    }
    for (fixture.value.points) |row| {
        try std.testing.expectEqual(point(row.add), point(row.a).add(point(row.b)));
        try std.testing.expectEqual(point(row.subtract), point(row.a).subtract(point(row.b)));
    }
    for (fixture.value.rects) |row| {
        const r = rect(row.input);
        try std.testing.expectEqual(row.edges, [4]i64{ r.minX(), r.minY(), r.maxX(), r.maxY() });
        try std.testing.expectEqual(rect(row.inset), r.inset(.{ .top = 1, .leading = 1, .bottom = 1, .trailing = 1 }));
        try std.testing.expectEqual(rect(row.intersection), r.intersection(rect(.{ 1, 1, 5, 5 })));
        try std.testing.expectEqual(row.originContained, r.contains(r.origin));
    }
    try std.testing.expectEqual(geo.Size{ .width = fixture.value.clamped[0], .height = fixture.value.clamped[1] }, (geo.Size{ .width = -2, .height = 8 }).clamped(.{ .width = 5, .height = 3 }));
}
const ExpectedEdit = struct { text: []const u8, selection: [2]i64 };
const TextFixture = struct {
    text: []const u8,
    clusters: []const []const u8,
    clusterWidths: []const i64,
    width: i64,
    edits: []const struct { selection: [2]i64, left: [2]i64, right: [2]i64, insert: ExpectedEdit, backward: ?ExpectedEdit, forward: ?ExpectedEdit },
    wrap: []const struct { width: i64, lines: []const []const u8 },
};
fn expectEdit(expected: ExpectedEdit, actual: text.Edit) !void {
    try std.testing.expectEqualStrings(expected.text, actual.value);
    try std.testing.expectEqual(selection(expected.selection), actual.selection);
}
fn expectDelete(value: []const u8, s: text.Selection, direction: text.Deletion, expected: ?ExpectedEdit) !void {
    var result = try text.delete(std.testing.allocator, value, s, direction);
    defer if (result) |*r| r.deinit(std.testing.allocator);
    if (expected) |e| {
        try std.testing.expect(result != null);
        try expectEdit(e, result.?);
    } else try std.testing.expect(result == null);
}
test "frozen Swift cluster width wrapping and every edit fixture parity" {
    const fixture = try parseJson([]const TextFixture, @embedFile("../parity/swift-baseline/unicode-editing.json"));
    defer fixture.deinit();
    try std.testing.expectEqual(@as(usize, 11), fixture.value.len);
    for (fixture.value) |row| {
        var clusters = try uni.Graphemes.init(row.text);
        for (row.clusters, row.clusterWidths) |cluster, width| {
            try std.testing.expectEqualStrings(cluster, clusters.next().?);
            try std.testing.expectEqual(width, try text.clusterWidth(cluster));
        }
        try std.testing.expect(clusters.next() == null);
        try std.testing.expectEqual(row.width, try text.displayWidth(row.text));
        for (row.wrap) |w| {
            var result = try text.wrap(std.testing.allocator, row.text, w.width);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(w.lines.len, result.lines.len);
            for (w.lines, result.lines) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
        }
        for (row.edits) |e| {
            const s = selection(e.selection);
            try std.testing.expectEqual(selection(e.left), try text.move(row.text, s, .left));
            try std.testing.expectEqual(selection(e.right), try text.move(row.text, s, .right));
            var result = try text.insert(std.testing.allocator, row.text, s, "Z");
            defer result.deinit(std.testing.allocator);
            try expectEdit(e.insert, result);
            try expectDelete(row.text, s, .backward, e.backward);
            try expectDelete(row.text, s, .forward, e.forward);
        }
    }
}

test "all official Unicode17 GraphemeBreakTest vectors" {
    const corpus = @embedFile("data/GraphemeBreakTest.txt");
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    var vector_count: usize = 0;
    while (lines.next()) |raw| {
        const line = raw[0..(std.mem.indexOfScalar(u8, raw, '#') orelse raw.len)];
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(std.testing.allocator);
        var breaks: std.ArrayList(usize) = .empty;
        defer breaks.deinit(std.testing.allocator);
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷")) try breaks.append(std.testing.allocator, bytes.items.len) else if (!std.mem.eql(u8, token, "×")) {
                const cp = try std.fmt.parseInt(u21, token, 16);
                var buffer: [4]u8 = undefined;
                const n = try std.unicode.utf8Encode(cp, &buffer);
                try bytes.appendSlice(std.testing.allocator, buffer[0..n]);
            }
        }
        if (breaks.items.len == 0) continue;
        vector_count += 1;
        var it = try uni.Graphemes.init(bytes.items);
        try std.testing.expectEqual(@as(usize, 0), breaks.items[0]);
        for (breaks.items[1..]) |expected_offset| {
            try std.testing.expect(it.next() != null);
            if (expected_offset != it.offset) std.debug.print("Unicode17 vector {d}: expected byte {d}, got {d}\n", .{ vector_count, expected_offset, it.offset });
            try std.testing.expectEqual(expected_offset, it.offset);
        }
        try std.testing.expect(it.next() == null);
    }
    try std.testing.expectEqual(@as(usize, 766), vector_count);
}

const ControlFixture = struct { input: []const u8, isLetter: bool, lowercase: []const u8 };
test "frozen Swift control classification plus multi scalar lowercase" {
    const fixture = try parseJson([]const ControlFixture, @embedFile("../parity/swift-baseline/control-key-classification.json"));
    defer fixture.deinit();
    for (fixture.value) |row| {
        try std.testing.expectEqual(row.isLetter, try uni.isLetter(row.input));
        const lower = try uni.lowercased(std.testing.allocator, row.input);
        defer std.testing.allocator.free(lower);
        try std.testing.expectEqualStrings(row.lowercase, lower);
    }
    try std.testing.expect(try uni.isLetter("a\u{301}"));
    try std.testing.expect(!try uni.isLetter("\u{301}a"));
    const lower = try uni.lowercased(std.testing.allocator, "İΣΣ");
    defer std.testing.allocator.free(lower);
    try std.testing.expectEqualStrings("i\u{307}σσ", lower);
}
const ControlOracle = struct { scalarCount: usize, alphabetic: []const [2]u21, lowercase: []const struct { cp: u21, mapping: []const u21 } };
test "every valid scalar agrees with captured pinned Swift runtime control oracle" {
    const fixture = try parseJson(ControlOracle, @embedFile("data/swift-control-oracle.json"));
    defer fixture.deinit();
    var alpha_index: usize = 0;
    var lower_index: usize = 0;
    var checked: usize = 0;
    var cp: u21 = 0;
    while (cp <= 0x10ffff) : (cp += 1) {
        if (cp >= 0xd800 and cp <= 0xdfff) continue;
        while (alpha_index < fixture.value.alphabetic.len and cp > fixture.value.alphabetic[alpha_index][1]) alpha_index += 1;
        const alpha = alpha_index < fixture.value.alphabetic.len and cp >= fixture.value.alphabetic[alpha_index][0];
        try std.testing.expectEqual(alpha, uni.isAlphabetic(cp));
        const mapping = uni.lowercaseMapping(cp);
        if (lower_index < fixture.value.lowercase.len and cp == fixture.value.lowercase[lower_index].cp) {
            const row = fixture.value.lowercase[lower_index];
            try std.testing.expectEqualSlices(u21, row.mapping, mapping.scalars[0..mapping.len]);
            lower_index += 1;
        } else try std.testing.expectEqualSlices(u21, &.{cp}, mapping.scalars[0..mapping.len]);
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 1112064), checked);
    try std.testing.expectEqual(checked, fixture.value.scalarCount);
    try std.testing.expectEqual(fixture.value.lowercase.len, lower_index);
}

test "geometry extremes preserve saturation order and canonical empty intersections" {
    const hi = std.math.maxInt(i64);
    const lo = std.math.minInt(i64);
    const r = geo.Rect{ .origin = .{ .x = lo, .y = -5 }, .size = .{ .width = hi, .height = 10 } };
    try std.testing.expectEqual(geo.Rect.zero, r.intersection(.{ .origin = .{ .x = hi }, .size = .{ .width = hi, .height = 1 } }));
    try std.testing.expectEqual(geo.Rect.zero, r.intersection(.{ .origin = .{ .x = -1 }, .size = .{ .width = 1, .height = 1 } }));
    const expanded = r.inset(.{ .leading = lo, .trailing = lo, .top = -2, .bottom = -3 });
    try std.testing.expectEqual(lo, expanded.origin.x);
    try std.testing.expectEqual(hi, expanded.size.width);
    try std.testing.expectEqual(@as(i64, 15), expanded.size.height);
    try std.testing.expectEqual(geo.Size{ .width = -8, .height = -4 }, (geo.ProposedSize{ .width = -8 }).replacingUnspecified(.{ .width = 22, .height = -4 }));
    try std.testing.expect(!(geo.Rect{ .origin = .{ .x = hi }, .size = .{ .width = hi, .height = 1 } }).contains(.{ .x = hi }));
    try std.testing.expectEqual(hi, geo.satSub(hi, lo));
    try std.testing.expectEqual(lo, geo.satAdd(lo, lo));
}

test "explicit malformed UTF8 rejection reaches every public text operation" {
    const invalid = [_][]const u8{ "\x80", "\xc0\x80", "\xc1\xbf", "\xe0\x80\x80", "\xed\xa0\x80", "\xf0\x80\x80\x80", "\xf4\x90\x80\x80", "\xf5\x80\x80\x80", "\xe2\x82", "\xf0\x9f\x92", "\xc2x", "a\xffb" };
    for (invalid) |bytes| {
        try std.testing.expectError(error.InvalidUtf8, uni.Graphemes.init(bytes));
        try std.testing.expectError(error.InvalidUtf8, uni.count(bytes));
        try std.testing.expectError(error.InvalidUtf8, uni.isLetter(bytes));
        try std.testing.expectError(error.InvalidUtf8, uni.lowercased(std.testing.allocator, bytes));
        try std.testing.expectError(error.InvalidUtf8, text.displayWidth(bytes));
        try std.testing.expectError(error.InvalidUtf8, text.clusterWidth(bytes));
        try std.testing.expectError(error.InvalidUtf8, text.wrap(std.testing.allocator, bytes, 1));
        try std.testing.expectError(error.InvalidUtf8, text.size(std.testing.allocator, bytes, 1));
        try std.testing.expectError(error.InvalidUtf8, text.move(bytes, .{}, .right));
        try std.testing.expectError(error.InvalidUtf8, text.delete(std.testing.allocator, bytes, .{}, .backward));
        try std.testing.expectError(error.InvalidUtf8, text.insert(std.testing.allocator, bytes, .{}, "x"));
        try std.testing.expectError(error.InvalidUtf8, text.insert(std.testing.allocator, "x", .{}, bytes));
        try std.testing.expectError(error.InvalidUtf8, text.acceptsCharacter(bytes));
    }
    try std.testing.expectError(error.InvalidCharacter, text.insert(std.testing.allocator, "", .{}, ""));
    try std.testing.expectError(error.InvalidCharacter, text.insert(std.testing.allocator, "", .{}, "ab"));
    try std.testing.expect(!try text.acceptsCharacter("\x1f"));
    try std.testing.expect(!try text.acceptsCharacter("\x7f"));
    try std.testing.expect(!try text.acceptsCharacter("\r\n"));
    try std.testing.expect(try text.acceptsCharacter("\u{85}"));
    try std.testing.expect(try text.acceptsCharacter("\u{200d}"));
    try std.testing.expect(try text.acceptsCharacter("\u{301}"));
}

fn expectWrap(value: []const u8, width: i64, expected: []const []const u8) !void {
    var result = try text.wrap(std.testing.allocator, value, width);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected.len, result.lines.len);
    for (expected, result.lines) |a, b| try std.testing.expectEqualStrings(a, b);
}
test "wrapping preserves baseline spaces newline equality zero width and oversized clusters" {
    try expectWrap("  a", 1, &.{"a"});
    try expectWrap("a  b", 2, &.{ "a ", "b" });
    try expectWrap("   ", 1, &.{""});
    try expectWrap("a  ", 1, &.{"a"});
    try expectWrap("界", 1, &.{"界"});
    try expectWrap("ab\u{200b}", 1, &.{ "a", "b", "\u{200b}" });
    try expectWrap("a\r\nb\nc\n", 0, &.{ "a\r\nb", "c", "" });
    try expectWrap("a\u{85}b\u{2028}c", 0, &.{"a\u{85}b\u{2028}c"});
    try expectWrap("a\u{a0}b", 2, &.{ "a\u{a0}", "b" });
    try expectWrap("a \u{301}b", 1, &.{ "a", " \u{301}", "b" });
    try expectWrap("a\tb", 1, &.{ "a", "\tb" });
    try std.testing.expectEqual(@as(i64, 0), try text.displayWidth("\u{fe0f}"));
    try std.testing.expectEqual(@as(i64, 2), try text.displayWidth("a\u{fe0f}"));
    try std.testing.expectEqual(@as(i64, 2), try text.displayWidth("⌚\u{fe0e}"));
    try std.testing.expectEqual(geo.Size{ .width = 1, .height = 1 }, try text.size(std.testing.allocator, "界", 1));
    try std.testing.expectEqual(geo.Size{ .width = 0, .height = 2 }, try text.size(std.testing.allocator, "a\nb", -1));
}

test "edits resegment combining CRLF ZWJ flags and preserve delayed cursor clamp" {
    const cases = [_]struct { original: []const u8, character: []const u8, expected: []const u8 }{
        .{ .original = "e", .character = "\u{301}", .expected = "e\u{301}" },
        .{ .original = "\r", .character = "\n", .expected = "\r\n" },
        .{ .original = "👩‍", .character = "👩", .expected = "👩‍👩" },
        .{ .original = "🇺", .character = "🇸", .expected = "🇺🇸" },
    };
    for (cases) |c| {
        var e = try text.insert(std.testing.allocator, c.original, .{ .anchor = 1, .head = 1 }, c.character);
        defer e.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(c.expected, e.value);
        try std.testing.expectEqual(@as(i64, 2), e.selection.head);
        try std.testing.expectEqual(@as(usize, 1), try uni.count(e.value));
        try std.testing.expectEqual(text.Selection{ .anchor = 1, .head = 1 }, try text.move(e.value, e.selection, .end));
        try expectDelete(e.value, e.selection, .backward, .{ .text = "", .selection = .{ 0, 0 } });
    }
    try std.testing.expectEqual(text.Selection{ .anchor = 0, .head = 3 }, try text.move("abc", .{ .anchor = 0, .head = 3 }, .right));
    try std.testing.expectEqual(text.Selection{}, try text.move("abc", .{ .anchor = 99, .head = -9 }, .home));
    try expectDelete("abc", .{ .anchor = 0, .head = 0 }, .backward, null);
    try expectDelete("abc", .{ .anchor = 3, .head = 3 }, .forward, null);
}

fn allocationExercise(allocator: std.mem.Allocator, kind: u8) !void {
    var input = [_]u8{ 'e', 0xcc, 0x81, ' ', 0xe7, 0x95, 0x8c, 'a', 'b', ' ', ' ', 'c' };
    const before = input;
    defer std.testing.expectEqualSlices(u8, &before, &input) catch @panic("OOM changed borrowed input");
    switch (kind) {
        0 => {
            var e = try text.insert(allocator, &input, .{ .anchor = 0, .head = 2 }, "👩‍👩‍👧‍👦");
            defer e.deinit(allocator);
        },
        1 => {
            var e = (try text.delete(allocator, &input, .{ .anchor = 1, .head = 1 }, .backward)).?;
            defer e.deinit(allocator);
        },
        2 => {
            var e = (try text.delete(allocator, &input, .{ .anchor = 1, .head = 1 }, .forward)).?;
            defer e.deinit(allocator);
        },
        3 => {
            var e = (try text.delete(allocator, &input, .{ .anchor = 99, .head = -4 }, .forward)).?;
            defer e.deinit(allocator);
        },
        4 => {
            var w = try text.wrap(allocator, &input, 1);
            defer w.deinit(allocator);
        },
        5 => {
            var w = try text.wrap(allocator, "a\n\n界\r\n", 0);
            defer w.deinit(allocator);
        },
        6 => {
            const lower = try uni.lowercased(allocator, "İΣÉABC👩‍💻");
            defer allocator.free(lower);
        },
        7 => {
            _ = try text.size(allocator, &input, 2);
        },
        else => unreachable,
    }
}
test "all allocation failure points clean up and leave borrowed text intact" {
    for (0..8) |kind| try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{@as(u8, @intCast(kind))});
}

test "large single clusters and long RI runs remain intact and bounded" {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    try bytes.append(std.testing.allocator, 'e');
    for (0..10000) |_| try bytes.appendSlice(std.testing.allocator, "\u{301}");
    try std.testing.expectEqual(@as(usize, 1), try uni.count(bytes.items));
    try std.testing.expectEqual(@as(i64, 1), try text.displayWidth(bytes.items));
    try expectWrap(bytes.items, 1, &.{bytes.items});
    bytes.clearRetainingCapacity();
    for (0..1001) |_| try bytes.appendSlice(std.testing.allocator, "🇺");
    try std.testing.expectEqual(@as(usize, 501), try uni.count(bytes.items));
    try std.testing.expectEqual(@as(i64, 1002), try text.displayWidth(bytes.items));
}

test "every valid scalar preserves captured baseline terminal width independently of Unicode grapheme properties" {
    const Oracle = struct { scalarCount: usize, nonNarrowRanges: []const [3]i64 };
    const fixture = try parseJson(Oracle, @embedFile("data/swift-width-oracle.json"));
    defer fixture.deinit();
    var range_index: usize = 0;
    var checked: usize = 0;
    var cp: u21 = 0;
    while (cp <= 0x10ffff) : (cp += 1) {
        if (cp >= 0xd800 and cp <= 0xdfff) continue;
        while (range_index < fixture.value.nonNarrowRanges.len and cp > fixture.value.nonNarrowRanges[range_index][1]) range_index += 1;
        const expected: i64 = if (range_index < fixture.value.nonNarrowRanges.len and cp >= fixture.value.nonNarrowRanges[range_index][0]) fixture.value.nonNarrowRanges[range_index][2] else 1;
        var bytes: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(cp, &bytes);
        try std.testing.expectEqual(expected, try text.displayWidth(bytes[0..len]));
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 1112064), checked);
    try std.testing.expectEqual(checked, fixture.value.scalarCount);
}

test "recorded intentional Swift Indic differences follow Unicode17 grouping" {
    const Difference = struct { vector: usize, scalars: []const u21, unicode17: []const usize, swift: []const usize };
    const Oracle = struct { vectors: usize, differences: []const Difference };
    const fixture = try parseJson(Oracle, @embedFile("data/swift-grapheme-differences.json"));
    defer fixture.deinit();
    try std.testing.expectEqual(@as(usize, 766), fixture.value.vectors);
    try std.testing.expectEqual(@as(usize, 8), fixture.value.differences.len);
    for (fixture.value.differences, 759..) |row, expected_vector| {
        try std.testing.expectEqual(expected_vector, row.vector);
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(std.testing.allocator);
        for (row.scalars) |cp| {
            var buffer: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(cp, &buffer);
            try bytes.appendSlice(std.testing.allocator, buffer[0..len]);
        }
        var clusters = try uni.Graphemes.init(bytes.items);
        for (row.unicode17[1..]) |offset| {
            try std.testing.expect(clusters.next() != null);
            try std.testing.expectEqual(offset, clusters.offset);
        }
        try std.testing.expect(clusters.next() == null);
        try std.testing.expect(!std.mem.eql(usize, row.unicode17, row.swift));
        var e = (try text.delete(std.testing.allocator, bytes.items, .{ .anchor = 1, .head = 1 }, .backward)).?;
        defer e.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(bytes.items[row.unicode17[1]..], e.value);
    }
}
