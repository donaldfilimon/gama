const std = @import("std");
const g = @import("gama");
const Capture = struct { nested: ?struct { bytes: []const u8 } };
fn callback(_: *const Capture, _: *anyopaque) g.Error!void {}
test {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    _ = try ctx.action(Capture{ .nested = .{ .bytes = "borrowed" } }, callback);
}
