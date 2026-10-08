const std = @import("std");

pub const version = "0.17.0-dev.2338+b46a7f3a2";
pub const revision = "b46a7f3a25a61c68bbc25759087a01095dc8446e";
pub const archive_url = "https://ziglang.org/builds/zig-aarch64-macos-0.17.0-dev.2338+b46a7f3a2.tar.xz";
pub const archive_sha256 = "6823e45e4f4b9b7eab5230baa06d9e59ea9e1f19e88d3eb29946d02111bfedd4";

pub fn validVersion(actual: []const u8) bool {
    return std.mem.eql(u8, actual, version);
}

pub fn requireVersion(comptime actual: []const u8) void {
    if (!validVersion(actual)) @compileError("Gama requires Zig " ++ version);
}

pub fn emptyDependencies(dependencies: anytype) bool {
    return @typeInfo(@TypeOf(dependencies)).@"struct".field_names.len == 0;
}

pub fn requireEmptyDependencies(comptime dependencies: anytype) void {
    if (!emptyDependencies(dependencies)) @compileError("Gama forbids package dependencies");
}

/// The final source policy applies to the entire repository, including retired apps.
pub fn allowedSourcePath(path: []const u8) bool {
    if (under(path, "GamaStudio") or under(path, "qt")) return false;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, "vendor") or std.mem.eql(u8, component, "third_party") or std.mem.eql(u8, component, "node_modules") or std.mem.endsWith(u8, component, ".framework")) return false;
    }
    if (std.mem.eql(u8, path, "include/GamaEmbed.h")) return true;
    if (under(path, "tests") and (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h"))) return true;
    for ([_][]const u8{ ".swift", ".c", ".h", ".cc", ".cpp", ".cxx", ".m", ".mm", ".a", ".dylib", ".so", ".dll" }) |extension| {
        if (std.mem.endsWith(u8, path, extension)) return false;
    }
    return true;
}

pub fn requireSourcePath(comptime path: []const u8) void {
    if (!allowedSourcePath(path)) @compileError("Gama forbids legacy or foreign sources");
}

/// Production uses std OS facilities; C declarations are limited to layout types.
pub fn allowedProductionSource(source: [:0]const u8) bool {
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag == .invalid) return false;
        const text = source[token.loc.start..token.loc.end];
        if (token.tag == .builtin and
            (std.mem.eql(u8, text, "@cImport") or std.mem.eql(u8, text, "@cInclude") or std.mem.eql(u8, text, "@extern"))) return false;
        if (token.tag == .keyword_extern and tokenizer.next().tag != .keyword_struct) return false;
    }
}

pub fn under(path: []const u8, directory: []const u8) bool {
    return std.mem.eql(u8, path, directory) or
        (std.mem.startsWith(u8, path, directory) and path.len > directory.len and path[directory.len] == '/');
}

pub fn portablePath(path: []const u8) bool {
    if (std.mem.eql(u8, path, "src/root.zig")) return false;
    for ([_][]const u8{ "src/core", "src/draw", "src/plugins", "src/mlir" }) |directory| {
        if (under(path, directory)) return true;
    }
    return false;
}

/// Zig tokenization ignores comments/ordinary string contents; imports must be literals.
pub fn allowedPortableSource(source: [:0]const u8) bool {
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag == .invalid) return false;
        const text = source[token.loc.start..token.loc.end];
        if (token.tag == .builtin) {
            if (std.mem.eql(u8, text, "@cImport") or std.mem.eql(u8, text, "@cInclude") or std.mem.eql(u8, text, "@extern")) return false;
            if (std.mem.eql(u8, text, "@import")) {
                if (tokenizer.next().tag != .l_paren) return false;
                const literal = tokenizer.next();
                if (literal.tag != .string_literal) return false;
                const import = source[literal.loc.start + 1 .. literal.loc.end - 1];
                if (!allowedImport(import)) return false;
                if (tokenizer.next().tag != .r_paren) return false;
            }
        }
        if (token.tag == .period) {
            const member = tokenizer.next();
            var name = source[member.loc.start..member.loc.end];
            if (std.mem.startsWith(u8, name, "@\"")) {
                name = name[2 .. name.len - 1];
                if (std.mem.indexOfScalar(u8, name, '\\') != null) return false;
            }
            for ([_][]const u8{ "process", "Io", "Thread", "os", "posix", "c", "DynLib", "page_allocator", "getCurrentId" }) |forbidden| {
                if (std.mem.eql(u8, name, forbidden)) return false;
            }
        }
    }
}

