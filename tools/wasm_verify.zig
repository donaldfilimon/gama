//! Bounded structural validator for this import-free pull ABI, not an instruction
//! validator/interpreter. Parsed framing, indices and signatures are enforced in
//! every optimization mode. Engine validation/execution is a separate test layer.
const std = @import("std");
pub const byte_limit = 32 * 1024 * 1024;
const E = error{ InvalidModule, LimitExceeded, ImportsForbidden, UnexpectedExport, SignatureMismatch, MissingExport, StartForbidden, OutOfMemory };
const Cursor = struct {
    bytes: []const u8,
    pos: usize = 0,
    fn take(self: *Cursor, n: usize) E![]const u8 {
        if (n > self.bytes.len - self.pos) return error.InvalidModule;
        const result = self.bytes[self.pos..][0..n];
        self.pos += n;
        return result;
    }
    fn byte(self: *Cursor) E!u8 {
        return (try self.take(1))[0];
    }
    fn u32leb(self: *Cursor) E!u32 {
        var result: u32 = 0;
        for (0..5) |i| {
            const b = try self.byte();
            if (i == 4 and b > 0x0f) return error.InvalidModule;
            result |= @as(u32, b & 0x7f) << @as(u5, @intCast(i * 7));
            if (b & 0x80 == 0) return result;
        }
        return error.InvalidModule;
    }
    fn count(self: *Cursor, max: u32) E!usize {
        const n = try self.u32leb();
        if (n > max) return error.LimitExceeded;
        return n;
    }
    fn name(self: *Cursor) E![]const u8 {
        const bytes = try self.take(try self.count(262144));
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidModule;
        return bytes;
    }
    fn done(self: Cursor) E!void {
        if (self.pos != self.bytes.len) return error.InvalidModule;
    }
};
const Signature = struct { params: []const u8, results: []const u8 };
const expected = [_]struct { name: []const u8, params: usize, results: usize }{
    .{ .name = "gama_wasm_v1_init", .params = 2, .results = 1 },
    .{ .name = "gama_wasm_v1_shutdown", .params = 0, .results = 0 },
    .{ .name = "gama_wasm_v1_key", .params = 4, .results = 1 },
    .{ .name = "gama_wasm_v1_pointer", .params = 3, .results = 1 },
    .{ .name = "gama_wasm_v1_resize", .params = 2, .results = 1 },
    .{ .name = "gama_wasm_v1_needs_frame", .params = 0, .results = 1 },
    .{ .name = "gama_wasm_v1_frame", .params = 0, .results = 1 },
    .{ .name = "gama_wasm_v1_frame_ptr", .params = 0, .results = 1 },
    .{ .name = "gama_wasm_v1_frame_len", .params = 0, .results = 1 },
};
fn valueType(byte: u8) E!void {
    switch (byte) {
        0x7f, 0x7e, 0x7d, 0x7c, 0x7b, 0x70, 0x6f => {},
        else => return error.InvalidModule,
    }
}
fn limits(r: *Cursor, maximum: u32) E!void {
    const flags = try r.u32leb();
    if (flags > 1) return error.InvalidModule; // no shared, memory64, or custom-page size
    const min = try r.u32leb();
    if (min > maximum) return error.InvalidModule;
    if (flags == 1) {
        const max = try r.u32leb();
        if (max > maximum or min > max) return error.InvalidModule;
    }
}
fn signed(r: *Cursor, comptime T: type) E!void {
    const start = r.pos;
    for (0..(@divTrunc(@bitSizeOf(T) + 6, 7))) |_| {
        if (try r.byte() & 0x80 == 0) {
            var reader = std.Io.Reader.fixed(r.bytes[start..r.pos]);
            _ = reader.takeLeb128(T) catch return error.InvalidModule;
            return;
        }
    }
    return error.InvalidModule;
}
fn expression(r: *Cursor, functions: usize, globals: usize) E!void {
    switch (try r.byte()) {
        0x41 => try signed(r, i32),
        0x42 => try signed(r, i64),
        0x43 => {
            _ = try r.take(4);
        },
        0x44 => {
            _ = try r.take(8);
        },
        0x23 => {
            if (try r.u32leb() >= globals) return error.InvalidModule;
        },
        0xd0 => {
            const kind = try r.byte();
            if (kind != 0x70 and kind != 0x6f) return error.InvalidModule;
        },
        0xd2 => {
            if (try r.u32leb() >= functions) return error.InvalidModule;
        },
        else => return error.InvalidModule,
    }
    if (try r.byte() != 0x0b) return error.InvalidModule;
}
fn rank(id: u8) E!u8 {
    return switch (id) {
        1...9 => id,
        12 => 10,
        10 => 11,
        11 => 12,
        else => error.InvalidModule,
    };
}
pub fn verify(a: std.mem.Allocator, bytes: []const u8) E!void {
    if (bytes.len > byte_limit) return error.LimitExceeded;
    var r: Cursor = .{ .bytes = bytes };
    if (!std.mem.eql(u8, try r.take(8), "\x00asm\x01\x00\x00\x00")) return error.InvalidModule;
    var types: std.ArrayList(Signature) = .empty;
    defer types.deinit(a);
    var functions: std.ArrayList(u32) = .empty;
    defer functions.deinit(a);
    var seen: [13]bool = @splat(false);
    var exports: [10]bool = @splat(false);
    var last_rank: u8 = 0;
    var sections: usize = 0;
    var memories: usize = 0;
    var tables: usize = 0;
    var globals: usize = 0;
    var declared_data: ?u32 = null;
    var actual_data: u32 = 0;
    while (r.pos < bytes.len) {
        sections += 1;
        if (sections > 256) return error.LimitExceeded;
        const id = try r.byte();
        var s: Cursor = .{ .bytes = try r.take(try r.u32leb()) };
        if (id == 0) {
            _ = try s.name();
            continue;
        }
        const section_rank = try rank(id);
        if (seen[id] or section_rank < last_rank) return error.InvalidModule;
        seen[id] = true;
        last_rank = section_rank;
        switch (id) {
            1 => {
                const n = try s.count(4096);
                for (0..n) |_| {
                    if (try s.byte() != 0x60) return error.InvalidModule;
                    const params = try s.take(try s.count(256));
                    for (params) |v| try valueType(v);
                    const results = try s.take(try s.count(16));
                    for (results) |v| try valueType(v);
                    try types.append(a, .{ .params = params, .results = results });
                }
            },
            2 => {
                if (try s.u32leb() != 0) return error.ImportsForbidden;
            },
            3 => {
                const n = try s.count(65536);
                for (0..n) |_| {
                    const type_id = try s.u32leb();
                    if (type_id >= types.items.len) return error.InvalidModule;
                    try functions.append(a, type_id);
                }
            },
            4 => {
                tables = try s.count(1);
                for (0..tables) |_| {
                    if (try s.byte() != 0x70) return error.InvalidModule;
                    try limits(&s, 65536);
                }
            },
            5 => {
                memories = try s.count(1);
                if (memories != 1) return error.InvalidModule;
                try limits(&s, 65536);
            },
            6 => {
                const n = try s.count(65536);
                for (0..n) |_| {
                    try valueType(try s.byte());
                    if (try s.byte() > 1) return error.InvalidModule;
                    try expression(&s, functions.items.len, globals);
                    globals += 1;
                }
            },
            7 => {
                const n = try s.count(10);
                for (0..n) |_| {
                    const name = try s.name();
                    const kind = try s.byte();
                    const index = try s.u32leb();
                    if (std.mem.eql(u8, name, "memory")) {
                        if (exports[9] or kind != 2 or index != 0 or memories != 1) return error.InvalidModule;
                        exports[9] = true;
                        continue;
                    }
                    var found = false;
                    for (expected, 0..) |exp, i| if (std.mem.eql(u8, name, exp.name)) {
                        if (exports[i] or kind != 0 or index >= functions.items.len) return error.InvalidModule;
                        const sig = types.items[functions.items[index]];
                        if (sig.params.len != exp.params or sig.results.len != exp.results) return error.SignatureMismatch;
                        for (sig.params) |v| if (v != 0x7f) return error.SignatureMismatch;
                        for (sig.results) |v| if (v != 0x7f) return error.SignatureMismatch;
                        exports[i] = true;
                        found = true;
                        break;
                    };
                    if (!found) return error.UnexpectedExport;
                }
            },
            8 => return error.StartForbidden,
            9 => {
                const n = try s.count(65536);
                for (0..n) |_| {
                    // This linker emits active table-zero function-index elements.
                    // Other forms are intentionally unsupported, never skipped as proof.
                    if (try s.u32leb() != 0 or tables != 1) return error.InvalidModule;
                    try expression(&s, functions.items.len, globals);
                    const count = try s.count(65536);
                    for (0..count) |_| if (try s.u32leb() >= functions.items.len) return error.InvalidModule;
                }
            },
            12 => {
                declared_data = try s.u32leb();
                if (declared_data.? > 65536) return error.LimitExceeded;
            },
            10 => {
                const n = try s.count(65536);
                if (n != functions.items.len) return error.InvalidModule;
                for (0..n) |_| {
                    var body: Cursor = .{ .bytes = try s.take(try s.u32leb()) };
                    const local_groups = try body.count(65536);
                    var locals: u64 = 0;
                    for (0..local_groups) |_| {
                        locals += try body.u32leb();
                        if (locals > 1048576) return error.LimitExceeded;
                        try valueType(try body.byte());
                    }
                    // Bounded body/local framing only. Engine verifies instruction typing.
                    if (body.pos == body.bytes.len or body.bytes[body.bytes.len - 1] != 0x0b) return error.InvalidModule;
                }
            },
            11 => {
                actual_data = try s.u32leb();
                if (actual_data > 65536) return error.LimitExceeded;
                for (0..actual_data) |_| {
                    const flags = try s.u32leb();
                    if (flags > 2) return error.InvalidModule;
                    if (flags != 1) {
                        if (memories != 1) return error.InvalidModule;
                        if (flags == 2 and try s.u32leb() != 0) return error.InvalidModule;
                        try expression(&s, functions.items.len, globals);
                    }
                    _ = try s.take(try s.u32leb());
                }
            },
            else => return error.InvalidModule,
        }
        try s.done();
    }
    for (exports) |present| if (!present) return error.MissingExport;
    if (!seen[1] or !seen[3] or !seen[5] or !seen[7] or !seen[10]) return error.InvalidModule;
    if (declared_data) |n| if (n != actual_data) return error.InvalidModule;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedArtifact;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.gpa, .limited(byte_limit));
    defer init.gpa.free(bytes);
    try verify(init.gpa, bytes);
    const count = try tamperChecks(init.gpa, bytes);
    std.debug.print("WASM structural verification passed: {d} bytes, 9 function signatures, exported memory32, zero imports; {d} linked-artifact tamper cases rejected\n", .{ bytes.len, count });
}

