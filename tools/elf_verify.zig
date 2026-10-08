//! Bounded ELF32LE structural inspection for the linked Cortex-M4 probe.
//! ARM tag rules: ARM abi-aa release2025Q4 addenda32 sections 3.2.3/3.2.4,
//! commit daa7a94ca55973736c0e434a67a6e4bbcd35d7fa. No instruction/hardware proof.
const std = @import("std");
pub const byte_limit = 32 * 1024 * 1024;
const E = error{ InvalidElf, LimitExceeded, DynamicDependency, UndefinedSymbol, InvalidAttributes };
fn range(bytes: []const u8, offset: usize, size: usize) E![]const u8 {
    if (offset > bytes.len or size > bytes.len - offset) return error.InvalidElf;
    return bytes[offset..][0..size];
}
fn word(bytes: []const u8, offset: usize) E!u32 {
    return std.mem.readInt(u32, (try range(bytes, offset, 4))[0..4], .little);
}
fn half(bytes: []const u8, offset: usize) E!u16 {
    return std.mem.readInt(u16, (try range(bytes, offset, 2))[0..2], .little);
}
fn string(bytes: []const u8, offset: usize) E![]const u8 {
    const tail = try range(bytes, offset, bytes.len -| offset);
    const end = std.mem.indexOfScalar(u8, tail[0..@min(tail.len, 4097)], 0) orelse return error.InvalidElf;
    if (end > 4096) return error.LimitExceeded;
    return tail[0..end];
}
const Cursor = struct {
    bytes: []const u8,
    pos: usize = 0,
    fn take(r: *Cursor, n: usize) E![]const u8 {
        const s = try range(r.bytes, r.pos, n);
        r.pos += n;
        return s;
    }
    fn leb(r: *Cursor) E!u32 {
        var result: u32 = 0;
        for (0..5) |i| {
            const c = (try r.take(1))[0];
            if (i == 4 and c > 15) return error.InvalidAttributes;
            result |= @as(u32, c & 127) << @as(u5, @intCast(7 * i));
            if (c & 128 == 0) return result;
        }
        return error.InvalidAttributes;
    }
    fn str(r: *Cursor) E![]const u8 {
        const s = try string(r.bytes, r.pos);
        r.pos += s.len + 1;
        return s;
    }
};
/// Strict supported file-scope metadata. Other scopes/vendors fail closed.
fn attributes(bytes: []const u8) E!void {
    var r: Cursor = .{ .bytes = bytes };
    if ((try r.take(1))[0] != 0x41) return error.InvalidAttributes;
    var values: [128]?[]const u8 = @splat(null);
    var required: [5]bool = @splat(false);
    var records: usize = 0;
    while (r.pos < bytes.len) {
        records += 1;
        if (records > 64) return error.LimitExceeded;
        const len = try word(try r.take(4), 0);
        if (len < 5) return error.InvalidAttributes;
        var v: Cursor = .{ .bytes = try r.take(len - 4) };
        if (!std.mem.eql(u8, try v.str(), "aeabi")) return error.InvalidAttributes;
        while (v.pos < v.bytes.len) {
            records += 1;
            if (records > 512) return error.LimitExceeded;
            const start = v.pos;
            if (try v.leb() != 1) return error.InvalidAttributes;
            const sublen = try word(try v.take(4), 0);
            const prefix = v.pos - start;
            if (sublen < prefix) return error.InvalidAttributes;
            var s: Cursor = .{ .bytes = try v.take(sublen - prefix) };
            var count: usize = 0;
            while (s.pos < s.bytes.len) {
                count += 1;
                if (count > 512) return error.LimitExceeded;
                const tag = try s.leb();
                const value_start = s.pos;
                var integer: ?u32 = null;
                var text: ?[]const u8 = null;
                switch (tag) {
                    4, 5 => text = try s.str(),
                    6...31 => integer = try s.leb(),
                    32 => {
                        _ = try s.leb();
                        _ = try s.str();
                    },
                    // Defined mandatory extensions are integers; unknown mandatory
                    // tags cannot be safely ignored under the ARM specification.
                    34, 36, 38, 42, 44, 46, 48, 50, 52 => integer = try s.leb(),
                    else => {
                        if (tag % 128 < 64) return error.InvalidAttributes;
                        if (tag % 2 == 0) integer = try s.leb() else text = try s.str();
                    },
                }
                if (tag < values.len) {
                    const encoded = s.bytes[value_start..s.pos];
                    if (values[tag]) |previous| {
                        if (!std.mem.eql(u8, previous, encoded)) return error.InvalidAttributes;
                    } else values[tag] = encoded;
                }
                switch (tag) {
                    5 => {
                        if (!std.mem.eql(u8, text.?, "cortex-m4")) return error.InvalidAttributes;
                        required[0] = true;
                    },
                    6 => {
                        if (integer.? != 13) return error.InvalidAttributes;
                        required[1] = true;
                    },
                    7 => {
                        if (integer.? != 77) return error.InvalidAttributes;
                        required[2] = true;
                    },
                    8 => {
                        if (integer.? != 0) return error.InvalidAttributes;
                        required[3] = true;
                    },
                    9 => {
                        if (integer.? != 2 and integer.? != 3) return error.InvalidAttributes;
                        required[4] = true;
                    },
                    else => {},
                }
            }
        }
    }
    for (required) |present| if (!present) return error.InvalidAttributes;
}
const Section = struct { header: usize, name: u32, kind: u32, flags: u32, address: u32, offset: u32, size: u32, link: u32, info: u32, align_: u32, stride: u32 };
fn section(bytes: []const u8, table: u32, index: usize) E!Section {
    const p = @as(usize, table) + index * 40;
    const s = try range(bytes, p, 40);
    return .{ .header = p, .name = try word(s, 0), .kind = try word(s, 4), .flags = try word(s, 8), .address = try word(s, 12), .offset = try word(s, 16), .size = try word(s, 20), .link = try word(s, 24), .info = try word(s, 28), .align_ = try word(s, 32), .stride = try word(s, 36) };
}
fn alignValid(n: u32) bool {
    return n == 0 or std.math.isPowerOfTwo(n);
}
fn end32(start: u32, size: u32) E!u64 {
    const end = @as(u64, start) + size;
    if (end > 0x1_0000_0000) return error.InvalidElf;
    return end;
}
pub const Measures = struct { file_bytes: usize, allocated_sections: u64 = 0, load_file_bytes: u64 = 0, load_memory_bytes: u64 = 0, sections: u16, symbols: usize = 0 };
pub fn verify(bytes: []const u8) E!Measures {
    if (bytes.len > byte_limit) return error.LimitExceeded;
    _ = try range(bytes, 0, 52);
    if (!std.mem.eql(u8, bytes[0..7], "\x7fELF\x01\x01\x01") or try half(bytes, 16) != 2 or try half(bytes, 18) != 40 or try word(bytes, 20) != 1 or try half(bytes, 40) != 52) return error.InvalidElf;
    // EABI5, soft-float ABI; no other producer flags are expected by this probe.
    if (try word(bytes, 36) != 0x05000200) return error.InvalidElf;
    if (!std.mem.allEqual(u8, bytes[7..16], 0)) return error.InvalidElf;
    const entry = try word(bytes, 24);
    if (entry & 1 == 0) return error.InvalidElf;
    const ph = try word(bytes, 28);
    const sh = try word(bytes, 32);
    const pn = try half(bytes, 44);
    const sn = try half(bytes, 48);
    const ni = try half(bytes, 50);
    if (try half(bytes, 42) != 32 or try half(bytes, 46) != 40 or pn == 0 or pn > 128 or sn < 2 or sn > 4096 or ni == 0 or ni >= sn) return error.InvalidElf;
    _ = try range(bytes, ph, @as(usize, pn) * 32);
    _ = try range(bytes, sh, @as(usize, sn) * 40);
    if (ph < 52 or sh < 52) return error.InvalidElf;
    var m: Measures = .{ .file_bytes = bytes.len, .sections = sn };
    var entry_load = false;
    for (0..pn) |i| {
        const p = try range(bytes, @as(usize, ph) + i * 32, 32);
        const kind = try word(p, 0);
        const off = try word(p, 4);
        const va = try word(p, 8);
        const fs = try word(p, 16);
        const ms = try word(p, 20);
        const flags = try word(p, 24);
        const al = try word(p, 28);
        if (kind == 2 or kind == 3) return error.DynamicDependency;
        _ = try range(bytes, off, fs);
        _ = try end32(va, ms);
        _ = try end32(try word(p, 12), ms);
        if (!alignValid(al)) return error.InvalidElf;
        if (kind == 1) {
            if (fs > ms or (al > 1 and va % al != off % al)) return error.InvalidElf;
            m.load_file_bytes += fs;
            m.load_memory_bytes += ms;
            if (flags & 1 != 0 and fs > 0 and (entry & ~@as(u32, 1)) >= va and @as(u64, entry & ~@as(u32, 1)) < @as(u64, va) + fs) entry_load = true;
        }
    }
    if (!entry_load) return error.InvalidElf;
    const names = try section(bytes, sh, ni);
    if (names.kind != 3) return error.InvalidElf;
    const strings = try range(bytes, names.offset, names.size);
    var symtab: ?Section = null;
    var attrs = false;
    for (0..sn) |i| {
        const s = try section(bytes, sh, i);
        const name = try string(strings, s.name);
        if (i == 0) {
            if (!std.mem.allEqual(u8, try range(bytes, s.header, 40), 0)) return error.InvalidElf;
            continue;
        }
        if (s.kind != 8) _ = try range(bytes, s.offset, s.size);
        _ = try end32(s.address, s.size);
        if (!alignValid(s.align_)) return error.InvalidElf;
        if (s.kind == 6 or s.kind == 11 or std.mem.eql(u8, name, ".interp")) return error.DynamicDependency;
        if (s.flags & 2 != 0) {
            m.allocated_sections += s.size;
            var loaded = s.size == 0;
            for (0..pn) |j| {
                const p = try range(bytes, @as(usize, ph) + j * 32, 32);
                if (try word(p, 0) != 1) continue;
                const va = try word(p, 8);
                const ms = try word(p, 20);
                const off = try word(p, 4);
                const fs = try word(p, 16);
                if (s.address < va or @as(u64, s.address) + s.size > @as(u64, va) + ms) continue;
                if (s.kind != 8 and (s.offset < off or @as(u64, s.offset) + s.size > @as(u64, off) + fs or s.address - va != s.offset - off)) continue;
                if (s.flags & 4 != 0 and try word(p, 24) & 1 == 0) continue;
                loaded = true;
            }
            if (!loaded) return error.InvalidElf;
        }
        if (s.kind == 2) {
            if (symtab != null) return error.InvalidElf;
            symtab = s;
        }
        if (s.kind == 0x70000003 or std.mem.eql(u8, name, ".ARM.attributes")) {
            if (attrs or s.kind != 0x70000003 or !std.mem.eql(u8, name, ".ARM.attributes")) return error.InvalidAttributes;
            try attributes(try range(bytes, s.offset, s.size));
            attrs = true;
        }
    }
    if (!attrs) return error.InvalidAttributes;
    const syms = symtab orelse return error.InvalidElf;
    if (syms.stride != 16 or syms.size % 16 != 0 or syms.size < 32 or syms.size / 16 > 262144 or syms.link == 0 or syms.link >= sn) return error.InvalidElf;
    const ns = try section(bytes, sh, syms.link);
    if (ns.kind != 3) return error.InvalidElf;
    const symbol_names = try range(bytes, ns.offset, ns.size);
    var entry_symbol = false;
    m.symbols = syms.size / 16;
    if (syms.info > m.symbols) return error.InvalidElf;
    for (0..m.symbols) |i| {
        const p = try range(bytes, @as(usize, syms.offset) + i * 16, 16);
        if (i == 0) {
            if (!std.mem.allEqual(u8, p, 0)) return error.InvalidElf;
            continue;
        }
        const name = try string(symbol_names, try word(p, 0));
        const value = try word(p, 4);
        const size = try word(p, 8);
        const index = try half(p, 14);
        if (index == 0 or index == 0xfff2) return error.UndefinedSymbol;
        if (index != 0xfff1 and index >= sn) return error.InvalidElf;
        if (std.mem.eql(u8, name, "gama_embedded_entry")) {
            if (entry_symbol or index == 0xfff1 or value != entry or size == 0 or p[12] & 15 != 2) return error.InvalidElf;
            const s = try section(bytes, sh, index);
            const address = value & ~@as(u32, 1);
            if (s.flags & 6 != 6 or address < s.address or @as(u64, address) + size > @as(u64, s.address) + s.size) return error.InvalidElf;
            entry_symbol = true;
        }
    }
    if (!entry_symbol) return error.InvalidElf;
    return m;
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedArtifact;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.gpa, .limited(byte_limit));
    defer init.gpa.free(bytes);
    const m = try verify(bytes);
    const count = try tamperChecks(init.gpa, bytes);
    std.debug.print("ELF structural verification passed: file={d}, allocated sections={d}, LOAD file={d}, LOAD memory={d}, sections={d}, symbols={d}; Cortex-M4 v7E-M/M/Thumb, defined entry, no imports; {d} tamper cases rejected\n", .{ m.file_bytes, m.allocated_sections, m.load_file_bytes, m.load_memory_bytes, m.sections, m.symbols, count });
}
fn put(bytes: []u8, at: usize, comptime T: type, value: T) void {
    std.mem.writeInt(T, bytes[at..][0..@sizeOf(T)], value, .little);
}
fn rejected(bytes: []const u8) !void {
    if (verify(bytes)) |_| return error.AcceptedTamper else |_| {}
}
pub fn tamperChecks(a: std.mem.Allocator, bytes: []const u8) !usize {
    _ = try verify(bytes);
    const copy = try a.dupe(u8, bytes);
    defer a.free(copy);
    var count: usize = 0;
    const changes = [_]struct { at: usize, width: u8, value: u32 }{
        .{ .at = 4, .width = 1, .value = 2 },           .{ .at = 5, .width = 1, .value = 2 },           .{ .at = 6, .width = 1, .value = 0 },
        .{ .at = 16, .width = 2, .value = 1 },          .{ .at = 18, .width = 2, .value = 62 },         .{ .at = 20, .width = 4, .value = 0 },
        .{ .at = 24, .width = 4, .value = 0 },          .{ .at = 24, .width = 4, .value = 0xfffffff1 }, .{ .at = 28, .width = 4, .value = 0xffffffff },
        .{ .at = 32, .width = 4, .value = 0xffffffff }, .{ .at = 36, .width = 4, .value = 0 },          .{ .at = 40, .width = 2, .value = 51 },
        .{ .at = 42, .width = 2, .value = 31 },         .{ .at = 44, .width = 2, .value = 0xffff },     .{ .at = 46, .width = 2, .value = 39 },
        .{ .at = 48, .width = 2, .value = 0 },          .{ .at = 50, .width = 2, .value = 0xffff },
    };
    for (changes) |c| {
        @memcpy(copy, bytes);
        switch (c.width) {
            1 => copy[c.at] = @intCast(c.value),
            2 => put(copy, c.at, u16, @intCast(c.value)),
            else => put(copy, c.at, u32, c.value),
        }
        try rejected(copy);
        count += 1;
    }
    const ph = try word(bytes, 28);
    const sh = try word(bytes, 32);
    const sn = try half(bytes, 48);
    for ([_]u32{ 2, 3 }) |kind| {
        @memcpy(copy, bytes);
        put(copy, ph, u32, kind);
        try rejected(copy);
        count += 1;
    }
    @memcpy(copy, bytes);
    for (0..try half(bytes, 44)) |i| {
        put(copy, @as(usize, ph) + i * 32 + 24, u32, 0);
    }
    try rejected(copy);
    count += 1;
    for (0..try half(bytes, 44)) |i| {
        const pos = @as(usize, ph) + i * 32;
        if (try word(bytes, pos) != 1) continue;
        for ([_]struct { delta: usize, value: u32 }{
            .{ .delta = 4, .value = 0xffffffff }, .{ .delta = 8, .value = 0xffffffff },
            .{ .delta = 20, .value = 0 },         .{ .delta = 28, .value = 3 },
        }) |c| {
            @memcpy(copy, bytes);
            put(copy, pos + c.delta, u32, c.value);
            try rejected(copy);
            count += 1;
        }
    }
    @memcpy(copy, bytes);
    put(copy, 24, u32, (try word(bytes, 24)) + 2);
    try rejected(copy);
    count += 1;
    for (0..sn) |i| {
        const s = try section(bytes, sh, i);
        if (s.kind == 2) {
            const symbol_names_section = try section(bytes, sh, s.link);
            const symbol_names = try range(bytes, symbol_names_section.offset, symbol_names_section.size);
            for (1..s.size / 16) |j| {
                const pos = @as(usize, s.offset) + j * 16;
                if (!std.mem.eql(u8, try string(symbol_names, try word(bytes, pos)), "gama_embedded_entry")) continue;
                for ([_]usize{ 0, 4, 8 }) |delta| {
                    @memcpy(copy, bytes);
                    put(copy, pos + delta, u32, 0);
                    try rejected(copy);
                    count += 1;
                }
                @memcpy(copy, bytes);
                put(copy, pos + 14, u16, 0xfff1);
                try rejected(copy);
                count += 1;
                @memcpy(copy, bytes);
                copy[pos + 12] = 0x11;
                try rejected(copy);
                count += 1;
            }
            const linked = try section(bytes, sh, s.link);
            @memcpy(copy, bytes);
            put(copy, linked.header + 4, u32, 1);
            try rejected(copy);
            count += 1;
            @memcpy(copy, bytes);
            copy[s.offset] = 1;
            try rejected(copy);
            count += 1;
            for ([_]struct { delta: usize, value: u32 }{ .{ .delta = 4, .value = 1 }, .{ .delta = 16, .value = 0xffffffff }, .{ .delta = 20, .value = 17 }, .{ .delta = 24, .value = 0 }, .{ .delta = 36, .value = 15 } }) |c| {
                @memcpy(copy, bytes);
                put(copy, s.header + c.delta, u32, c.value);
                try rejected(copy);
                count += 1;
            }
            for ([_]u16{ 0, 0xfff2, 0xffff }) |index| {
                @memcpy(copy, bytes);
                put(copy, @as(usize, s.offset) + 16 + 14, u16, index);
                try rejected(copy);
                count += 1;
            }
            // unnamed, weak undefined is still unresolved.
            @memcpy(copy, bytes);
            put(copy, @as(usize, s.offset) + 16, u32, 0);
            copy[@as(usize, s.offset) + 16 + 12] = 0x20;
            put(copy, @as(usize, s.offset) + 16 + 14, u16, 0);
            try rejected(copy);
            count += 1;
            @memcpy(copy, bytes);
            put(copy, @as(usize, s.offset) + 16, u32, 0xffffffff);
            try rejected(copy);
            count += 1;
        }
        if (s.kind == 0x70000003) {
            for ([_]usize{ 0, 1, 11 }) |delta| {
                @memcpy(copy, bytes);
                copy[@as(usize, s.offset) + delta] = 0;
                try rejected(copy);
                count += 1;
            }
            const attr = try range(bytes, s.offset, s.size);
            for ([_][2]u8{ .{ 6, 13 }, .{ 7, 77 }, .{ 8, 0 }, .{ 9, 2 } }) |pair| {
                const at = std.mem.indexOf(u8, attr, &pair) orelse return error.ExpectedAttribute;
                @memcpy(copy, bytes);
                copy[@as(usize, s.offset) + at + 1] = 127;
                try rejected(copy);
                count += 1;
            }
            @memcpy(copy, bytes);
            put(copy, s.header + 20, u32, s.size - 1);
            try rejected(copy);
            count += 1;
        }
        if (s.kind == 1 and s.flags & 4 != 0) {
            @memcpy(copy, bytes);
            put(copy, s.header + 4, u32, 6);
            try rejected(copy);
            count += 1;
        }
    }
    for ([_]usize{ 0, 7, 51, bytes.len - 1 }) |end| {
        try rejected(bytes[0..end]);
        count += 1;
    }
    return count;
}
test "short headers and impossible ranges reject in every mode" {
    var bytes: [128]u8 = @splat(0);
    for (0..bytes.len) |n| try rejected(bytes[0..n]);
    try std.testing.expectError(error.InvalidElf, range(&bytes, std.math.maxInt(usize), 8));
    try std.testing.expectError(error.InvalidElf, range(&bytes, 120, std.math.maxInt(usize)));
}
test "ARM parameters follow specification including special tags and conflicts" {
    // Independently constructed record, no dependency on compiler output.
    const params = "\x05cortex-m4\x00\x06\x0d\x07M\x08\x00\x09\x02\x20\x00vendor\x00\x43" ++ "2.09\x00";
    var bytes: [1 + 4 + 6 + 1 + 4 + params.len]u8 = undefined;
    bytes[0] = 'A';
    put(&bytes, 1, u32, bytes.len - 1);
    @memcpy(bytes[5..11], "aeabi\x00");
    bytes[11] = 1;
    put(&bytes, 12, u32, bytes.len - 11);
    @memcpy(bytes[16..], params);
    try attributes(&bytes);
    for (0..bytes.len) |n| {
        if (attributes(bytes[0..n])) |_| return error.AcceptedTruncation else |_| {}
    }
    bytes[bytes.len - 1] = 1;
    try std.testing.expectError(error.InvalidElf, attributes(&bytes));
}