pub fn allowedImport(import: []const u8) bool {
    if (std.mem.eql(u8, import, "std") or std.mem.eql(u8, import, "builtin")) return true;
    if (std.mem.indexOfScalar(u8, import, '\\') != null or std.mem.startsWith(u8, import, "/")) return false;
    if (!std.mem.endsWith(u8, import, ".zig")) return false;
    var segments = std.mem.splitScalar(u8, import, '/');
    while (segments.next()) |segment| {
        if (std.mem.eql(u8, segment, "tui") or std.mem.eql(u8, segment, "services") or std.mem.eql(u8, segment, "abi")) return false;
    }
    return true;
}

pub fn requirePortableSource(comptime source: [:0]const u8) void {
    if (!allowedPortableSource(source)) @compileError("Gama forbids hosted or foreign portable imports");
}

test "compiler version is an exact pin" {
    try std.testing.expect(validVersion("0.17.0-dev.2338+b46a7f3a2"));
    try std.testing.expect(!validVersion("0.17.0-dev.2339+b46a7f3a2"));
    try std.testing.expect(!validVersion("0.17.0-dev.2338+b46a7f3a2-dirty"));
}

test "package dependency policy rejects any dependency" {
    try std.testing.expect(emptyDependencies(.{}));
    try std.testing.expect(!emptyDependencies(.{ .foreign = .{} }));
}

test "retirement policy rejects legacy and native helper sources" {
    for ([_][]const u8{ "Sources/gama/App.swift", "GamaStudio/build.zig", "qt/build.zig", "src/bridge.c", "src/bridge.h", "src/bridge.cpp", "vendor/library.zig", "src/third_party/library.zig", "Frameworks/AppKit.framework/Info.plist" }) |path|
        try std.testing.expect(!allowedSourcePath(path));
    try std.testing.expect(allowedSourcePath("src/root.zig"));
    try std.testing.expect(allowedSourcePath("tests/parity/core.json"));
    try std.testing.expect(allowedSourcePath("include/GamaEmbed.h"));
    try std.testing.expect(allowedSourcePath("tests/embed_consumer.c"));
}

test "production rejects handwritten OS bindings while permitting ABI layout" {
    try std.testing.expect(!allowedProductionSource("extern fn sigaction() void;"));
    try std.testing.expect(!allowedProductionSource("const x = @extern(*const anyopaque, .{.name = \"objc_msgSend\"});"));
    try std.testing.expect(!allowedProductionSource("const x = @cImport({});"));
    try std.testing.expect(allowedProductionSource("const Layout = extern struct { value: i32 };"));
}

test "portable imports reject hosted and foreign access" {
    try std.testing.expect(!allowedPortableSource("const x = @import(\"std\").process;"));
    try std.testing.expect(!allowedPortableSource("const x = @import(\"std\").@\"process\";"));
    try std.testing.expect(!allowedPortableSource("const std = @import(\"std\"); const x = std.heap.page_allocator;"));
    try std.testing.expect(!allowedPortableSource("const x = @cImport({});"));
    try std.testing.expect(!allowedPortableSource("const x = @import(\"../services/io.zig\");"));
    try std.testing.expect(allowedPortableSource("const std = @import(\"std\"); const Allocator = std.mem.Allocator;"));
    try std.testing.expect(allowedPortableSource("const fields = @typeInfo(T).@\"struct\".field_names;"));
    try std.testing.expect(allowedPortableSource("// std.process and @cImport are forbidden\nconst text = \"std.heap.page_allocator\";"));
}

