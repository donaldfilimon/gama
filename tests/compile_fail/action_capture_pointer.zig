const std = @import("std");
const g = @import("gama");
fn callback(_: *const *u8, _: *anyopaque) g.Error!void {}
test {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var byte: u8 = 0;
    _ = try ctx.action(&byte, callback);
}
