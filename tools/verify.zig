//! Bounded, std-only repository policy verifier. No external tools or network.
const std = @import("std");
const policy = @import("policy.zig");
const limit = 4 * 1024 * 1024;

const Pin = struct {
    version: []const u8,
    revision: []const u8,
    aarch64_macos_url: []const u8,
    aarch64_macos_sha256: []const u8,
};
const Package = struct {
    name: enum { gama },
    version: []const u8,
    fingerprint: u64,
    minimum_zig_version: []const u8,
    dependencies: struct {},
    paths: []const []const u8,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedPolicyMode;
    try checkPins(init.gpa, init.io);
    const portable_only = std.mem.eql(u8, args[1], "portable");
    if (!portable_only and !std.mem.eql(u8, args[1], "all")) return error.InvalidPolicyMode;
    try checkSources(init.gpa, init.io, portable_only);
    const embedded = try read(init.gpa, init.io, "examples/embedded_app.zig");
    defer init.gpa.free(embedded);
    if (!policy.allowedEmbeddedWorkload(embedded)) return error.ForbiddenEmbeddedWorkload;

    std.debug.print("Gama {s} source/pin policies passed\n", .{args[1]});
}

fn read(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![:0]u8 {
    return std.Io.Dir.cwd().readFileAllocOptions(io, path, gpa, .limited(limit), .of(u8), 0);
}

fn checkPins(gpa: std.mem.Allocator, io: std.Io) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const pin_bytes = try read(gpa, io, "ZigToolchain.zon");
    defer gpa.free(pin_bytes);
    const pin = try std.zon.parse.fromSlice(Pin, .{ .gpa = gpa, .arena = arena.allocator(), .source = pin_bytes, .diagnostics = &diagnostics });
    if (!policy.validVersion(pin.version) or
        !std.mem.eql(u8, pin.revision, policy.revision) or
        !std.mem.eql(u8, pin.aarch64_macos_url, policy.archive_url) or
        !std.mem.eql(u8, pin.aarch64_macos_sha256, policy.archive_sha256)) return error.ToolchainPinMismatch;
    const version_bytes = try read(gpa, io, ".zig-version");
    defer gpa.free(version_bytes);
    if (!std.mem.eql(u8, version_bytes, policy.version ++ "\n")) return error.VersionFileMismatch;
    const package_bytes = try read(gpa, io, "build.zig.zon");
    defer gpa.free(package_bytes);
    const package = try std.zon.parse.fromSlice(Package, .{ .gpa = gpa, .arena = arena.allocator(), .source = package_bytes, .diagnostics = &diagnostics });
    if (!policy.validVersion(package.minimum_zig_version)) return error.PackagePinMismatch;
}

