//! The sole hosted executor dependency. Native owners must die before their thread exits.
const std = @import("std");
const builtin = @import("builtin");
const Error = @import("../core/state.zig").Error;
/// Native thread-affinity guard capturing the creating thread ID.
pub const NativeGuard = struct {
    /// Creating native thread ID; check compares it with the current thread.
    id: std.Thread.Id,

    /// Capture the current thread without allocation; later checks reject another thread.
    pub fn init() NativeGuard {
        if (builtin.single_threaded) @compileError("host.native-requires-multithreaded-build");
        return .{ .id = std.Thread.getCurrentId() };
    }

    /// Return WrongThread unless called on the captured creating thread; does not extend owner lifetime.
    pub fn check(self: *const NativeGuard) Error!void {
        if (std.Thread.getCurrentId() != self.id) return error.WrongThread;
    }
};
