//! Bounded syntactic API superset: all public declarations and ALL container/error
//! members in src, including generic returns, inline options and indirect types.
//! This deliberately includes private implementation container fields, avoiding
//! visibility guesses and blanket owner-field exclusions. Generated Unicode types
//! and tables are included; documentation text is emitted by their generator.
//! Nonempty documentation presence is checked, not semantic contract quality.
const std = @import("std");
const Ast = std.zig.Ast;
const Entry = struct { first: Ast.TokenIndex, name: Ast.TokenIndex, kind: []const u8 };
fn documented(tree: Ast, first: Ast.TokenIndex) bool {
    if (first == 0) return false;
    var t = first;
    var content = false;
    while (t > 0 and tree.tokenTag(t - 1) == .doc_comment) {
        t -= 1;
        if (std.mem.trim(u8, tree.tokenSlice(t)[3..], " \t\r\n").len != 0) content = true;
    }
    return content;
}
fn entries(a: std.mem.Allocator, tree: Ast) !std.ArrayList(Entry) {
    var out: std.ArrayList(Entry) = .empty;
    errdefer out.deinit(a);
    var seen = std.AutoHashMap(Ast.TokenIndex, void).init(a);
    defer seen.deinit();
    for (0..tree.nodes.len) |index| {
        const node: Ast.Node.Index = @fromBackingInt(@intCast(index));
        var entry: ?Entry = null;
        if (tree.fullVarDecl(node)) |v| {
            if (v.visib_token != null) entry = .{ .first = v.firstToken(), .name = v.ast.mut_token + 1, .kind = "declaration" };
        }
        var scratch: [1]Ast.Node.Index = undefined;
        if (tree.fullFnProto(&scratch, node)) |f| {
            if (f.visib_token != null and f.name_token != null) entry = .{ .first = f.firstToken(), .name = f.name_token.?, .kind = "function" };
        }
        if (tree.fullContainerField(node)) |f| entry = .{ .first = f.firstToken(), .name = f.ast.main_token, .kind = "member" };
        if (entry) |e| {
            if (!(try seen.getOrPut(e.first)).found_existing) try out.append(a, e);
        }
        if (tree.nodeTag(node) == .error_set_decl) {
            const bounds = tree.nodeData(node).token_and_token;
            var t = bounds[0] + 1;
            while (t < bounds[1]) : (t += 1) switch (tree.tokenTag(t)) {
                .identifier => if (!(try seen.getOrPut(t)).found_existing) {
                    try out.append(a, .{ .first = t, .name = t, .kind = "error" });
                },
                .comma, .doc_comment => {},
                else => return error.UnknownErrorMemberSyntax,
            };
        }
    }
    return out;
}
fn mentions(tree: Ast, first: Ast.TokenIndex, last: Ast.TokenIndex, names: *const std.StringHashMap(void)) bool {
    var token = first;
    while (token <= last) : (token += 1) {
        if (tree.tokenTag(token) == .identifier and names.contains(tree.tokenSlice(token))) return true;
    }
    return false;
}
// Private generated data must not become a facade API type through a public alias,
// field, function signature, or type factory. Conservatively taint any initializer
// referring to tainted names, and type-returning function bodies, to a fixed point.
// Runtime functions may still read the tables when their public types are clean.
fn checkGenerated(a: std.mem.Allocator, tree: Ast) !void {
    var names = std.StringHashMap(void).init(a);
    defer names.deinit();
    for (0..tree.nodes.len) |i| {
        const node: Ast.Node.Index = @fromBackingInt(@intCast(i));
        if (tree.fullVarDecl(node)) |v| if (v.ast.init_node.unwrap()) |init| {
            var token = tree.firstToken(init);
            while (token <= tree.lastToken(init)) : (token += 1) {
                if (tree.tokenTag(token) == .string_literal and std.mem.endsWith(u8, tree.tokenSlice(token), "tables.zig\"")) {
                    try names.put(tree.tokenSlice(v.ast.mut_token + 1), {});
                }
            }
        };
    }
    if (names.count() == 0) return;
    var changed = true;
    while (changed) {
        changed = false;
        for (0..tree.nodes.len) |i| {
            const node: Ast.Node.Index = @fromBackingInt(@intCast(i));
            if (tree.fullVarDecl(node)) |v| if (v.ast.init_node.unwrap()) |init| {
                if (mentions(tree, tree.firstToken(init), tree.lastToken(init), &names)) {
                    const result = try names.getOrPut(tree.tokenSlice(v.ast.mut_token + 1));
                    if (!result.found_existing) changed = true;
                }
            };
            var scratch: [1]Ast.Node.Index = undefined;
            if (tree.fullFnProto(&scratch, node)) |f| if (f.name_token) |name| {
                if (f.ast.return_type.unwrap()) |t| {
                    // `type` is an identifier in Zig. Scan the whole function node,
                    // including its body; aliases may themselves call private factories.
                    const type_result = std.mem.eql(u8, tree.getNodeSource(t), "type");
                    if (type_result and mentions(tree, tree.firstToken(node), tree.lastToken(node), &names)) {
                        const result = try names.getOrPut(tree.tokenSlice(name));
                        if (!result.found_existing) changed = true;
                    }
                }
            };
        }
    }
    for (0..tree.nodes.len) |i| {
        const node: Ast.Node.Index = @fromBackingInt(@intCast(i));
        if (tree.fullVarDecl(node)) |v| if (v.visib_token != null) {
            if (names.contains(tree.tokenSlice(v.ast.mut_token + 1))) return error.GeneratedApiExposure;
            if (v.ast.init_node.unwrap()) |init| if (mentions(tree, tree.firstToken(init), tree.lastToken(init), &names)) return error.GeneratedApiExposure;
        };
        if (tree.fullContainerField(node)) |f| if (f.ast.type_expr.unwrap()) |t| {
            if (mentions(tree, tree.firstToken(t), tree.lastToken(t), &names)) return error.GeneratedApiExposure;
        };
        var scratch: [1]Ast.Node.Index = undefined;
        if (tree.fullFnProto(&scratch, node)) |f| if (f.visib_token != null) {
            if (f.name_token) |name| if (names.contains(tree.tokenSlice(name))) return error.GeneratedApiExposure;
            if (f.ast.return_type.unwrap()) |t| if (mentions(tree, f.lparen, tree.lastToken(t), &names)) return error.GeneratedApiExposure;
        };
    }
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.ExpectedSourcePaths;
    var count: usize = 0;
    var missing: usize = 0;
    var writer = std.Io.File.stdout().writer(init.io, &.{});
    for (args[1..]) |path| {
        const source = try std.Io.Dir.cwd().readFileAllocOptions(init.io, path, init.gpa, .limited(2 * 1024 * 1024), .of(u8), 0);
        defer init.gpa.free(source);
        var tree = try Ast.parse(init.gpa, source, .{ .mode = .zig });
        defer tree.deinit(init.gpa);
        if (tree.errors.len != 0) return error.InvalidZigSyntax;
        try checkGenerated(init.gpa, tree);
        var inventory = try entries(init.gpa, tree);
        defer inventory.deinit(init.gpa);
        for (inventory.items) |entry| {
            const ok = documented(tree, entry.first);
            count += 1;
            if (!ok) missing += 1;
            try writer.interface.print("{s}\t{d}\t{s}\t{s}\t{s}\t{d}\n", .{ if (ok) "documented" else "missing", tree.tokenStart(entry.first), entry.kind, tree.tokenSlice(entry.name), path, tree.tokenLocation(0, entry.first).line + 1 });
        }
    }
    if (count == 0) return error.EmptyApiInventory;
    std.debug.print("API superset: {d} entries, {d} missing documentation\n", .{ count, missing });
    if (missing != 0) return error.UndocumentedApi;
}
