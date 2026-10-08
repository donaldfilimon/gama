const g = @import("gama");
test {
    var bytes: [128]u8 = undefined;
    var fixed = @import("std").heap.FixedBufferAllocator.init(&bytes);
    var frame = g.FrameStorage.init(fixed.allocator());
    defer frame.deinit();
    var ctx = frame.context();
    _ = try ctx.state([]const u8, 0, "borrowed");
}
