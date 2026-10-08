//! Independent offline acceptance of the immutable Swift corpus. Every check is
//! an explicit error return (also in Fast); Python assertions are not acceptance.
const std = @import("std");
const A = std.mem.Allocator;
const limit = 8 * 1024 * 1024;
const manifest_hash = "a74ecab3a1e1d7b8873b537a40e650756fa1e27c2b5ad02b1e7c29b09f9511d6";
const Entry = struct { path: []const u8, bytes: usize, sha256: []const u8 };
const Manifest = struct {
    schema: u32,
    baselineHEAD: []const u8,
    baselineDirtyPatch: []const u8,
    intBits: u32,
    fixtureEncoding: []const u8,
    generator: []const u8,
    generatorSHA256: []const u8,
    captureCommands: []const u8,
    fixtures: []Entry,
    directoryCase: []const u8,
};
fn digest(bytes: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}
fn checkManifestHash(bytes: []const u8) !void {
    if (!std.mem.eql(u8, &digest(bytes), manifest_hash)) return error.ManifestHashMismatch;
}
fn checkEntries(entries: []const Entry) !void {
    if (entries.len == 0) return error.EmptyCorpus;
    for (entries, 0..) |entry, i| {
        if (!std.mem.startsWith(u8, entry.path, "swift-baseline/") or entry.path.len <= 15) return error.UnsafePath;
        const name = entry.path[15..];
        if (std.mem.indexOfAny(u8, name, "/\\") != null or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return error.UnsafePath;
        if (entry.bytes > limit or entry.sha256.len != 64) return error.InvalidEntry;
        for (entry.sha256) |c| if (!std.ascii.isHex(c) or (c >= 'A' and c <= 'F')) return error.InvalidEntry;
        for (entries[0..i]) |prior| if (std.mem.eql(u8, entry.path, prior.path)) return error.DuplicateEntry;
    }
}
fn checkContent(a: A, entry: Entry, bytes: []const u8) !void {
    if (bytes.len != entry.bytes) return error.SizeMismatch;
    if (!std.mem.eql(u8, &digest(bytes), entry.sha256)) return error.HashMismatch;
    if (std.mem.endsWith(u8, entry.path, ".gama")) {
        if (bytes.len < 20 or !std.mem.eql(u8, bytes[0..4], "GAMA") or std.mem.readInt(u32, bytes[4..8], .little) != 1) return error.InvalidWireHeader;
    } else {
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
        if (std.mem.endsWith(u8, entry.path, ".json")) {
            const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
            defer parsed.deinit();
        }
    }
}
fn verify(a: A, io: std.Io, dir: std.Io.Dir, entries: []const Entry) !void {
    try checkEntries(entries);
    for (entries) |entry| {
        const stat = try dir.statFile(io, entry.path, .{ .follow_symlinks = false });
        if (stat.kind != .file) return error.NonRegularFixture;
        const bytes = try dir.readFileAlloc(io, entry.path, a, .limited(limit));
        defer a.free(bytes);
        try checkContent(a, entry, bytes);
    }
    var fixtures = try dir.openDir(io, "swift-baseline", .{ .iterate = true, .follow_symlinks = false });
    defer fixtures.close(io);
    var it = fixtures.iterate();
    var count: usize = 0;
    while (try it.next(io)) |file| {
        if (file.kind != .file) return error.NonRegularFixture;
        var found = false;
        for (entries) |entry| if (std.mem.eql(u8, entry.path[15..], file.name)) {
            found = true;
            break;
        };
        if (!found) return error.UnlistedFixture;
        count += 1;
    }
    if (count != entries.len) return error.IncompleteCorpus;
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 2) return error.Usage;
    var dir = try std.Io.Dir.cwd().openDir(init.io, if (args.len == 2) args[1] else "tests/parity", .{});
    defer dir.close(init.io);
    const bytes = try dir.readFileAlloc(init.io, "manifest.json", init.gpa, .limited(limit));
    defer init.gpa.free(bytes);
    try checkManifestHash(bytes);
    const parsed = try std.json.parseFromSlice(Manifest, init.gpa, bytes, .{});
    defer parsed.deinit();
    if (parsed.value.schema != 1 or parsed.value.intBits != 64 or !std.mem.eql(u8, parsed.value.baselineHEAD, "b8ce774285c79d83a4bf3ffff7b11975d4716af2")) return error.InvalidManifest;
    try verify(init.gpa, init.io, dir, parsed.value.fixtures);
    std.debug.print("Gama corpus: {d} immutable fixtures verified (manifest, SHA256, sizes, totality, content)\n", .{parsed.value.fixtures.len});
}
test "manifest tampering and missing duplicate escaping entries fail explicitly" {
    try std.testing.expectError(error.ManifestHashMismatch, checkManifestHash("{}"));
    try std.testing.expectError(error.EmptyCorpus, checkEntries(&.{}));
    const good: Entry = .{ .path = "swift-baseline/a.json", .bytes = 2, .sha256 = &digest("{}") };
    try checkEntries(&.{good});
    try std.testing.expectError(error.DuplicateEntry, checkEntries(&.{ good, good }));
    for ([_][]const u8{ "/tmp/a", "swift-baseline/../a", "swift-baseline/a/b", "swift-baseline/..", "swift-baseline/a\\b" }) |path| {
        var bad = good;
        bad.path = path;
        try std.testing.expectError(error.UnsafePath, checkEntries(&.{bad}));
    }
}
test "fixture bytes size UTF8 JSON and version tampering fail explicitly" {
    const alloc = std.testing.allocator;
    var entry: Entry = .{ .path = "swift-baseline/a.json", .bytes = 2, .sha256 = &digest("{}") };
    try std.testing.expectError(error.SizeMismatch, checkContent(alloc, entry, "x"));
    try std.testing.expectError(error.HashMismatch, checkContent(alloc, entry, "[]"));
    entry.sha256 = &digest("xx");
    try std.testing.expectError(error.SyntaxError, checkContent(alloc, entry, "xx"));
    entry.sha256 = &digest("\xff\xff");
    try std.testing.expectError(error.InvalidUtf8, checkContent(alloc, entry, "\xff\xff"));
    entry.path = "swift-baseline/a.gama";
    entry.sha256 = &digest("xx");
    try std.testing.expectError(error.InvalidWireHeader, checkContent(alloc, entry, "xx"));
}
test "filesystem missing extra same-size mutation and directory tampering fail closed" {
    const io = std.testing.io;
    const alloc = std.testing.allocator;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(io, "swift-baseline", .default_dir);
    const entry: Entry = .{ .path = "swift-baseline/a.json", .bytes = 2, .sha256 = &digest("{}") };
    try std.testing.expectError(error.FileNotFound, verify(alloc, io, temp.dir, &.{entry}));
    try temp.dir.writeFile(io, .{ .sub_path = entry.path, .data = "{}" });
    try verify(alloc, io, temp.dir, &.{entry});
    try temp.dir.writeFile(io, .{ .sub_path = entry.path, .data = "[]" });
    try std.testing.expectError(error.HashMismatch, verify(alloc, io, temp.dir, &.{entry}));
    try temp.dir.writeFile(io, .{ .sub_path = entry.path, .data = "{}" });
    try temp.dir.writeFile(io, .{ .sub_path = "swift-baseline/extra", .data = "x" });
    try std.testing.expectError(error.UnlistedFixture, verify(alloc, io, temp.dir, &.{entry}));
    // A second isolated directory exercises non-files without deleting corpus data.
    var dirs = std.testing.tmpDir(.{});
    defer dirs.cleanup();
    try dirs.dir.createDir(io, "swift-baseline", .default_dir);
    try dirs.dir.createDir(io, "swift-baseline/a.json", .default_dir);
    try std.testing.expectError(error.NonRegularFixture, verify(alloc, io, dirs.dir, &.{entry}));
}
test "symlink fixture cannot substitute external data" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(io, "swift-baseline", .default_dir);
    try temp.dir.writeFile(io, .{ .sub_path = "outside.json", .data = "{}" });
    try temp.dir.symLink(io, "../outside.json", "swift-baseline/a.json", .{});
    const entry: Entry = .{ .path = "swift-baseline/a.json", .bytes = 2, .sha256 = &digest("{}") };
    try std.testing.expectError(error.NonRegularFixture, verify(std.testing.allocator, io, temp.dir, &.{entry}));
}
