const std = @import("std");
const g = @import("gama");
test {
    var first: u8 = 1;
    var second: u8 = 2;
    const Value = @Vector(2, ?*const u8);
    const value: Value = .{ &first, &second };
    const signal = try g.Signal(Value).create(std.testing.allocator, value);
    defer signal.destroy() catch unreachable;
    _ = try signal.read();
}
