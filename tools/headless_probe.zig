const std = @import("std");
const g = @import("gama");
const App = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
        return .{ .text = .{ .content = "headless" } };
    }
};
export fn gama_headless_probe(bytes: [*]u8, len: usize) i32 {
    var fba = std.heap.FixedBufferAllocator.init(bytes[0..len]);
    var app: App = .{};
    const host = g.Host(App).create(fba.allocator(), &app) catch return -1;
    defer host.destroy() catch unreachable;
    var surface = g.tui.Surface.init(std.Io.failing, .plain);
    _ = g.tui.run(host, &surface) catch return -2;
    return 0;
}
export fn gama_terminal_probe() i32 {
    if (@import("builtin").os.tag == .windows) return -3;
    var terminal = g.tui.Terminal.acquire(std.Io.failing, 0, 1) catch return -1;
    defer terminal.close() catch {};
    _ = terminal.size() catch return -2;
    terminal.write("probe") catch return -2;
    _ = terminal.next(0) catch return -2;
    return 0;
}