const Section = struct { start: usize, payload: usize, end: usize };
fn locate(bytes: []const u8, id: u8) !Section {
    var r: Cursor = .{ .bytes = bytes, .pos = 8 };
    while (r.pos < bytes.len) {
        const start = r.pos;
        const actual = try r.byte();
        const n = try r.u32leb();
        const payload = r.pos;
        _ = try r.take(n);
        if (actual == id) return .{ .start = start, .payload = payload, .end = r.pos };
    }
    return error.InvalidModule;
}
fn appendLeb(out: *std.ArrayList(u8), a: std.mem.Allocator, n_: usize) !void {
    var n = n_;
    while (true) {
        const b: u8 = @intCast(n & 127);
        n >>= 7;
        try out.append(a, b | @as(u8, if (n == 0) 0 else 128));
        if (n == 0) return;
    }
}
fn section(out: *std.ArrayList(u8), a: std.mem.Allocator, id: u8, payload: []const u8) !void {
    try out.append(a, id);
    try appendLeb(out, a, payload.len);
    try out.appendSlice(a, payload);
}
fn replace(a: std.mem.Allocator, bytes: []const u8, id: u8, payload: []const u8) ![]u8 {
    const old = try locate(bytes, id);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, bytes[0..old.start]);
    try section(&out, a, id, payload);
    try out.appendSlice(a, bytes[old.end..]);
    return out.toOwnedSlice(a);
}
fn rejected(a: std.mem.Allocator, bytes: []const u8) !void {
    verify(a, bytes) catch |e| {
        if (e == error.OutOfMemory) return e;
        return;
    };
    return error.AcceptedTamper;
}
fn rejectReplacement(a: std.mem.Allocator, bytes: []const u8, id: u8, payload: []const u8) !void {
    const tampered = try replace(a, bytes, id, payload);
    defer a.free(tampered);
    try rejected(a, tampered);
}
/// Independently corrupt the actual linked bytes. No expected-signature builder is
/// involved in these mutations; success requires rejection of every changed input.
pub fn tamperChecks(a: std.mem.Allocator, bytes: []const u8) !usize {
    try verify(a, bytes);
    var checks: usize = 0;
    const copy = try a.dupe(u8, bytes);
    defer a.free(copy);
    copy[0] = 0x7f;
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    copy[4] = 2;
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    for ([_]usize{ 0, 7, bytes.len - 1 }) |n| {
        try rejected(a, bytes[0..n]);
        checks += 1;
    }
    // Nonzero imports and empty-import trailing payloads inserted in legal order.
    const f = try locate(bytes, 3);
    for ([_][]const u8{ &.{ 2, 1, 1 }, &.{ 2, 2, 0, 0 } }) |insertion| {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(a);
        try out.appendSlice(a, bytes[0..f.start]);
        try out.appendSlice(a, insertion);
        try out.appendSlice(a, bytes[f.start..]);
        try rejected(a, out.items);
        checks += 1;
    }
    const exp = try locate(bytes, 7);
    const name_at = std.mem.indexOf(u8, copy[exp.payload..exp.end], "gama_wasm_v1_init").? + exp.payload;
    copy[name_at] = 'x';
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    try rejectReplacement(a, bytes, 7, &.{0});
    checks += 1;
    // Function vector must resolve type ids, and code count must agree.
    try rejectReplacement(a, bytes, 3, &.{ 1, 0xff, 0xff, 0x7f });
    checks += 1;
    try rejectReplacement(a, bytes, 10, &.{0});
    checks += 1;
    try rejectReplacement(a, bytes, 10, &.{ 1, 0xff, 0xff, 0xff, 0xff, 0x0f });
    checks += 1;
    for ([_][]const u8{ &.{ 1, 2, 1 }, &.{ 1, 4, 1 }, &.{ 1, 1, 2, 1 }, &.{0}, &.{ 1, 0, 0, 0 } }) |bad| {
        try rejectReplacement(a, bytes, 5, bad);
        checks += 1;
    }
    // Type section shape/overflow plus valid framed wrong signature type.
    try rejectReplacement(a, bytes, 1, &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0 });
    checks += 1;
    try rejectReplacement(a, bytes, 1, &.{ 0xff, 0xff, 0xff, 0xff, 0x1f });
    checks += 1;
    const ty = try locate(bytes, 1);
    var tr: Cursor = .{ .bytes = bytes[ty.payload..ty.end] };
    const type_count = try tr.u32leb();
    for (0..type_count) |_| {
        _ = try tr.byte();
        const params = try tr.u32leb();
        for (0..params) |_| {
            const p = tr.pos;
            _ = try tr.byte();
            if (copy[ty.payload + p] == 0x7f) copy[ty.payload + p] = 0x7e;
        }
        const results = try tr.u32leb();
        _ = try tr.take(results);
    }
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    // Missing memory, duplicate function name, and invalid indices/kinds use export parsing.
    var er: Cursor = .{ .bytes = bytes[exp.payload..exp.end] };
    const export_count = try er.u32leb();
    var memory_index: usize = 0;
    var function_index: usize = 0;
    var function_kind: usize = 0;
    for (0..export_count) |_| {
        const name = try er.name();
        const kind_at = er.pos;
        const kind = try er.byte();
        const index_at = er.pos;
        _ = try er.u32leb();
        if (std.mem.eql(u8, name, "memory")) memory_index = exp.payload + index_at else if (kind == 0) {
            function_index = exp.payload + index_at;
            function_kind = exp.payload + kind_at;
        }
    }
    copy[memory_index] = 1;
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    copy[function_index] = 0xff;
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    copy[function_kind] = 2;
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    const frame_ptr = std.mem.indexOf(u8, copy[exp.payload..exp.end], "gama_wasm_v1_frame_ptr").? + exp.payload;
    @memcpy(copy[frame_ptr..][0.."gama_wasm_v1_frame_len".len], "gama_wasm_v1_frame_len");
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    var duplicate: std.ArrayList(u8) = .empty;
    defer duplicate.deinit(a);
    try duplicate.appendSlice(a, bytes);
    try duplicate.appendSlice(a, bytes[ty.start..ty.end]);
    try rejected(a, duplicate.items);
    checks += 1;
    // Validly framed wrong arity and wrong result type, independent of the
    // expected-signature table. Every function type is rewritten, not the exports.
    for ([_]bool{ false, true }) |wrong_result| {
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(a);
        var source: Cursor = .{ .bytes = bytes[ty.payload..ty.end] };
        const n = try source.u32leb();
        try appendLeb(&payload, a, n);
        for (0..n) |_| {
            try payload.append(a, try source.byte());
            const params = try source.take(try source.u32leb());
            try appendLeb(&payload, a, if (wrong_result) params.len else 0);
            if (wrong_result) try payload.appendSlice(a, params);
            const results = try source.take(try source.u32leb());
            try appendLeb(&payload, a, results.len);
            for (results) |v| try payload.append(a, if (wrong_result and v == 0x7f) 0x7e else v);
        }
        try rejectReplacement(a, bytes, 1, payload.items);
        checks += 1;
    }
    // A missing memory export (renamed), unknown sections, and trailing payload.
    const memory_name = std.mem.indexOf(u8, bytes[exp.payload..exp.end], "memory").? + exp.payload;
    copy[memory_name] = 'x';
    try rejected(a, copy);
    checks += 1;
    @memcpy(copy, bytes);
    duplicate.clearRetainingCapacity();
    try duplicate.appendSlice(a, bytes);
    try duplicate.appendSlice(a, &.{ 13, 0 });
    try rejected(a, duplicate.items);
    checks += 1;
    duplicate.clearRetainingCapacity();
    try duplicate.appendSlice(a, bytes[ty.payload..ty.end]);
    try duplicate.append(a, 0);
    try rejectReplacement(a, bytes, 1, duplicate.items);
    checks += 1;
    // The type section is moved after function declarations, with no duplicate.
    duplicate.clearRetainingCapacity();
    try duplicate.appendSlice(a, bytes[0..ty.start]);
    try duplicate.appendSlice(a, bytes[ty.end..f.end]);
    try duplicate.appendSlice(a, bytes[ty.start..ty.end]);
    try duplicate.appendSlice(a, bytes[f.end..]);
    try rejected(a, duplicate.items);
    checks += 1;
    // A start section in its legal ordering position is explicitly forbidden.
    duplicate.clearRetainingCapacity();
    try duplicate.appendSlice(a, bytes[0..exp.end]);
    try duplicate.appendSlice(a, &.{ 8, 1, 0 });
    try duplicate.appendSlice(a, bytes[exp.end..]);
    try rejected(a, duplicate.items);
    checks += 1;
    // Keep the real code count; truncate its first bounded body envelope.
    const code = try locate(bytes, 10);
    var code_cursor: Cursor = .{ .bytes = bytes[code.payload..code.end] };
    _ = try code_cursor.u32leb();
    duplicate.clearRetainingCapacity();
    try duplicate.appendSlice(a, code_cursor.bytes[0..code_cursor.pos]);
    try duplicate.appendSlice(a, &.{ 0xff, 0xff, 0xff, 0xff, 0x0f });
    try rejectReplacement(a, bytes, 10, duplicate.items);
    checks += 1;
    // Legal padded u32 is accepted by Cursor; six-byte and overflowing forms fail above.
    return checks;
}
test "u32 envelope permits legal padding rejects overflow and overlong encodings" {
    var r: Cursor = .{ .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x00 } };
    try std.testing.expectEqual(@as(u32, 0), try r.u32leb());
    r = .{ .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0x0f } };
    try std.testing.expectEqual(std.math.maxInt(u32), try r.u32leb());
    for ([_][]const u8{ &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0 }, &.{ 0xff, 0xff, 0xff, 0xff, 0x10 }, &.{0x80} }) |bad| {
        r = .{ .bytes = bad };
        try std.testing.expectError(error.InvalidModule, r.u32leb());
    }
}
test "wrong architecture and truncated headers never inspect successfully" {
    try std.testing.expectError(error.InvalidModule, verify(std.testing.allocator, "\x7fELF\x01\x01\x01\x00"));
    for (0..8) |n| try std.testing.expectError(error.InvalidModule, verify(std.testing.allocator, "\x00asm\x01\x00\x00\x00"[0..n]));
}

