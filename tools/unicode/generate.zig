//! Std-only, offline Unicode17 generator. Frozen inputs are hash checked before parsing.
const std = @import("std");
const Range = struct { lo: u21, hi: u21, value: u8 };
const Lower = struct { cp: u21, scalars: [3]u21, len: u8 };
const Source = struct { file: []const u8, url: []const u8, sha256: []const u8, bytes: usize };
const Manifest = struct { unicode: []const u8, uax29: []const u8, swift_revision: []const u8, inputs: []const Source };
const gcb_names = [_][]const u8{ "Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator", "Prepend", "SpacingMark", "L", "V", "T", "LV", "LVT" };
fn parseCode(raw: []const u8) !u21 {
    return std.fmt.parseInt(u21, std.mem.trim(u8, raw, " \t\r"), 16);
}
fn rangeLess(_: void, a: Range, b: Range) bool {
    return a.lo < b.lo;
}
fn lowerLess(_: void, a: Lower, b: Lower) bool {
    return a.cp < b.cp;
}
fn properties(gpa: std.mem.Allocator, bytes: []const u8, kind: enum { gcb, incb, pictographic, alphabetic }) ![]Range {
    var out: std.ArrayList(Range) = .empty;
    errdefer out.deinit(gpa);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw[0..(std.mem.indexOfScalar(u8, raw, '#') orelse raw.len)], " \t\r");
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ';');
        const span = std.mem.trim(u8, parts.next() orelse return error.BadProperty, " \t");
        const prop = std.mem.trim(u8, parts.next() orelse return error.BadProperty, " \t");
        var value: u8 = 0;
        switch (kind) {
            .gcb => {
                for (gcb_names, 0..) |name, i| {
                    if (std.mem.eql(u8, prop, name)) {
                        value = @intCast(i);
                        break;
                    }
                }
                if (value == 0) return error.UnknownGcb;
            },
            .incb => {
                if (!std.mem.eql(u8, prop, "InCB")) continue;
                const sub = std.mem.trim(u8, parts.next() orelse return error.BadIncb, " \t");
                value = if (std.mem.eql(u8, sub, "Consonant")) 1 else if (std.mem.eql(u8, sub, "Extend")) 2 else if (std.mem.eql(u8, sub, "Linker")) 3 else return error.UnknownIncb;
            },
            .pictographic => {
                if (!std.mem.eql(u8, prop, "Extended_Pictographic")) continue;
                value = 1;
            },
            .alphabetic => {
                if (!std.mem.eql(u8, prop, "Alphabetic")) continue;
                value = 1;
            },
        }
        const dots = std.mem.indexOf(u8, span, "..");
        const lo = try parseCode(if (dots) |d| span[0..d] else span);
        const hi = if (dots) |d| try parseCode(span[d + 2 ..]) else lo;
        if (hi < lo) return error.BadRange;
        try out.append(gpa, .{ .lo = lo, .hi = hi, .value = value });
    }
    std.mem.sort(Range, out.items, {}, rangeLess);
    var kept: usize = 0;
    for (out.items) |r| {
        if (kept > 0 and r.lo <= @as(u32, out.items[kept - 1].hi) + 1 and r.value == out.items[kept - 1].value) {
            out.items[kept - 1].hi = @max(r.hi, out.items[kept - 1].hi);
        } else {
            if (kept > 0 and r.lo <= out.items[kept - 1].hi) return error.OverlappingRange;
            out.items[kept] = r;
            kept += 1;
        }
    }
    out.items.len = kept;
    return out.toOwnedSlice(gpa);
}
fn mappings(gpa: std.mem.Allocator, unicode_data: []const u8, special: []const u8) ![]Lower {
    var map: std.AutoHashMap(u21, Lower) = .init(gpa);
    defer map.deinit();
    var lines = std.mem.splitScalar(u8, unicode_data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');
        const cp = try parseCode(fields.next() orelse return error.BadUnicodeData);
        for (1..13) |_| _ = fields.next() orelse return error.BadUnicodeData;
        const lower = fields.next() orelse return error.BadUnicodeData;
        if (lower.len > 0) try map.put(cp, .{ .cp = cp, .scalars = .{ try parseCode(lower), 0, 0 }, .len = 1 });
    }
    lines = std.mem.splitScalar(u8, special, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw[0..(std.mem.indexOfScalar(u8, raw, '#') orelse raw.len)], " \t\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');
        const cp = try parseCode(fields.next() orelse return error.BadSpecialCasing);
        const lower = fields.next() orelse return error.BadSpecialCasing;
        _ = fields.next() orelse return error.BadSpecialCasing;
        _ = fields.next() orelse return error.BadSpecialCasing;
        if (std.mem.trim(u8, fields.next() orelse "", " \t").len > 0) continue;
        var item: Lower = .{ .cp = cp, .scalars = .{ 0, 0, 0 }, .len = 0 };
        var codes = std.mem.tokenizeAny(u8, lower, " \t");
        while (codes.next()) |code| {
            if (item.len == 3) return error.MappingTooLong;
            item.scalars[item.len] = try parseCode(code);
            item.len += 1;
        }
        if (item.len == 0) return error.EmptyLowercase;
        if (item.len == 1 and item.scalars[0] == cp) _ = map.remove(cp) else try map.put(cp, item);
    }
    var out: std.ArrayList(Lower) = .empty;
    errdefer out.deinit(gpa);
    var it = map.valueIterator();
    while (it.next()) |item| try out.append(gpa, item.*);
    std.mem.sort(Lower, out.items, {}, lowerLess);
    return out.toOwnedSlice(gpa);
}
fn emit(out: *std.ArrayList(u8), gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const bytes = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(bytes);
    try out.appendSlice(gpa, bytes);
}
fn emitRanges(out: *std.ArrayList(u8), gpa: std.mem.Allocator, name: []const u8, ranges: []const Range) !void {
    const description = if (std.mem.eql(u8, name, "gcb")) "Grapheme-break property ranges, sorted by scalar; values index the runtime Gcb enum." else if (std.mem.eql(u8, name, "incb")) "Indic-conjunct property ranges, sorted by scalar; values index the runtime Incb enum." else if (std.mem.eql(u8, name, "pictographic")) "Extended-pictographic scalar ranges; nonzero values indicate membership." else "Apple-pinned alphabetic scalar ranges; nonzero values indicate membership.";
    try emit(out, gpa, "/// {s}\npub const {s} = [_]Range{{\n", .{ description, name });
    for (ranges) |r| try emit(out, gpa, "    .{{ .lo = 0x{x}, .hi = 0x{x}, .value = {d} }},\n", .{ r.lo, r.hi, r.value });
    try out.appendSlice(gpa, "};\n");
}
fn read(gpa: std.mem.Allocator, io: std.Io, name: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(gpa, "tests/unicode/data/{s}", .{name});
    defer gpa.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024));
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 or (!std.mem.eql(u8, args[1], "check") and !std.mem.eql(u8, args[1], "write"))) return error.ExpectedCheckOrWrite;
    const gpa = init.gpa;
    const manifest_bytes = try read(gpa, init.io, "provenance.json");
    defer gpa.free(manifest_bytes);
    const manifest = try std.json.parseFromSlice(Manifest, gpa, manifest_bytes, .{});
    defer manifest.deinit();
    if (!std.mem.eql(u8, manifest.value.unicode, "17.0.0") or !std.mem.eql(u8, manifest.value.swift_revision, "95c5142e84b82c1") or manifest.value.inputs.len != 9) return error.WrongVersion;
    for (manifest.value.inputs) |source| {
        const bytes = try read(gpa, init.io, source.file);
        defer gpa.free(bytes);
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
        const hex = std.fmt.bytesToHex(hash, .lower);
        if (bytes.len != source.bytes or !std.mem.eql(u8, &hex, source.sha256)) return error.SourceHashMismatch;
    }
    const gcb_bytes = try read(gpa, init.io, "GraphemeBreakProperty.txt");
    defer gpa.free(gcb_bytes);
    const dcp_bytes = try read(gpa, init.io, "DerivedCoreProperties.txt");
    defer gpa.free(dcp_bytes);
    const emoji_bytes = try read(gpa, init.io, "emoji-data.txt");
    defer gpa.free(emoji_bytes);
    const apple_dcp = try read(gpa, init.io, "AppleDerivedCoreProperties.txt");
    defer gpa.free(apple_dcp);
    const apple_ud = try read(gpa, init.io, "AppleUnicodeData.txt");
    defer gpa.free(apple_ud);
    const special = try read(gpa, init.io, "SpecialCasing.txt");
    defer gpa.free(special);
    const gs = try properties(gpa, gcb_bytes, .gcb);
    defer gpa.free(gs);
    const is = try properties(gpa, dcp_bytes, .incb);
    defer gpa.free(is);
    const eps = try properties(gpa, emoji_bytes, .pictographic);
    defer gpa.free(eps);
    const alpha = try properties(gpa, apple_dcp, .alphabetic);
    defer gpa.free(alpha);
    const lower = try mappings(gpa, apple_ud, special);
    defer gpa.free(lower);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, "//! GENERATED by tools/unicode/generate.zig; do not edit.\n//! Unicode data copyright 1991-2026 Unicode, Inc.; Unicode License V3.\n//! Copyright and permission notice: tests/unicode/data/LICENSE.txt.\n//! Segmentation: Unicode17 common UCD. Control casing: pinned Swift Apple UCD.\n//! Input URLs, versions and SHA256: tests/unicode/data/provenance.json.\n/// Inclusive scalar interval carrying a table-specific property value.\npub const Range = struct {\n    /// First scalar included in the interval.\n    lo: u21,\n    /// Last scalar included in the interval.\n    hi: u21,\n    /// Property discriminant interpreted by the consuming table.\n    value: u8,\n};\n/// Default lowercase expansion for one source scalar.\npub const Lower = struct {\n    /// Source scalar to map.\n    cp: u21,\n    /// Mapped scalars; only the prefix selected by len is meaningful.\n    scalars: [3]u21,\n    /// Number of mapped scalars, in the range 1...3.\n    len: u8,\n};\n");
    try emitRanges(&out, gpa, "gcb", gs);
    try emitRanges(&out, gpa, "incb", is);
    try emitRanges(&out, gpa, "pictographic", eps);
    try emitRanges(&out, gpa, "alphabetic", alpha);
    try out.appendSlice(gpa, "/// Lowercase expansions sorted by source scalar; omitted scalars map to themselves.\npub const lowercase = [_]Lower{\n");
    for (lower) |r| try emit(&out, gpa, "    .{{ .cp = 0x{x}, .scalars = .{{ 0x{x}, 0x{x}, 0x{x} }}, .len = {d} }},\n", .{ r.cp, r.scalars[0], r.scalars[1], r.scalars[2], r.len });
    try out.appendSlice(gpa, "};\n");
    // Format in-process using the compiler's std AST formatter, no subprocess/tool dependency.
    const sentinel = try gpa.dupeSentinel(u8, out.items, 0);
    defer gpa.free(sentinel);
    var ast = try std.zig.Ast.parse(gpa, sentinel, .{ .mode = .zig });
    defer ast.deinit(gpa);
    if (ast.errors.len != 0) return error.InvalidGeneratedZig;
    const rendered = try ast.renderAlloc(gpa);
    defer gpa.free(rendered);
    if (std.mem.eql(u8, args[1], "write")) {
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = "src/core/unicode/tables.zig", .data = rendered });
    } else {
        const current = try std.Io.Dir.cwd().readFileAlloc(init.io, "src/core/unicode/tables.zig", gpa, .limited(4 * 1024 * 1024));
        defer gpa.free(current);
        if (!std.mem.eql(u8, current, rendered)) return error.GeneratedTableDrift;
    }
    std.debug.print("Unicode17 tables {s}: {d} GCB, {d} InCB, {d} EP, {d} alphabetic ranges, {d} lowercase mappings\n", .{ args[1], gs.len, is.len, eps.len, alpha.len, lower.len });
}

