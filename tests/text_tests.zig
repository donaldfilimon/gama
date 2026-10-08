//! Test package root permits direct consumption of untouched sibling parity fixtures.
comptime {
    _ = @import("unicode/text_tests.zig");
}