fn fixture(a: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, "\x00asm\x01\x00\x00\x00");
    // Independent tiny valid module: five explicitly encoded types, nine bodies.
    try section(&out, a, 1, &.{ 5, 0x60, 2, 0x7f, 0x7f, 1, 0x7f, 0x60, 0, 0, 0x60, 4, 0x7f, 0x7f, 0x7f, 0x7f, 1, 0x7f, 0x60, 3, 0x7f, 0x7f, 0x7f, 1, 0x7f, 0x60, 0, 1, 0x7f });
    try section(&out, a, 3, &.{ 9, 0, 1, 2, 3, 0, 4, 4, 4, 4 });
    try section(&out, a, 5, &.{ 1, 0, 1 });
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(a);
    try names.append(a, 10);
    for ([_][]const u8{ "gama_wasm_v1_init", "gama_wasm_v1_shutdown", "gama_wasm_v1_key", "gama_wasm_v1_pointer", "gama_wasm_v1_resize", "gama_wasm_v1_needs_frame", "gama_wasm_v1_frame", "gama_wasm_v1_frame_ptr", "gama_wasm_v1_frame_len" }, 0..) |name, index| {
        try appendLeb(&names, a, name.len);
        try names.appendSlice(a, name);
        try names.append(a, 0);
        try appendLeb(&names, a, index);
    }
    try names.appendSlice(a, &.{ 6, 'm', 'e', 'm', 'o', 'r', 'y', 2, 0 });
    try section(&out, a, 7, names.items);
    try section(&out, a, 10, &.{ 9, 4, 0, 0x41, 0, 0x0b, 2, 0, 0x0b, 4, 0, 0x41, 0, 0x0b, 4, 0, 0x41, 0, 0x0b, 4, 0, 0x41, 0, 0x0b, 4, 0, 0x41, 0, 0x0b, 4, 0, 0x41, 0, 0x0b, 4, 0, 0x41, 0, 0x0b, 4, 0, 0x41, 0, 0x0b });
    return out.toOwnedSlice(a);
}
test "independent valid module and all structural tamper cases" {
    const a = std.testing.allocator;
    const bytes = try fixture(a);
    defer a.free(bytes);
    try verify(a, bytes);
    try std.testing.expectEqual(@as(usize, 33), try tamperChecks(a, bytes));
    for (0..bytes.len) |n| try rejected(a, bytes[0..n]);
}
fn allocatedVerify(a: std.mem.Allocator, bytes: []const u8) !void {
    try verify(a, bytes);
}
test "verifier allocation failures release bounded type and function storage" {
    const bytes = try fixture(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocatedVerify, .{bytes});
}
