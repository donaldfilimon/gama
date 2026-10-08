//! Run the pinned compiler's leak-checking runner, rejecting empty suites.
const std = @import("std");
const builtin = @import("builtin");
const default_runner = @import("default_runner");

pub const std_options = default_runner.std_options;

pub fn main(init: std.process.Init.Minimal) void {
    // The pinned compiler emits this slice as runtime data, not comptime data.
    if (builtin.test_functions.len == 0) {
        std.debug.print("zero-test suite\n", .{});
        std.process.exit(1);
    }
    default_runner.main(init);
}