// The sole facade-to-hosted edge must occur in this exact, target-aware selector.
pub const guard_selector = "const SelectedGuard = if (@import(\"builtin\").target.os.tag == .freestanding) @import(\"core/state.zig\").SingleExecutor else @import(\"services/native_guard.zig\").NativeGuard;";
pub const hosted_selector = "pub const HostedServices = if (@import(\"builtin\").target.os.tag == .freestanding) void else @import(\"services/hosted.zig\").HostedServices;";
pub const tui_selector = "pub const tui = if (@import(\"builtin\").target.os.tag == .freestanding) void else @import(\"tui/root.zig\");";
pub const abi_selector = "pub const abi = @import(\"abi/root.zig\");";
pub fn allowedFacadeSource(source: [:0]const u8) bool {
    if (source.len > 32768) return false;
    var filtered: [32769]u8 = undefined;
    @memcpy(filtered[0..source.len], source);
    filtered[source.len] = 0;
    const guard_start = std.mem.indexOf(u8, source, guard_selector) orelse return false;
    @memset(filtered[guard_start .. guard_start + guard_selector.len], ' ');
    if (std.mem.indexOf(u8, source, hosted_selector)) |start| @memset(filtered[start .. start + hosted_selector.len], ' ');
    if (std.mem.indexOf(u8, source, tui_selector)) |start| @memset(filtered[start .. start + tui_selector.len], ' ');
    if (std.mem.indexOf(u8, source, abi_selector)) |start| @memset(filtered[start .. start + abi_selector.len], ' ');
    return allowedPortableSource(filtered[0..source.len :0]);
}
pub fn allowedHostedSource(source: [:0]const u8) bool {
    if (!allowedProductionSource(source)) return false;
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag == .invalid) return false;
        if (token.tag != .builtin or !std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import")) continue;
        if (tokenizer.next().tag != .l_paren) return false;
        const literal = tokenizer.next();
        if (literal.tag != .string_literal) return false;
        const name = source[literal.loc.start + 1 .. literal.loc.end - 1];
        var allowed = false;
        for ([_][]const u8{ "std", "../plugins/root.zig", "../core/state.zig", "native_guard.zig" }) |candidate| if (std.mem.eql(u8, name, candidate)) {
            allowed = true;
        };
        if (!allowed or tokenizer.next().tag != .r_paren) return false;
    }
}
/// Hosted terminal imports stay within this explicit adapter boundary.
pub fn allowedTerminalSource(source: [:0]const u8) bool {
    if (!allowedProductionSource(source)) return false;
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag == .invalid) return false;
        if (token.tag != .builtin or !std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import")) continue;
        if (tokenizer.next().tag != .l_paren) return false;
        const literal = tokenizer.next();
        if (literal.tag != .string_literal) return false;
        const name = source[literal.loc.start + 1 .. literal.loc.end - 1];
        var allowed = false;
        for ([_][]const u8{ "std", "builtin", "root.zig", "decoder.zig", "terminal.zig", "runtime.zig", "../services/native_guard.zig", "../core/state.zig", "../core/geometry.zig", "../core/input.zig", "../core/host.zig", "../core/pump.zig", "../draw/pump.zig" }) |candidate| if (std.mem.eql(u8, name, candidate)) {
            allowed = true;
        };
        if (!allowed or tokenizer.next().tag != .r_paren) return false;
    }
}
pub fn allowedNativeSource(source: [:0]const u8) bool {
    if (!allowedProductionSource(source)) return false;
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag == .invalid) return false;
        if (token.tag != .builtin or !std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import")) continue;
        if (tokenizer.next().tag != .l_paren) return false;
        const literal = tokenizer.next();
        if (literal.tag != .string_literal) return false;
        const name = source[literal.loc.start + 1 .. literal.loc.end - 1];
        if (!std.mem.eql(u8, name, "std") and !std.mem.eql(u8, name, "builtin") and !std.mem.eql(u8, name, "../core/state.zig")) return false;
        if (tokenizer.next().tag != .r_paren) return false;
    }
}
test "facade exception is exact target selected and cannot admit other hosted edges" {
    try std.testing.expect(allowedFacadeSource(guard_selector));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ "const x = @import(\"services/other.zig\");"));
    try std.testing.expect(!allowedFacadeSource("const SelectedGuard = @import(\"services/native_guard.zig\").NativeGuard;"));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ "const x = @import(name);"));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ "const x = @import(\"gama_execution\");"));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ "const x = @import(\"services\\x2fnative_guard.zig\");"));
    try std.testing.expect(!allowedNativeSource("const x = @import(\"../../tools/policy.zig\");"));
    try std.testing.expect(!allowedNativeSource("extern fn pthread_self() u64;"));
}

test "hosted service selector and adapter import edges are exact" {
    try std.testing.expect(allowedFacadeSource(guard_selector ++ hosted_selector));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ hosted_selector ++ hosted_selector));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ "pub const HostedServices = @import(\"services/hosted.zig\").HostedServices;"));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ hosted_selector ++ "const x = @import(\"services/other.zig\");"));
    try std.testing.expect(allowedHostedSource("const x = @import(\"native_guard.zig\"); const p = @import(\"../plugins/root.zig\");"));
    try std.testing.expect(!allowedHostedSource("const x = @import(\"../abi/host.zig\");"));
    try std.testing.expect(!allowedHostedSource("const x = @import(name);"));
    try std.testing.expect(!allowedHostedSource("extern fn open() void;"));
}