fn attributeFixture(a: std.mem.Allocator, params: []const u8) ![]u8 {
    const bytes = try a.alloc(u8, 16 + params.len);
    bytes[0] = 'A';
    put(bytes, 1, u32, @intCast(bytes.len - 1));
    @memcpy(bytes[5..11], "aeabi\x00");
    bytes[11] = 1;
    put(bytes, 12, u32, @intCast(bytes.len - 11));
    @memcpy(bytes[16..], params);
    return bytes;
}
test "ARM duplicate conflicts unknown mandatory tags and malformed encodings fail closed" {
    const valid = "\x05cortex-m4\x00\x06\x0d\x07M\x08\x00\x09\x02";
    const a = std.testing.allocator;
    for ([_][]const u8{ "\x06\x0c", "\x28\x00", "\x80\x80\x80\x80\x80\x00", "\x09\x80\x80\x80\x80\x10", "\x05wrong\x00" }) |suffix| {
        const params = try std.mem.concat(a, u8, &.{ valid, suffix });
        defer a.free(params);
        const bytes = try attributeFixture(a, params);
        defer a.free(bytes);
        if (attributes(bytes)) |_| return error.AcceptedInvalidAttributes else |_| {}
    }
    const same = try attributeFixture(a, valid ++ "\x06\x0d\x43ignored\x00");
    defer a.free(same);
    try attributes(same);
}
