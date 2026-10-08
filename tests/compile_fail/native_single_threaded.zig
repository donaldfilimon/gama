const g = @import("gama");
const App = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
        return .empty;
    }
};
test {
    var app: App = .{};
    const host = try g.Host(App).create(@import("std").testing.allocator, &app);
    try host.destroy();
}