test "terminal exception admits only scoped std-backed adapter imports" {
    try std.testing.expect(allowedTerminalSource("const x = @import(\"terminal.zig\"); const y = @import(\"../core/host.zig\");"));
    try std.testing.expect(!allowedTerminalSource("const x = @import(\"../services/hosted.zig\");"));
    try std.testing.expect(!allowedTerminalSource("const x = @import(\"../../foreign.zig\");"));
    try std.testing.expect(!allowedTerminalSource("extern fn sigaction() void;"));
    try std.testing.expect(!allowedPortableSource("const x = @import(\"../tui/root.zig\");"));
    try std.testing.expect(allowedFacadeSource(guard_selector ++ "\n" ++ tui_selector));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ "\npub const tui = @import(\"tui/root.zig\");"));
}

/// ABI roots alone may reach the target-selected facade and adapter-local code.
/// No arbitrary services/OS binding imports are admitted through this boundary.
pub fn allowedAbiSource(source: [:0]const u8) bool {
    if (!allowedProductionSource(source)) return false;
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag == .invalid) return false;
        if (token.tag != .builtin or !std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import")) continue;
        if (tokenizer.next().tag != .l_paren) return false;
        const literal = tokenizer.next();
        if (literal.tag != .string_literal) return false;
        const name = source[literal.loc.start + 1 .. literal.loc.end - 1];
        var allowed = false;
        for ([_][]const u8{ "std", "builtin", "../root.zig", "root.zig", "context.zig", "input.zig", "pull.zig", "c.zig", "wasm.zig", "abi/c.zig", "abi/wasm.zig" }) |candidate| if (std.mem.eql(u8, name, candidate)) {
            allowed = true;
        };
        if (!allowed or tokenizer.next().tag != .r_paren) return false;
    }
}
test "ABI import exception cannot introduce raw OS or hosted implementation detours" {
    try std.testing.expect(allowedAbiSource("const g = @import(\"../root.zig\"); const c = @import(\"context.zig\");"));
    try std.testing.expect(!allowedAbiSource("const x = @import(\"../services/hosted.zig\");"));
    try std.testing.expect(!allowedAbiSource("const x = @cImport({});"));
    try std.testing.expect(allowedFacadeSource(guard_selector ++ abi_selector));
    try std.testing.expect(!allowedFacadeSource(guard_selector ++ "const x = @import(\"abi/context.zig\");"));
}

/// Embedded workload imports only std and the target-selecting facade. This
/// separate root cannot hide page allocation behind a successfully static ELF.
pub fn allowedEmbeddedWorkload(source: [:0]const u8) bool {
    if (source.len > 32768 or !allowedProductionSource(source)) return false;
    const facade = "const g = @import(\"gama\");";
    const start = std.mem.indexOf(u8, source, facade) orelse return false;
    var filtered: [32769]u8 = undefined;
    @memcpy(filtered[0..source.len], source);
    filtered[source.len] = 0;
    @memset(filtered[start .. start + facade.len], ' ');
    const rest = filtered[0..source.len :0];
    if (!allowedPortableSource(rest)) return false;
    var tokenizer = std.zig.Tokenizer.init(rest);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return true;
        if (token.tag != .builtin or !std.mem.eql(u8, rest[token.loc.start..token.loc.end], "@import")) continue;
        _ = tokenizer.next();
        const literal = tokenizer.next();
        if (!std.mem.eql(u8, rest[literal.loc.start..literal.loc.end], "\"std\"")) return false;
    }
}
test "embedded workload rejects linked hosted allocator and helper detours" {
    const prefix = "const g = @import(\"gama\"); const std = @import(\"std\");";
    try std.testing.expect(allowedEmbeddedWorkload(prefix ++ "fn f() void { var a: [64]u8 = undefined; _ = std.heap.FixedBufferAllocator.init(&a); }"));
    try std.testing.expect(!allowedEmbeddedWorkload(prefix ++ "const a = std.heap.page_allocator;"));
    try std.testing.expect(!allowedEmbeddedWorkload(prefix ++ "const hidden = @import(\"hosted.zig\");"));
    try std.testing.expect(!allowedEmbeddedWorkload(prefix ++ "extern fn malloc(n: usize) ?*anyopaque;"));
}
