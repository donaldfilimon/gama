const g = @import("gama");
const Capture = struct { command: g.plugins.Command, bytes: []const u8 };
fn call(_: *const Capture, _: *anyopaque) g.Error!void {}
test {
    var frame = g.FrameStorage.init(@import("std").testing.allocator);
    defer frame.deinit();
    var ctx = frame.context();
    _ = try ctx.action(Capture{ .command = undefined, .bytes = "temporary" }, call);
}