fn checkSources(gpa: std.mem.Allocator, io: std.Io, portable_only: bool) !void {
    var root = try std.Io.Dir.cwd().openDir(io, if (portable_only) "src" else ".", .{ .iterate = true });
    defer root.close(io);
    var walker = try root.walkSelectively(gpa);
    defer walker.deinit();
    var entries: usize = 0;
    var portable_count: usize = 0;
    while (try walker.next(io)) |entry| {
        entries += 1;
        if (entries > 100_000 or entry.path.len > 4096) return error.SourceScanLimit;
        if (entry.kind == .directory) {
            if (excluded(entry.path)) continue;
            if (!portable_only and !std.mem.eql(u8, entry.path, "GamaStudio") and !std.mem.eql(u8, entry.path, "qt") and !policy.allowedSourcePath(entry.path)) {
                std.debug.print("retirement policy rejects {s}\n", .{entry.path});
                return error.ForbiddenSource;
            }
            try walker.enter(io, entry);
            continue;
        }
        if (entry.kind == .sym_link) return error.SourceSymlink;
        if (entry.kind != .file) continue;
        const path = if (portable_only) try std.fmt.allocPrint(gpa, "src/{s}", .{entry.path}) else try gpa.dupe(u8, entry.path);
        defer gpa.free(path);
        if (policy.under(path, "src") and !std.mem.endsWith(u8, path, ".zig") and !std.mem.endsWith(u8, path, ".md") and !std.mem.eql(u8, std.fs.path.basename(path), ".DS_Store")) return error.ForbiddenSource;
        if (!policy.allowedSourcePath(path)) {
            std.debug.print("retirement policy rejects {s}\n", .{path});
            return error.ForbiddenSource;
        }
        if (!policy.under(path, "tests") and std.mem.endsWith(u8, path, ".zig")) {
            const source = try read(gpa, io, path);
            defer gpa.free(source);
            if (!policy.allowedProductionSource(source)) {
                std.debug.print("production binding policy rejects {s}\n", .{path});
                return error.ForbiddenBinding;
            }
            const facade = std.mem.eql(u8, path, "src/root.zig");
            if (policy.under(path, "src/abi") or std.mem.eql(u8, path, "src/c_embed.zig") or std.mem.eql(u8, path, "src/wasm.zig")) {
                if (!policy.allowedAbiSource(source) or !checkLocalImports(gpa, source, path)) return error.ForbiddenImport;
                try checkImportFiles(gpa, io, source, path);
                continue;
            }
            if (policy.under(path, "src/tui")) {
                if (!policy.allowedTerminalSource(source) or !checkLocalImports(gpa, source, path)) return error.ForbiddenImport;
                try checkImportFiles(gpa, io, source, path);
                continue;
            }
            if (std.mem.eql(u8, path, "src/services/native_guard.zig")) {
                if (!policy.allowedNativeSource(source) or !checkLocalImports(gpa, source, path)) return error.ForbiddenImport;
                try checkImportFiles(gpa, io, source, path);
                continue;
            }
            if (std.mem.eql(u8, path, "src/services/hosted.zig")) {
                if (!policy.allowedHostedSource(source) or !checkLocalImports(gpa, source, path)) return error.ForbiddenImport;
                try checkImportFiles(gpa, io, source, path);
                continue;
            }
            if (!policy.portablePath(path) and !facade) continue;
            portable_count += 1;
            if (!(if (facade) policy.allowedFacadeSource(source) else policy.allowedPortableSource(source)) or !checkLocalImports(gpa, source, path)) {
                std.debug.print("portable import policy rejects {s}\n", .{path});
                return error.ForbiddenImport;
            }
            try checkImportFiles(gpa, io, source, path);
        }
    }
    if (portable_count == 0) return error.NoPortableSources;
}

fn excluded(path: []const u8) bool {
    for ([_][]const u8{ ".git", ".zig-cache", "zig-out", ".build", ".swiftpm", ".superpowers", ".agents", ".claude", ".kungfu", ".remember", "GamaStudio/.build", "qt/.build" }) |name| {
        if (policy.under(path, name)) return true;
    }
    return false;
}

fn checkLocalImports(gpa: std.mem.Allocator, source: [:0]const u8, path: []const u8) bool {
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag != .builtin or !std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import")) continue;
        _ = tokenizer.next();
        const literal = tokenizer.next();
        if (literal.tag != .string_literal) return false;
        const import = source[literal.loc.start + 1 .. literal.loc.end - 1];
        if (std.mem.eql(u8, import, "std") or std.mem.eql(u8, import, "builtin")) continue;
        const resolved = std.fs.path.resolveAllocPosix(gpa, &.{ "/", std.fs.path.dirname(path) orelse return false, import }) catch return false;
        defer gpa.free(resolved);
        const native_edge = std.mem.eql(u8, path, "src/root.zig") and (std.mem.eql(u8, import, "services/native_guard.zig") or std.mem.eql(u8, import, "services/hosted.zig") or std.mem.eql(u8, import, "tui/root.zig") or std.mem.eql(u8, import, "abi/root.zig"));
        const service_guard_edge = std.mem.eql(u8, path, "src/services/hosted.zig") and std.mem.eql(u8, import, "native_guard.zig");
        const terminal_edge = policy.under(path, "src/tui") and (policy.under(resolved[1..], "src/tui") or std.mem.eql(u8, resolved[1..], "src/services/native_guard.zig"));
        const abi_edge = (policy.under(path, "src/abi") or std.mem.eql(u8, path, "src/c_embed.zig") or std.mem.eql(u8, path, "src/wasm.zig")) and (policy.under(resolved[1..], "src/abi") or std.mem.eql(u8, resolved[1..], "src/root.zig"));
        if (resolved.len == 0 or (!policy.portablePath(resolved[1..]) and !native_edge and !service_guard_edge and !terminal_edge and !abi_edge)) return false;
    }
}