test "property parser handles defaults duplicate binary ranges and rejects conflicting overlaps" {
    const gpa = std.testing.allocator;
    const alpha = try properties(gpa, "F882 ; Alphabetic\nF882 ; Alphabetic\n0041..005A ; Alphabetic\n0000..001F ; Lowercase\n", .alphabetic);
    defer gpa.free(alpha);
    try std.testing.expectEqual(@as(usize, 2), alpha.len);
    try std.testing.expectEqual(@as(u21, 0x41), alpha[0].lo);
    try std.testing.expectError(error.UnknownGcb, properties(gpa, "0041 ; Unknown\n", .gcb));
    try std.testing.expectError(error.OverlappingRange, properties(gpa, "0041..0043 ; Extend\n0042 ; CR\n", .gcb));
    try std.testing.expectError(error.BadRange, properties(gpa, "0043..0041 ; Extend\n", .gcb));
    try std.testing.expectError(error.UnknownIncb, properties(gpa, "0041 ; InCB ; Invalid\n", .incb));
}
test "lowercase parser preserves unconditional full mappings and ignores context" {
    const lower = try mappings(std.testing.allocator, "0041;A;Lu;0;L;;;;;N;;;;0061;\n0130;I;Lu;0;L;;;;;N;;;;0069;\n03A3;S;Lu;0;L;;;;;N;;;;03C3;\n", "0130; 0069 0307; 0130; 0130; # unconditional\n03A3; 03C2; 03A3; 03A3; Final_Sigma;\n");
    defer std.testing.allocator.free(lower);
    try std.testing.expectEqual(@as(usize, 3), lower.len);
    try std.testing.expectEqual(@as(u8, 2), lower[1].len);
    try std.testing.expectEqual([3]u21{ 0x69, 0x307, 0 }, lower[1].scalars);
    try std.testing.expectEqual(@as(u21, 0x3c3), lower[2].scalars[0]);
    try std.testing.expectError(error.MappingTooLong, mappings(std.testing.allocator, "", "0041; 0061 0062 0063 0064; 0041; 0041;\n"));
}
fn parserAllocationExercise(gpa: std.mem.Allocator) !void {
    const ranges = try properties(gpa, "0041..005A ; Alphabetic\n0061..007A ; Alphabetic\n", .alphabetic);
    defer gpa.free(ranges);
    const lower = try mappings(gpa, "0041;A;Lu;0;L;;;;;N;;;;0061;\n", "0130; 0069 0307; 0130; 0130;\n");
    defer gpa.free(lower);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try emitRanges(&out, gpa, "alphabetic", ranges);
}
test "generator parser and output every allocation failure cleans up" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parserAllocationExercise, .{});
}
