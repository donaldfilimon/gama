const g = @import("gama");
const Spoof = struct {
    pub const Context = g.plugins.Context;
    pub const is_framework_handle = true;
    lease: *u64,
};
fn call(_: *const Spoof, _: *anyopaque) g.Error!void {}
test {
    var frame = g.FrameStorage.init(@import("std").testing.allocator);
    defer frame.deinit();
    var ctx = frame.context();
    var value: u64 = 0;
    _ = try ctx.action(Spoof{ .lease = &value }, call);
}
