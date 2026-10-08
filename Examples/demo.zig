//! Counter and grapheme-aware form on the same adaptive terminal/plain host.
const std = @import("std");
const g = @import("gama");
const App = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    const Change = struct { value: g.StateRef(i64), delta: i64 };
    fn change(c: *const Change, _: *anyopaque) g.Error!void {
        try c.value.set((try c.value.read()).* + c.delta);
    }
    fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        const count = try ctx.state(i64, 0, 0);
        const name = try ctx.state(g.String, 1, .{ .bytes = "" });
        var minus = ctx.child(0);
        var plus = ctx.child(1);
        var field = ctx.child(2);
        const focused: []const u8 = if (ctx.focus) |id| (if (id.raw == minus.id.raw) "-1" else if (id.raw == plus.id.raw) "+1" else if (id.raw == field.id.raw) "name" else "none") else "none";
        const children = [_]g.Node{
            .{ .text = .{ .content = try std.fmt.allocPrint(ctx.allocator, "Gama counter | count {d} | focus {s}", .{ (try count.read()).*, focused }) } },
            try (try g.authoring.buttonTitle(&minus, "-1", try minus.action(Change{ .value = count, .delta = -1 }, change))).render(&minus),
            try (try g.authoring.buttonTitle(&plus, "+1", try plus.action(Change{ .value = count, .delta = 1 }, change))).render(&plus),
            .{ .text = .{ .content = "Name:" } },
            try (g.authoring.TextField{ .value = (try name.read()).bytes, .placeholder = "type here", .binding = name.token }).render(&field),
            .{ .text = .{ .content = try std.fmt.allocPrint(ctx.allocator, "name [{s}]", .{(try name.read()).bytes}) } },
            .{ .text = .{ .content = "Tab: focus | Enter: activate | Ctrl-C: quit" } },
        };
        return .{ .stack = .{ .axis = .vertical, .alignment = .top_leading, .children = try ctx.retainChildren(&children) } };
    }
};
pub fn main(init: std.process.Init) !void {
    var app: App = .{};
    const host = try g.Host(App).create(init.gpa, &app);
    defer host.destroy() catch unreachable;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const result = try g.tui.runAdaptive(host, init.io, args[1..]);
    if (!result.completion.succeeded()) return error.ApplicationFailed;
}
