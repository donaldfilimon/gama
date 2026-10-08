const g = @import("gama");
const Spoof = struct {
    pub const Value = i64;
    pub const is_framework_handle = true;
    pointer: *i64,
};
fn callback(_: *const Spoof, _: *anyopaque) g.Error!void {}
test {
    var bytes: [128]u8 = undefined;
    var fixed = @import("std").heap.FixedBufferAllocator.init(&bytes);
    var frame = g.FrameStorage.init(fixed.allocator());
    defer frame.deinit();
    var ctx = frame.context();
    var value: i64 = 0;
    _ = try ctx.action(Spoof{ .pointer = &value }, callback);
}
