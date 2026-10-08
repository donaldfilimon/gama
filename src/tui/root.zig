const std = @import("std");
/// Bounded incremental UTF-8/escape decoder; emitted text borrows decoder storage.
pub const Decoder = @import("decoder.zig").Decoder;
/// Output strategy selected by explicit flags or stdout terminal detection.
pub const Mode = enum {
    /// Noninteractive newline text; stops at quiescence unless completion declares more work.
    plain,
    /// Interactive terminal acquisition, ANSI rendering and input dispatch.
    interactive,
};
/// Fallback plain/headless extent of 80 columns by 24 rows.
pub const default_size: @import("../core/geometry.zig").Size = .{ .width = 80, .height = 24 };
/// Detect stdout separately; arguments are applied left to right, last override wins.
pub fn select(stdout_is_terminal: bool, args: []const []const u8) Mode {
    var mode: Mode = if (stdout_is_terminal) .interactive else .plain;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--gama-plain")) mode = .plain;
        if (std.mem.eql(u8, arg, "--gama-tui")) mode = .interactive;
    }
    return mode;
}

/// Exclusive terminal owner on supported targets; void on Windows.
pub const Terminal = if (@import("builtin").os.tag == .windows) void else @import("terminal.zig").Terminal;
/// Hosted stdout/stdin adapter; begin/end manage optional terminal acquisition.
pub const Surface = @import("runtime.zig").Surface;
/// Run-loop completion value plus an explicit-completion indicator.
pub const Result = @import("runtime.zig").Result;
/// Run a caller-supplied host and surface through lifecycle, input and frame delivery.
pub const run = @import("runtime.zig").run;
/// Run a borrowed host using a stdout/argument-selected terminal or plain surface.
pub const runAdaptive = @import("runtime.zig").runAdaptive;
