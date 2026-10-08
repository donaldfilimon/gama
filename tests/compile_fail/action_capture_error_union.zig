const std = @import("std");
const g = @import("gama");
const Capture = error{Missing}![]const u8;
fn callback(_: *const Capture, _: *anyopaque) g.Error!void {}
test {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    _ = try ctx.action(@as(Capture, "borrowed"), callback);
}
