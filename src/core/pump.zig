//! Borrowed single-step driver. A produced follow-up never drains internally, so
//! adapters can poll input between frames. The host outlives this non-owning value.
const host_module = @import("host.zig");
const Error = @import("state.zig").Error;
/// Result of one pump attempt: whether it published and whether another frame is needed.
pub const Outcome = struct {
    /// True when this step published a new frame.
    produced: bool = false,
    /// True when another frame remains dirty; adapters should poll input between frames.
    follow_up: bool = false,
};
/// Specialize a copyable non-owning step driver; the borrowed host must outlive every copy.
pub fn Implementation(comptime Host: type) type {
    return struct {
        /// Borrowed host pointer; keep the host alive until this value is released.
        host: *Host,
        const Self = @This();

        /// Dispatch a semantic event through the current published registrations.
        pub fn handle(self: Self, event: host_module.Event) Error!void {
            try self.host.handle(event);
        }
        /// Build, lay out, prepare downstream bytes, then publish atomically.
        /// Callback failures reclaim candidate resources and retain the old publication.
        pub fn advance(self: Self, context: anytype, comptime callback: fn (@TypeOf(context), Host.Preparation) Error![]const u8) Error!Outcome {
            const size = try self.host.currentSize();
            const candidate = (try self.host.prepare(size)) orelse return .{};
            try candidate.finish(context, callback);
            return .{ .produced = true, .follow_up = try self.host.needsFrame() };
        }
    };
}
