const std = @import("std");
const g = @import("gama");
test {
    var first: u8 = 1;
    var second: u8 = 2;
    const Value = struct { values: [1]?@Vector(2, ?*const u8) };
    const value: Value = .{ .values = .{.{ &first, &second }} };
    var bytes: [128]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&bytes);
    var frame = g.FrameStorage.init(fixed.allocator());
    defer frame.deinit();
    var ctx = frame.context();
    _ = try ctx.state(Value, 0, value);
}