test "strict package schema rejects dependencies and unknown fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const DependencyTable = struct { dependencies: struct {} };
    const valid = try std.zon.parse.fromSliceNoAlloc(DependencyTable, .{ .gpa = std.testing.allocator, .arena = arena.allocator(), .source = ".{ .dependencies = .{} }", .diagnostics = &diagnostics });
    _ = valid;
    try std.testing.expectError(error.ParseZon, std.zon.parse.fromSliceNoAlloc(DependencyTable, .{ .gpa = std.testing.allocator, .arena = arena.allocator(), .source = ".{ .dependencies = .{ .foreign = .{} } }", .diagnostics = &diagnostics }));
    try std.testing.expectError(error.ParseZon, std.zon.parse.fromSliceNoAlloc(DependencyTable, .{ .gpa = std.testing.allocator, .arena = arena.allocator(), .source = ".{ .dependencies = .{}, .unapproved = true }", .diagnostics = &diagnostics }));
}

test "relative portable imports cannot escape into hosted or foreign trees" {
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../root.zig\");", "src/core/node.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../../tools/policy.zig\");", "src/core/node.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../services/io.zig\");", "src/core/node.zig"));
}

fn checkImportFiles(gpa: std.mem.Allocator, io: std.Io, source: [:0]const u8, path: []const u8) !void {
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return;
        if (token.tag != .builtin or !std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import")) continue;
        _ = tokenizer.next();
        const literal = tokenizer.next();
        if (literal.tag != .string_literal) return error.ForbiddenImport;
        const import = source[literal.loc.start + 1 .. literal.loc.end - 1];
        if (std.mem.eql(u8, import, "std") or std.mem.eql(u8, import, "builtin")) continue;
        const resolved = try std.fs.path.resolveAllocPosix(gpa, &.{ "/", std.fs.path.dirname(path) orelse return error.ForbiddenImport, import });
        defer gpa.free(resolved);
        const stat = try std.Io.Dir.cwd().statFile(io, resolved[1..], .{ .follow_symlinks = false });
        if (stat.kind != .file) return error.ForbiddenImport;
    }
}

test "service local import edges reject sibling and facade detours" {
    try std.testing.expect(checkLocalImports(std.testing.allocator, "const x = @import(\"native_guard.zig\");", "src/services/hosted.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../services/other.zig\");", "src/plugins/root.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../root.zig\");", "src/plugins/root.zig"));
}

test "terminal resolved imports cannot grant portable callers hosted access" {
    try std.testing.expect(checkLocalImports(std.testing.allocator, "const x = @import(\"../services/native_guard.zig\");", "src/tui/terminal.zig"));
    try std.testing.expect(checkLocalImports(std.testing.allocator, "const x = @import(\"runtime.zig\");", "src/tui/root.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../tui/root.zig\");", "src/core/host.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../../tools/verify.zig\");", "src/tui/root.zig"));
}

test "ABI resolved edges do not grant core access to adapters" {
    try std.testing.expect(checkLocalImports(std.testing.allocator, "const x = @import(\"../root.zig\");", "src/abi/context.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../abi/root.zig\");", "src/core/node.zig"));
    try std.testing.expect(!checkLocalImports(std.testing.allocator, "const x = @import(\"../../tools/verify.zig\");", "src/abi/context.zig"));
}
