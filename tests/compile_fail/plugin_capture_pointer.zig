const g = @import("gama");
const Capture = struct { context: g.plugins.Context, pointer: *u64 };
fn call(_: *const Capture, _: *anyopaque) g.Error!void {}
test {
    var frame = g.FrameStorage.init(@import("std").testing.allocator);
    defer frame.deinit();
    var ctx = frame.context();
    var value: u64 = 0;
    _ = try ctx.action(Capture{ .context = undefined, .pointer = &value }, call);
}
