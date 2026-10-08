const std = @import("std");
const g = @import("gama");
const a = std.testing.allocator;
test "drawing owns graphemes and swaps only after preparation" {
    var b = try g.draw.CellBuffer.init(a, .{ .width = 5, .height = 1 });
    defer b.deinit();
    try b.put(0, 0, "中", .plain);
    try b.put(2, 0, "é", .plain);
    const out = try g.draw.AnsiPresenter.prepare(a, &b);
    defer a.free(out);
    try std.testing.expectEqualStrings(" ", b.front.cells[0].glyph);
    g.draw.AnsiPresenter.promote(&b);
    try std.testing.expectEqualStrings("中", b.front.cells[0].glyph);
}
const geo = g.geometry;
const draw = g.draw;
fn fixtureNode(ctx: *g.BuildContext) !g.Node {
    const row = [_]g.Node{ .{ .text = .{ .content = "x" } }, .{ .spacer = 1 }, .{ .text = .{ .content = "end" } } };
    const column = [_]g.Node{ .{ .text = .{ .content = "A<&中", .style = .{ .attributes = g.style.Attributes.bold } } }, .{ .stack = .{ .axis = .horizontal, .spacing = 1, .alignment = .top_leading, .children = &row } } };
    return ctx.retain(.{ .border = .{ .style = .rounded, .title = "T", .text_style = .{ .foreground = .red }, .child = &.{ .padding = .{ .insets = .{ .top = 1, .leading = 1, .bottom = 1, .trailing = 1 }, .child = &.{ .stack = .{ .axis = .vertical, .spacing = 1, .alignment = .top_leading, .children = &column } } } } } });
}
fn compareCells(b: *const draw.CellBuffer, entries: std.json.Value) !void {
    try std.testing.expectEqual(b.back.cells.len, entries.array.items.len);
    for (entries.array.items) |entry| {
        const o = entry.object;
        const cell = b.cell(o.get("x").?.integer, o.get("y").?.integer).?;
        try std.testing.expectEqualStrings(o.get("text").?.string, cell.glyph);
        try std.testing.expectEqual(o.get("continuation").?.bool, cell.continuation);
        try std.testing.expectEqual(o.get("sgr").?.integer, cell.style.attributes);
    }
}
test "all frozen drawing cells rows wire HTML ANSI and chronology bytes" {
    inline for (.{ "16x8", "9x5" }, .{ geo.Size{ .width = 16, .height = 8 }, geo.Size{ .width = 9, .height = 5 } }) |name, size| {
        var storage = g.FrameStorage.init(a);
        defer storage.deinit();
        var ctx = storage.context();
        const tree = try g.layout.place(ctx.allocator, try fixtureNode(&ctx), .{ .size = size }, .{});
        var b = try draw.CellBuffer.init(a, size);
        defer b.deinit();
        try draw.paint(&b, tree);
        const json = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/layout-" ++ name ++ ".json"), .{});
        defer json.deinit();
        try compareCells(&b, json.value.object.get("cells").?);
        var list = try draw.DrawListSerializer.serialize(a, &b);
        defer list.deinit();
        const wire = try list.encode(a);
        defer a.free(wire);
        try std.testing.expectEqualSlices(u8, @embedFile("parity/swift-baseline/layout-" ++ name ++ ".gama"), wire);
        const html = try draw.HTMLSerializer.serialize(a, &b);
        defer a.free(html);
        try std.testing.expectEqualStrings(@embedFile("parity/swift-baseline/layout-" ++ name ++ ".html"), html);
        const ansi = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/layout-" ++ name ++ "-ansi.json"), .{});
        defer ansi.deinit();
        const plain = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/layout-" ++ name ++ "-plain.json"), .{});
        defer plain.deinit();
        var lines = try draw.StreamPresenter.prepare(a, &b);
        defer lines.deinit(a);
        const expected_lines = plain.value.object.get("initial").?.array.items;
        try std.testing.expectEqual(expected_lines.len, lines.items.len);
        for (lines.items, expected_lines) |actual, expected| try std.testing.expectEqualStrings(expected.string, actual);
        const initial = try draw.AnsiPresenter.present(a, &b);
        defer a.free(initial);
        try std.testing.expectEqualStrings(ansi.value.object.get("initial").?.string, initial);
        // Capture sequence: repaint after first swap; unchanged swap leaves a full old frame in back.
        try draw.paint(&b, tree);
        const unchanged = try draw.AnsiPresenter.present(a, &b);
        defer a.free(unchanged);
        try std.testing.expectEqualStrings(ansi.value.object.get("unchanged").?.string, unchanged);
        var clean = try draw.StreamPresenter.prepare(a, &b);
        defer clean.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), clean.items.len);
        try b.put(0, 0, "Z", .plain);
        const changed = try draw.AnsiPresenter.present(a, &b);
        defer a.free(changed);
        try std.testing.expectEqualStrings(ansi.value.object.get("changed").?.string, changed);
    }
}
test "all six frozen GAMA files decode encode exact and every truncation fails" {
    inline for (.{ "layout-16x8", "layout-9x5", "embed-initial", "embed-increment", "c-embed-initial", "c-embed-increment" }) |name| {
        const bytes = @embedFile("parity/swift-baseline/" ++ name ++ ".gama");
        var decoded = try draw.DrawList.decode(a, bytes);
        defer decoded.deinit();
        const encoded = try decoded.encode(a);
        defer a.free(encoded);
        try std.testing.expectEqualSlices(u8, bytes, encoded);
        for (0..bytes.len) |end| {
            if (draw.DrawList.decode(a, bytes[0..end])) |value| {
                var invalid = value;
                invalid.deinit();
                return error.AcceptedTruncation;
            } else |_| {}
        }
    }
}
test "frozen wide-cell overwrite complete plane" {
    const json = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/wide-cell-overwrite.json"), .{});
    defer json.deinit();
    var b = try draw.CellBuffer.init(a, .{ .width = 5, .height = 1 });
    defer b.deinit();
    try b.putText(0, 0, "中é✈️", .plain, 5);
    try compareCells(&b, json.value.object.get("initial").?);
    try b.put(1, 0, "x", .plain);
    try compareCells(&b, json.value.object.get("overwriteContinuation").?);
}
test "normalization zero product shapes no-op resize and hostile bounded painting" {
    const max = std.math.maxInt(i64);
    var b = try draw.CellBuffer.init(a, .{ .width = 3, .height = 2 });
    defer b.deinit();
    try b.put(0, 0, "q", .plain);
    try b.resizeIfNeeded(.{ .width = 3, .height = 2 });
    try std.testing.expectEqualStrings("q", b.cell(0, 0).?.glyph);
    try b.resize(.{ .width = 3, .height = 2 });
    try std.testing.expectEqualStrings(" ", b.cell(0, 0).?.glyph);
    for ([_]geo.Size{ .{ .width = -1, .height = 2 }, .{ .width = max, .height = 2 }, .{ .width = 4097, .height = 4096 } }) |size| {
        try b.resize(size);
        try std.testing.expectEqual(geo.Size{}, b.size);
        b.force_full = false;
        try b.resizeIfNeeded(size);
        try std.testing.expect(!b.force_full);
    }
    for ([_]geo.Size{ .{ .width = max, .height = 0 }, .{ .width = 0, .height = max } }) |size| {
        try b.resize(size);
        try std.testing.expectEqual(size, b.size);
        try std.testing.expectEqual(size.height > 0, b.rowChanged(0));
        var empty_list = try draw.DrawList.from(a, &b);
        defer empty_list.deinit();
        const empty_wire = try empty_list.encode(a);
        defer a.free(empty_wire);
        try std.testing.expectEqualSlices(u8, &header(@intCast(@min(size.width, std.math.maxInt(i32))), @intCast(@min(size.height, std.math.maxInt(i32))), 0), empty_wire);
        try draw.paint(&b, .{ .node = .{ .border = .{ .child = &.empty } }, .frame = .{ .size = .{ .width = max, .height = max } } });
        const ansi = try draw.AnsiPresenter.present(a, &b);
        defer a.free(ansi);
        try std.testing.expectEqual(@as(usize, 0), ansi.len);
        try std.testing.expect(!b.force_full and !b.rowChanged(0));
        var lines = try draw.StreamPresenter.present(a, &b);
        defer lines.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), lines.items.len);
        const html = try draw.HTMLSerializer.serialize(a, &b);
        defer a.free(html);
        try std.testing.expectEqualStrings("", html);
    }
    try b.resize(.{ .width = 3, .height = 2 });
    const hostile = [_]geo.Rect{ .{ .origin = .{ .x = std.math.minInt(i64), .y = std.math.minInt(i64) }, .size = .{ .width = max, .height = max } }, .{ .size = .{ .width = max, .height = max } }, .{ .origin = .{ .x = max - 1, .y = max - 1 }, .size = .{ .width = max, .height = max } } };
    for (hostile) |rect| {
        try draw.paint(&b, .{ .node = .{ .border = .{ .child = &.empty } }, .frame = rect });
        try draw.paint(&b, .{ .node = .{ .divider = .{ .axis = .horizontal } }, .frame = rect });
        try draw.paint(&b, .{ .node = .{ .divider = .{ .axis = .vertical } }, .frame = rect });
        try b.fill(rect, .{ .glyph = "X" });
        b.fillBackground(rect, .blue);
    }
}
test "destructive zero-width final-column writes raw cells and split continuation runs" {
    var b = try draw.CellBuffer.init(a, .{ .width = 3, .height = 1 });
    defer b.deinit();
    try b.put(0, 0, "中", .{ .foreground = .red });
    try b.put(1, 0, "\u{301}", .plain);
    try std.testing.expectEqualStrings(" ", b.cell(0, 0).?.glyph);
    try std.testing.expect(!b.cell(1, 0).?.continuation);
    try b.put(1, 0, "中", .plain);
    try b.put(2, 0, "✈️", .plain);
    try std.testing.expectEqualStrings(" ", b.cell(1, 0).?.glyph);
    try std.testing.expectEqualStrings(" ", b.cell(2, 0).?.glyph);
    const rect: geo.Rect = .{ .size = b.size };
    try b.fill(rect, .{ .glyph = "中" });
    for (b.back.cells) |cell| {
        try std.testing.expectEqualStrings("中", cell.glyph);
        try std.testing.expect(!cell.continuation);
    }
    try b.fill(rect, .{ .glyph = "\u{301}" });
    for (b.back.cells) |cell| try std.testing.expectEqualStrings("\u{301}", cell.glyph);
    try b.fill(rect, .{ .continuation = true });
    // Raw continuation fill uses the legacy linear overlap clearing rule.
    try std.testing.expect(b.cell(2, 0).?.continuation);
    b.clearBack();
    try b.put(0, 0, "中", .plain);
    b.fillBackground(.{ .origin = .{ .x = 1 }, .size = .{ .width = 1, .height = 1 } }, .red);
    var runs = b.runs();
    const lead = runs.next().?;
    const continuation = runs.next().?;
    try std.testing.expectEqual(@as(i64, 1), lead.width);
    try std.testing.expectEqual(@as(i64, 1), continuation.column);
    var list = try draw.DrawList.from(a, &b);
    defer list.deinit();
    try std.testing.expectEqual(@as(usize, 2), list.commands.len);
    try std.testing.expectEqualStrings("中", list.commands[0].text.value);
    try std.testing.expectEqual(@as(i64, 1), list.commands[1].fill.rect.origin.x);
}
fn putNode(b: *draw.CellBuffer, node: g.Node, rect: geo.Rect, children: []const g.layout.LaidNode) !void {
    try draw.paint(b, .{ .node = node, .frame = rect, .children = children });
}
test "source-derived painter style precedence backdrop overflow and zero-width text" {
    var b = try draw.CellBuffer.init(a, .{ .width = 8, .height = 4 });
    defer b.deinit();
    const child: g.layout.LaidNode = .{ .node = .{ .text = .{ .content = "A B C", .style = .{ .foreground = .blue } } }, .frame = .{ .size = .{ .width = 0, .height = 0 } } };
    const outer: g.TextStyle = .{ .foreground = .red, .background = .green, .attributes = g.style.Attributes.italic };
    try putNode(&b, .{ .styled = .{ .style = outer, .child = &.empty } }, .{ .size = .{ .width = 1, .height = 1 } }, &.{child});
    try std.testing.expectEqual(g.Color.red, b.cell(0, 0).?.style.foreground);
    try std.testing.expectEqual(g.Color.green, b.cell(0, 2).?.style.background); // no height/ancestor clip
    try std.testing.expectEqualStrings("C", b.cell(0, 2).?.glyph);
    b.clearBack();
    try putNode(&b, .{ .background = .{ .color = .green, .child = &.empty } }, .{ .size = b.size }, &.{child});
    try std.testing.expect(b.cell(0, 0).?.style.background.is_default);
    try std.testing.expectEqual(g.Color.green, b.cell(1, 0).?.style.background);
    const border: g.layout.LaidNode = .{ .node = .{ .border = .{ .text_style = .{ .foreground = .blue }, .child = &.empty } }, .frame = .{ .size = .{ .width = 3, .height = 3 } } };
    const divider: g.layout.LaidNode = .{ .node = .{ .divider = .{ .style = .{ .foreground = .cyan }, .axis = .vertical } }, .frame = .{ .origin = .{ .x = 4 }, .size = .{ .width = 2, .height = 1 } } };
    try putNode(&b, .{ .styled = .{ .style = outer, .child = &.empty } }, .{ .size = b.size }, &.{ border, divider });
    try std.testing.expectEqual(g.Color.blue, b.cell(0, 0).?.style.foreground);
    try std.testing.expectEqual(g.Color.cyan, b.cell(4, 0).?.style.foreground);
    try std.testing.expect(b.cell(4, 0).?.style.attributes & g.style.Attributes.italic != 0);
}
test "all border glyph families multiline titles and divider explicit and inferred orientation" {
    var b = try draw.CellBuffer.init(a, .{ .width = 12, .height = 4 });
    defer b.deinit();
    inline for (.{ g.style.BorderStyle.single, .double, .rounded, .heavy, .ascii }, .{ "┌─┐││└─┘", "╔═╗║║╚═╝", "╭─╮││╰─╯", "┏━┓┃┃┗━┛", "+-+||+-+" }) |kind, expected| {
        b.clearBack();
        try putNode(&b, .{ .border = .{ .style = kind, .child = &.empty } }, .{ .size = .{ .width = 3, .height = 3 } }, &.{});
        var it = try g.unicode.Graphemes.init(expected);
        for ([_][2]i64{ .{ 0, 0 }, .{ 1, 0 }, .{ 2, 0 }, .{ 0, 1 }, .{ 2, 1 }, .{ 0, 2 }, .{ 1, 2 }, .{ 2, 2 } }) |xy| try std.testing.expectEqualStrings(it.next().?, b.cell(xy[0], xy[1]).?.glyph);
    }
    b.clearBack();
    try putNode(&b, .{ .border = .{ .title = "a\nb", .child = &.empty } }, .{ .size = .{ .width = 12, .height = 2 } }, &.{});
    try std.testing.expectEqualStrings("b", b.cell(1, 1).?.glyph);
    try std.testing.expect(b.cell(1, 1).?.style.attributes & 1 != 0);
    b.clearBack();
    try putNode(&b, .{ .divider = .{ .axis = .horizontal } }, .{ .size = .{ .width = 3, .height = 1 } }, &.{});
    try std.testing.expectEqualStrings("│", b.cell(0, 0).?.glyph);
    try std.testing.expectEqualStrings(" ", b.cell(1, 0).?.glyph);
    b.clearBack();
    try putNode(&b, .{ .divider = .{} }, .{ .size = .{ .width = 2, .height = 2 } }, &.{});
    try std.testing.expectEqualStrings("─", b.cell(1, 0).?.glyph);
    b.clearBack();
    try putNode(&b, .{ .divider = .{} }, .{ .size = .{ .width = 1, .height = 3 } }, &.{});
    try std.testing.expectEqualStrings("│", b.cell(0, 2).?.glyph);
}
test "independent wire golden all fields saturate and decoder canonicalization" {
    const cmds = [_]draw.DrawCommand{
        .{ .fill = .{ .rect = .{ .origin = .{ .x = 1, .y = 2 }, .size = .{ .width = 3, .height = 4 } }, .color = .init(5, 6, 7) } },
        .{ .text = .{ .at = .{ .x = 8, .y = 9 }, .style = .{ .foreground = .init(10, 11, 12), .background = .default, .attributes = 0xff }, .value = "A" } },
    };
    var list = try draw.DrawList.init(a, .{ .width = 10, .height = 20 }, &cmds);
    defer list.deinit();
    const expected = [_]u8{ 0x47, 0x41, 0x4d, 0x41, 1, 0, 0, 0, 10, 0, 0, 0, 20, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 5, 6, 7, 0, 1, 8, 0, 0, 0, 9, 0, 0, 0, 10, 11, 12, 0, 0, 0, 0, 1, 255, 0, 1, 0, 0, 0, 65 };
    const encoded = try list.encode(a);
    defer a.free(encoded);
    try std.testing.expectEqualSlices(u8, &expected, encoded);
    var modified = expected;
    modified[37] = 31;
    modified[38] = 32;
    modified[39] = 33;
    modified[40] = 0x81;
    modified[53] = 0x80; // concrete foreground, reserved flags ignored
    modified[59] = 0xab; // high SGR byte truncates
    var decoded = try draw.DrawList.decode(a, &modified);
    defer decoded.deinit();
    try std.testing.expectEqual(g.Color.default, decoded.commands[0].fill.color);
    try std.testing.expectEqual(@as(u8, 255), decoded.commands[1].text.style.attributes);
    const canonical = try decoded.encode(a);
    defer a.free(canonical);
    try std.testing.expectEqual(@as(u8, 0), canonical[37]);
    try std.testing.expectEqual(@as(u8, 1), canonical[40]);
    try std.testing.expectEqual(@as(u8, 0), canonical[59]);
    try std.testing.expectEqual(@as(u8, 0), canonical[53]);
    try std.testing.expectEqual(g.Color.init(10, 11, 12), decoded.commands[1].text.style.foreground);
    const hi = std.math.maxInt(i64);
    const lo = std.math.minInt(i64);
    var saturated = try draw.DrawList.init(a, .{ .width = hi, .height = lo }, &.{ .{ .fill = .{ .rect = .{ .origin = .{ .x = hi, .y = lo }, .size = .{ .width = hi, .height = lo } }, .color = .default } }, .{ .text = .{ .at = .{ .x = lo, .y = hi }, .style = .plain, .value = "" } } });
    defer saturated.deinit();
    const bytes = try saturated.encode(a);
    defer a.free(bytes);
    for ([_]usize{ 8, 21, 29, 46 }) |offset| try std.testing.expectEqual(std.math.maxInt(i32), std.mem.readInt(i32, bytes[offset..][0..4], .little));
    for ([_]usize{ 12, 25, 33, 42 }) |offset| try std.testing.expectEqual(std.math.minInt(i32), std.mem.readInt(i32, bytes[offset..][0..4], .little));
}
fn header(w: i32, h: i32, count: u32) [20]u8 {
    var b: [20]u8 = undefined;
    @memcpy(b[0..4], "GAMA");
    std.mem.writeInt(u32, b[4..8], 1, .little);
    std.mem.writeInt(i32, b[8..12], w, .little);
    std.mem.writeInt(i32, b[12..16], h, .little);
    std.mem.writeInt(u32, b[16..20], count, .little);
    return b;
}
test "decoder precedence payload bounds negative rect UTF8 and metadata-only dimensions" {
    try std.testing.expectError(error.Truncated, draw.DrawList.decode(a, "GAM"));
    try std.testing.expectError(error.BadMagic, draw.DrawList.decode(a, "xxxx"));
    try std.testing.expectError(error.UnsupportedVersion, draw.DrawList.decode(a, "GAMA\x02\x00\x00\x00"));
    try std.testing.expectError(error.NegativeDimensions, draw.DrawList.decode(a, &header(-1, 1, 999)));
    try std.testing.expectError(error.CommandCountOverflow, draw.DrawList.decode(a, &header(1, 1, std.math.maxInt(u32))));
    var short: [40]u8 = @splat(0);
    @memcpy(short[0..20], &header(1, 1, 1));
    try std.testing.expectError(error.CommandCountOverflow, draw.DrawList.decode(a, short[0..36]));
    try std.testing.expectError(error.Truncated, draw.DrawList.decode(a, short[0..37])); // deliberately baseline /17, not /21
    short[20] = 99;
    try std.testing.expectError(error.UnknownCommandKind, draw.DrawList.decode(a, short[0..37]));
    var fill: [41]u8 = @splat(0);
    @memcpy(fill[0..20], &header(1, 1, 1));
    std.mem.writeInt(i32, fill[29..33], -1, .little);
    try std.testing.expectError(error.Truncated, draw.DrawList.decode(a, fill[0..40]));
    try std.testing.expectError(error.NegativeRect, draw.DrawList.decode(a, &fill));
    var trailing: [21]u8 = @splat(0);
    @memcpy(trailing[0..20], &header(0, 0, 0));
    try std.testing.expectError(error.TrailingBytes, draw.DrawList.decode(a, &trailing));
    var huge = try draw.DrawList.decode(a, &header(std.math.maxInt(i32), std.math.maxInt(i32), 0));
    defer huge.deinit();
    var buffer = try draw.CellBuffer.init(a, huge.size);
    defer buffer.deinit();
    try std.testing.expectEqual(geo.Size{}, buffer.size);
    for ([_][]const u8{ "\x80", "\xc0\x80", "\xc2", "\xe0\x80\x80", "\xed\xa0\x80", "\xf0\x80\x80\x80", "\xf4\x90\x80\x80", "\xf5\x80\x80\x80", "\xe2\x28\xa1" }) |invalid| {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(a);
        try bytes.appendSlice(a, &header(1, 1, 1));
        try bytes.append(a, 1);
        try bytes.appendNTimes(a, 0, 18);
        var len: [4]u8 = undefined;
        std.mem.writeInt(u32, &len, @intCast(invalid.len), .little);
        try bytes.appendSlice(a, &len);
        try bytes.appendSlice(a, invalid);
        try std.testing.expectError(error.InvalidUtf8, draw.DrawList.decode(a, bytes.items));
        std.mem.writeInt(u32, bytes.items[39..43], std.math.maxInt(u32), .little);
        try std.testing.expectError(error.Truncated, draw.DrawList.decode(a, bytes.items));
    }
    var controls = try draw.DrawList.init(a, .{}, &.{.{ .text = .{ .at = .{ .x = -100, .y = 100 }, .style = .plain, .value = "\x00\r\n\t\u{ffff}" } }});
    defer controls.deinit();
    const bytes = try controls.encode(a);
    defer a.free(bytes);
    var decoded = try draw.DrawList.decode(a, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings(controls.commands[0].text.value, decoded.commands[0].text.value);
}
test "deterministic malformed corpus mutations canonical valid roundtrips" {
    var random = std.Random.DefaultPrng.init(0x47414d41);
    const rng = random.random();
    const source = @embedFile("parity/swift-baseline/layout-9x5.gama");
    var scratch: [4096]u8 = undefined;
    var rejected: usize = 0;
    var accepted: usize = 0;
    for (0..4000) |iteration| {
        const n = if (iteration % 2 == 0) rng.uintLessThan(usize, 512) else source.len;
        if (iteration % 2 == 0) rng.bytes(scratch[0..n]) else {
            @memcpy(scratch[0..n], source);
            for (0..1 + iteration % 8) |_| scratch[rng.uintLessThan(usize, n)] = rng.int(u8);
        }
        if (draw.DrawList.decode(a, scratch[0..n])) |value| {
            var list = value;
            defer list.deinit();
            accepted += 1;
            const canonical = try list.encode(a);
            defer a.free(canonical);
            var again = try draw.DrawList.decode(a, canonical);
            defer again.deinit();
            const twice = try again.encode(a);
            defer a.free(twice);
            try std.testing.expectEqualSlices(u8, canonical, twice);
        } else |err| {
            try std.testing.expect(err != error.OutOfMemory);
            rejected += 1;
        }
    }
    try std.testing.expect(rejected > 2500 and accepted > 100);
}
test "ANSI styles palettes sparse erase wide and continuation-only changes" {
    var b = try draw.CellBuffer.init(a, .{ .width = 4, .height = 1 });
    defer b.deinit();
    const styled: g.TextStyle = .{ .foreground = .init(205, 0, 0), .background = .init(0, 0, 238), .attributes = 63 };
    inline for (.{ draw.cells.ColorDepth.unknown, .monochrome, .ansi16, .ansi256, .true_color }, .{ "\x1b[0;1;2;3;4;7;9m", "\x1b[0;1;2;3;4;7;9m", "\x1b[0;1;2;3;4;7;9;31;44m", "\x1b[0;1;2;3;4;7;9;38;5;160;48;5;21m", "\x1b[0;1;2;3;4;7;9;38;2;205;0;0;48;2;0;0;238m" }) |depth, sgr| {
        b.clearBack();
        b.force_full = true;
        b.color_depth = depth;
        try b.put(0, 0, "中", styled);
        const out = try draw.AnsiPresenter.prepare(a, &b);
        defer a.free(out);
        try std.testing.expectEqualStrings("\x1b[1;1H" ++ sgr ++ "中\x1b[0m  ", out);
    }
    b.color_depth = .unknown;
    const first = try draw.AnsiPresenter.present(a, &b);
    defer a.free(first);
    try b.put(0, 0, "中", styled); // repaint prior front
    b.fillBackground(.{ .origin = .{ .x = 1 }, .size = .{ .width = 1, .height = 1 } }, .green);
    const continuation = try draw.AnsiPresenter.present(a, &b);
    defer a.free(continuation);
    try std.testing.expectEqualStrings("", continuation);
    // palette-only mutation never dirties cells
    b.color_depth = .true_color;
    b.fillBackground(.{ .origin = .{ .x = 1 }, .size = .{ .width = 1, .height = 1 } }, .green);
    const palette = try draw.AnsiPresenter.present(a, &b);
    defer a.free(palette);
    try std.testing.expectEqualStrings("", palette);
    b.clearBack();
    const erase = try draw.AnsiPresenter.present(a, &b);
    defer a.free(erase);
    try std.testing.expectEqualStrings("\x1b[1;1H\x1b[0m  ", erase);
    b.clearBack();
    try b.put(3, 0, "Z", .plain);
    const sparse = try draw.AnsiPresenter.present(a, &b);
    defer a.free(sparse);
    try std.testing.expectEqualStrings("\x1b[1;4H\x1b[0mZ", sparse);
}
test "palette exact thresholds ties and plain style chronology" {
    for ([_]u8{ 0, 7, 8, 248, 249, 255 }, [_]u8{ 16, 16, 232, 255, 231, 231 }) |c, index| try std.testing.expectEqual(index, g.Color.init(c, c, c).xterm256());
    for ([_]u8{ 47, 48, 113, 114 }, [_]u8{ 16, 52, 52, 52 }) |c, index| try std.testing.expectEqual(index, g.Color.init(c, 0, 0).xterm256());
    // Integer threshold behavior follows the source cube rather than nearest-color quantization.
    var tie = try draw.CellBuffer.init(a, .{ .width = 1, .height = 1 });
    defer tie.deinit();
    tie.color_depth = .ansi16;
    try tie.put(0, 0, "x", .{ .foreground = .init(0, 0, 119) });
    const tied = try draw.AnsiPresenter.present(a, &tie);
    defer a.free(tied);
    try std.testing.expectEqualStrings("\x1b[1;1H\x1b[0;30mx", tied);
    var b = try draw.CellBuffer.init(a, .{ .width = 4, .height = 1 });
    defer b.deinit();
    try b.put(1, 0, "x", .plain);
    var first = try draw.StreamPresenter.present(a, &b);
    defer first.deinit(a);
    try std.testing.expectEqualStrings(" x", first.items[0]);
    try b.put(1, 0, "x", .{ .attributes = 1 });
    var style_change = try draw.StreamPresenter.present(a, &b);
    defer style_change.deinit(a);
    try std.testing.expectEqualStrings(" x", style_change.items[0]);
    b.clearBack();
    var erase = try draw.StreamPresenter.present(a, &b);
    defer erase.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), erase.items.len);
}
test "HTML full CSS order inverse unknown attributes grapheme escape and serializers never swap" {
    var b = try draw.CellBuffer.init(a, .{ .width = 1, .height = 1 });
    defer b.deinit();
    try b.put(0, 0, "&", .{ .foreground = .init(1, 2, 3), .background = .init(4, 5, 6), .attributes = 255 });
    const html = try draw.HTMLSerializer.serialize(a, &b);
    defer a.free(html);
    try std.testing.expectEqualStrings("<pre class=\"gama-row\"><span style=\"color:rgb(4,5,6);background:rgb(1,2,3);font-weight:bold;opacity:.6;font-style:italic;text-decoration:underline line-through;\">&amp;</span></pre>", html);
    var list = try draw.DrawListSerializer.serialize(a, &b);
    defer list.deinit();
    try std.testing.expect(b.force_full);
    try std.testing.expectEqualStrings(" ", b.front.cells[0].glyph);
    inline for (.{ "&́", "<́", ">́", "\"", "'" }) |cluster| {
        b.clearBack();
        try b.put(0, 0, cluster, .plain);
        const out = try draw.HTMLSerializer.serialize(a, &b);
        defer a.free(out);
        try std.testing.expectEqualStrings("<pre class=\"gama-row\"><span style=\"\">" ++ cluster ++ "</span></pre>", out);
    }
    b.clearBack();
    try b.put(0, 0, " ", .{ .attributes = 128 });
    var runs = b.runs();
    try std.testing.expectEqual(@as(u8, 128), runs.next().?.style.attributes);
}
const DrawingApp = struct {
    text_ref: ?g.StateRef(g.String) = null,
    presses: ?g.StateRef(i64) = null,
    show: bool = true,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn press(ref: *const g.StateRef(i64), _: *anyopaque) g.Error!void {
        try ref.set((try ref.read()).* + 1);
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.text_ref = try ctx.state(g.String, 1, .{ .bytes = "é✈️" });
        self.presses = try ctx.state(i64, 2, 0);
        if (!self.show) return .empty;
        const button = try g.authoring.buttonTitle(ctx, (try self.text_ref.?.read()).bytes, try ctx.action(self.presses.?, press));
        return button.render(ctx);
    }
};
test "drawing pump managed glyph lifetime abort replacement resize and clean publication" {
    var failure = std.testing.FailingAllocator.init(a, .{});
    const alloc = failure.allocator();
    var app: DrawingApp = .{};
    const host = try g.Host(DrawingApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.handle(.{ .resize = .{ .width = 12, .height = 2 } });
    var adapter = try g.DrawingPump(DrawingApp).init(alloc, host, .ansi);
    defer adapter.deinit();
    try std.testing.expect((try adapter.advance()).produced);
    const old_output = try a.dupe(u8, try host.currentOutput());
    defer a.free(old_output);
    const old_tree = (try host.currentTree()).?;
    const handle = (try host.actionHandle(g.NodeID.root)).?;
    const front = adapter.buffer.front.cells.ptr;
    try app.text_ref.?.set(.{ .bytes = "👩‍👩‍👧‍👦 NEW" }); // frees managed old text
    failure.fail_index = failure.alloc_index;
    try std.testing.expectError(error.OutOfMemory, adapter.advance());
    try std.testing.expect(front == adapter.buffer.front.cells.ptr);
    try std.testing.expect(old_tree == (try host.currentTree()).?);
    try std.testing.expectEqualStrings(old_output, try host.currentOutput());
    try std.testing.expect(try host.needsFrame());
    try std.testing.expect(try handle.invoke());
    try std.testing.expectEqual(@as(i64, 1), (try app.presses.?.read()).*);
    try std.testing.expectEqualStrings("👩‍👩‍👧‍👦 NEW", (try app.text_ref.?.read()).bytes);
    var found = false;
    for (adapter.buffer.front.cells) |cell| if (std.mem.eql(u8, cell.glyph, "é")) {
        found = true;
    };
    try std.testing.expect(found);
    failure.fail_index = std.math.maxInt(usize);
    try std.testing.expect((try adapter.advance()).produced); // frees old Host arena
    try std.testing.expectError(error.InvalidHandle, handle.invoke());
    found = false;
    for (adapter.buffer.front.cells) |cell| if (std.mem.eql(u8, cell.glyph, "👩‍👩‍👧‍👦")) {
        found = true;
    };
    try std.testing.expect(found);
    // The old front was cloned into the new back; its original host and
    // raster arenas are now gone. Borrow and serialize that retained plane.
    found = false;
    for (adapter.buffer.back.cells) |cell| if (std.mem.eql(u8, cell.glyph, "é")) {
        found = true;
    };
    try std.testing.expect(found);
    var retained = try draw.StreamPresenter.prepare(a, &adapter.buffer);
    defer retained.deinit(a);
    try std.testing.expect(retained.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, retained.items[0], "é✈️") != null);
    try std.testing.expect(!(try adapter.advance()).produced);
    try app.text_ref.?.set(.{ .bytes = "é again" });
    try std.testing.expect((try adapter.advance()).produced);
    try host.handle(.{ .resize = .{ .width = std.math.maxInt(i64), .height = 2 } });
    const prior = adapter.buffer.front.cells.ptr;
    try std.testing.expectError(error.FrameTooLarge, adapter.advance());
    try std.testing.expect(prior == adapter.buffer.front.cells.ptr);
    try std.testing.expect(try host.needsFrame());
    try host.handle(.{ .resize = .{ .width = 8, .height = 2 } });
    failure.fail_index = failure.alloc_index;
    try std.testing.expectError(error.OutOfMemory, adapter.advance());
    try std.testing.expect(prior == adapter.buffer.front.cells.ptr);
    failure.fail_index = std.math.maxInt(usize);
    try std.testing.expect((try adapter.advance()).produced);
}
fn drawingAllocations(alloc: std.mem.Allocator) !void {
    var app: DrawingApp = .{};
    const host = try g.Host(DrawingApp).create(alloc, &app);
    defer host.destroy() catch unreachable;
    try host.handle(.{ .resize = .{ .width = 10, .height = 2 } });
    var adapter = try g.DrawingPump(DrawingApp).init(alloc, host, .draw_list);
    defer adapter.deinit();
    _ = try adapter.advance();
    const old = (try host.currentTree()).?;
    const output = try host.currentOutput();
    const back = adapter.buffer.back.cells.ptr;
    try app.text_ref.?.set(.{ .bytes = "中é next" });
    _ = adapter.advance() catch |err| {
        try std.testing.expect(old == (try host.currentTree()).?);
        try std.testing.expect(output.ptr == (try host.currentOutput()).ptr);
        try std.testing.expect(back == adapter.buffer.back.cells.ptr);
        try std.testing.expect(try host.needsFrame());
        try std.testing.expectEqualStrings("中é next", (try app.text_ref.?.read()).bytes);
        return err;
    };
    var decoded = try draw.DrawList.decode(alloc, try host.currentOutput());
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i64, 10), decoded.size.width);
}
test "every host build paint clone encode copy allocation failure preserves publication" {
    try std.testing.checkAllAllocationFailures(a, drawingAllocations, .{});
}
fn bufferAllocations(alloc: std.mem.Allocator) !void {
    var b = try draw.CellBuffer.init(alloc, .{ .width = 4, .height = 1 });
    defer b.deinit();
    try b.putText(0, 0, "é中", .plain, 4);
    const initial = try draw.AnsiPresenter.present(alloc, &b);
    defer alloc.free(initial);
    const front = b.front.cells.ptr;
    b.resize(.{ .width = 6, .height = 2 }) catch |err| {
        try std.testing.expect(front == b.front.cells.ptr);
        try std.testing.expectEqualStrings("é", b.front.cells[0].glyph);
        return err;
    };
    try b.putText(0, 0, "é中", .plain, 6);
    const html = try draw.HTMLSerializer.serialize(alloc, &b);
    defer alloc.free(html);
    var list = try draw.DrawList.from(alloc, &b);
    defer list.deinit();
    const encoded = try list.encode(alloc);
    defer alloc.free(encoded);
    var decoded = try draw.DrawList.decode(alloc, encoded);
    defer decoded.deinit();
    var plain = try draw.StreamPresenter.present(alloc, &b);
    defer plain.deinit(alloc);
}
test "every resize glyph HTML plain wire allocation failure releases owned resources" {
    try std.testing.checkAllAllocationFailures(a, bufferAllocations, .{});
}
test "ANSI and plain output OOM leave both planes and force flag unchanged" {
    var b = try draw.CellBuffer.init(a, .{ .width = 4, .height = 1 });
    defer b.deinit();
    try b.putText(0, 0, "中é", .plain, 4);
    var failure = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    const front = b.front.cells.ptr;
    const back = b.back.cells.ptr;
    try std.testing.expectError(error.OutOfMemory, draw.AnsiPresenter.present(failure.allocator(), &b));
    try std.testing.expectError(error.OutOfMemory, draw.StreamPresenter.present(failure.allocator(), &b));
    try std.testing.expect(front == b.front.cells.ptr and back == b.back.cells.ptr and b.force_full);
}
const Downstream = struct {
    allocation: std.mem.Allocator,
    stage: enum { paint, encode, output },
    fn prepare(self: *@This(), frame: g.Host(DrawingApp).Preparation) g.Error![]const u8 {
        var buffer = try draw.CellBuffer.init(a, .{ .width = 10, .height = 2 });
        defer buffer.deinit();
        if (self.stage == .paint) {
            // Use the failing allocator for glyph copies/wrap in the real painter.
            var failing = try draw.CellBuffer.init(self.allocation, .{ .width = 10, .height = 2 });
            defer failing.deinit();
            try draw.paint(&failing, frame.tree.*);
        }
        try draw.paint(&buffer, frame.tree.*);
        var list = try draw.DrawList.from(a, &buffer);
        defer list.deinit();
        const output_allocator = if (self.stage == .encode) self.allocation else a;
        const wire = try list.encode(output_allocator);
        defer output_allocator.free(wire);
        if (self.stage == .output) return self.allocation.dupe(u8, wire);
        return frame.allocator.dupe(u8, wire);
    }
};
test "real downstream paint encode and output failures abort through PreparedFrame finish" {
    var app: DrawingApp = .{};
    const host = try g.Host(DrawingApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.handle(.{ .resize = .{ .width = 10, .height = 2 } });
    var adapter = try g.DrawingPump(DrawingApp).init(a, host, .draw_list);
    defer adapter.deinit();
    _ = try adapter.advance();
    const old_tree = (try host.currentTree()).?;
    const old_output = try host.currentOutput();
    const action = (try host.actionHandle(g.NodeID.root)).?;
    inline for (.{ Downstream{ .allocation = a, .stage = .paint }, Downstream{ .allocation = a, .stage = .encode }, Downstream{ .allocation = a, .stage = .output } }) |stage| {
        var failure = std.testing.FailingAllocator.init(a, .{ .fail_index = if (stage.stage == .paint) 2 else 0 });
        var downstream = stage;
        downstream.allocation = failure.allocator();
        try host.invalidate();
        const candidate = (try host.prepare(.{ .width = 10, .height = 2 })).?;
        try std.testing.expectError(error.OutOfMemory, candidate.finish(&downstream, Downstream.prepare));
        try std.testing.expect(old_tree == (try host.currentTree()).? and old_output.ptr == (try host.currentOutput()).ptr);
        try std.testing.expect(try host.needsFrame());
        try std.testing.expect(try action.invoke());
    }
    _ = try adapter.advance();
}
const MetadataApp = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        var children: std.ArrayList(g.Node) = .empty;
        for (0..4) |i| {
            const id = ctx.id.child(@intCast(i));
            try ctx.register(.{ .native_region = .{ .id = id, .region_id = "obsolete" } });
            try ctx.register(.{ .native_region = .{ .id = id, .region_id = if (i % 2 == 0) "A" else "B" } });
            try children.append(ctx.allocator, .{ .interactive = .{ .id = id, .focusable = false, .child = try ctx.box(.{ .spacer = 1 }) } });
        }
        return .{ .stack = .{ .axis = .horizontal, .alignment = .top_leading, .children = children.items } };
    }
};
test "M1 latest registration per NodeID last visual region wins diagnostic first order" {
    var app: MetadataApp = .{};
    const host = try g.Host(MetadataApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{ .width = 4, .height = 1 });
    const regions = try host.nativeRegions();
    const duplicates = try host.duplicateNativeRegionIDs();
    try std.testing.expectEqual(@as(usize, 2), regions.len);
    try std.testing.expectEqual(@as(usize, 2), duplicates.len);
    try std.testing.expectEqualStrings("A", regions[0].region_id);
    try std.testing.expectEqualStrings("B", regions[1].region_id);
    try std.testing.expectEqual(g.NodeID.root.child(2), regions[0].id);
    try std.testing.expectEqual(g.NodeID.root.child(3), regions[1].id);
    try std.testing.expectEqual(@as(i64, 2), regions[0].frame.origin.x);
    try std.testing.expectEqual(@as(i64, 3), regions[1].frame.origin.x);
    try std.testing.expectEqualStrings("A", duplicates[0]);
    try std.testing.expectEqualStrings("B", duplicates[1]);
}
test "all adapter formats publish borrowed output with serializer and presenter plane rules" {
    inline for (.{ draw.Format.draw_list, .html, .ansi, .plain }) |format| {
        var app: DrawingApp = .{};
        const host = try g.Host(DrawingApp).create(a, &app);
        defer host.destroy() catch unreachable;
        try host.handle(.{ .resize = .{ .width = 10, .height = 2 } });
        var adapter = try g.DrawingPump(DrawingApp).init(a, host, format);
        defer adapter.deinit();
        try std.testing.expect((try adapter.advance()).produced);
        const output = try host.currentOutput();
        try std.testing.expect(output.len > 0);
        try std.testing.expectEqual(format == .draw_list or format == .html, adapter.buffer.force_full);
        if (format == .plain) try std.testing.expect(output[output.len - 1] == '\n');
        if (format == .html) try std.testing.expect(std.mem.startsWith(u8, output, "<pre class="));
        if (format == .draw_list) try std.testing.expect(std.mem.startsWith(u8, output, "GAMA"));
        try std.testing.expect(!(try adapter.advance()).produced);
        try std.testing.expect(output.ptr == (try host.currentOutput()).ptr);
        const Foreign = struct {
            fn run(p: *g.DrawingPump(DrawingApp)) void {
                std.testing.expectError(error.WrongThread, p.advance()) catch unreachable;
            }
        };
        const thread = try std.Thread.spawn(.{}, Foreign.run, .{&adapter});
        thread.join();
    }
}
test "blank styled runs exact leading trim decorated space and full attribute bytes" {
    var b = try draw.CellBuffer.init(a, .{ .width = 4, .height = 1 });
    defer b.deinit();
    try b.put(1, 0, "x", .plain);
    var list = try draw.DrawList.from(a, &b);
    defer list.deinit();
    try std.testing.expectEqual(@as(i64, 1), list.commands[0].text.at.x);
    try std.testing.expectEqualStrings("x", list.commands[0].text.value);
    b.clearBack();
    try b.fill(.{ .size = b.size }, .{ .style = .{ .background = .red } });
    var blank = try draw.DrawList.from(a, &b);
    defer blank.deinit();
    try std.testing.expectEqual(@as(usize, 1), blank.commands.len);
    try std.testing.expect(blank.commands[0] == .fill);
    b.clearBack();
    try b.put(2, 0, " \u{301}", .plain);
    const row = try b.rowText(a, 0);
    defer a.free(row);
    try std.testing.expectEqualStrings("   \u{301}", row);
    for (0..256) |attrs| {
        var command = try draw.DrawList.init(a, .{}, &.{.{ .text = .{ .at = .{}, .style = .{ .attributes = @intCast(attrs) }, .value = "x" } }});
        defer command.deinit();
        const bytes = try command.encode(a);
        defer a.free(bytes);
        var decoded = try draw.DrawList.decode(a, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(@as(u8, @intCast(attrs)), decoded.commands[0].text.style.attributes);
    }
}
test "final host output-copy OOM after real paint and encoding preserves publication" {
    var failure = std.testing.FailingAllocator.init(a, .{});
    var app: DrawingApp = .{};
    const host = try g.Host(DrawingApp).create(failure.allocator(), &app);
    defer host.destroy() catch unreachable;
    try host.handle(.{ .resize = .{ .width = 10, .height = 2 } });
    var adapter = try g.DrawingPump(DrawingApp).init(a, host, .ansi);
    defer adapter.deinit();
    _ = try adapter.advance();
    const previous_tree = (try host.currentTree()).?;
    const previous_output = try host.currentOutput();
    const previous_front = adapter.buffer.front.cells.ptr;
    const FinalCopy = struct {
        failing: *std.testing.FailingAllocator,
        wire: ?[]u8 = null,
        prepared: bool = false,
        fn prepare(self: *@This(), frame: g.Host(DrawingApp).Preparation) g.Error![]const u8 {
            // A large, bounded raster makes output exceed the small candidate
            // arena's remaining capacity. All raster/codec allocations succeed.
            var raster = try draw.CellBuffer.init(a, .{ .width = 65536, .height = 1 });
            defer raster.deinit();
            try raster.fill(.{ .size = raster.size }, .{ .glyph = "x" });
            try draw.paint(&raster, frame.tree.*);
            var list = try draw.DrawList.from(a, &raster);
            defer list.deinit();
            self.wire = try list.encode(a);
            self.prepared = true;
            self.failing.fail_index = self.failing.alloc_index;
            self.failing.resize_fail_index = self.failing.resize_index;
            return self.wire.?; // next failing allocation is Host's final copy
        }
    };
    var final: FinalCopy = .{ .failing = &failure };
    defer if (final.wire) |wire| a.free(wire);
    try host.invalidate();
    const candidate = (try host.prepare(.{ .width = 10, .height = 2 })).?;
    try std.testing.expectError(error.OutOfMemory, candidate.finish(&final, FinalCopy.prepare));
    try std.testing.expect(final.prepared and final.wire.?.len > 65536);
    try std.testing.expect(previous_tree == (try host.currentTree()).?);
    try std.testing.expect(previous_output.ptr == (try host.currentOutput()).ptr);
    try std.testing.expect(previous_front == adapter.buffer.front.cells.ptr);
    try std.testing.expect(try host.needsFrame());
    failure.fail_index = std.math.maxInt(usize);
    failure.resize_fail_index = std.math.maxInt(usize);
    _ = try adapter.advance();
}
