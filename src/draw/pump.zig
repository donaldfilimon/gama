//! Transactional draw adapter. No external output occurs in the guarded callback.
//! A candidate raster owns its glyphs independently from Host arenas. Only after
//! Host staging has copied bytes and delivery has succeeded do we replace planes.
//! advance publishes to memory; advanceDelivered additionally requires the caller
//! transport to accept all bytes before host publication and raster promotion.
const std = @import("std");
const cells = @import("cells.zig");
const paint = @import("painter.zig").paint;
const list = @import("list.zig");
const Error = @import("../core/state.zig").Error;
const geo = @import("../core/geometry.zig");
/// Output representation prepared transactionally before frame publication.
pub const Format = enum {
    /// Versioned binary DrawList wire bytes.
    draw_list,
    /// Escaped HTML serialization of the cell plane.
    html,
    /// ANSI terminal diff relative to the last published front plane.
    ansi,
    /// Newline-delimited plain text, optionally supplied as semantic lines.
    plain,
};
/// Stable borrowed pointer, like Host. Do not copy an owning initialized adapter.
pub fn Implementation(comptime Host: type, comptime Pump: type) type {
    return struct {
        const Self = @This();

        /// Owned last-published cell buffer; replaced only after successful delivery.
        buffer: cells.CellBuffer,

        /// Selected serialization/presentation format; serializers do not implicitly swap planes.
        format: Format,

        /// Borrowed host pointer; keep the host alive until this value is released.
        host: *Host,

        /// Allocate an empty drawing buffer and borrow host; deinit the pump before destroying host.
        pub fn init(a: std.mem.Allocator, host: *Host, format: Format) Error!Self {
            return .{ .buffer = try .init(a, .{}), .format = format, .host = host };
        }

        /// Release owned storage exactly once; all borrows into this value become invalid.
        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
            self.* = undefined;
        }

        /// Advance at most one dirty frame; a clean poll produces no output.
        pub fn advance(self: *Self) Error!@import("../core/pump.zig").Outcome {
            return self.advanceDelivered({}, memoryOnly, &.{});
        }
        fn memoryOnly(_: void, _: []const u8) Error!void {}
        /// All allocation, including Host's final output copy, precedes transport.
        /// Failed transport retains old planes/registrations and dirty retry.
        pub fn advanceDelivered(self: *Self, context: anytype, comptime transport: fn (@TypeOf(context), []const u8) Error!void, semantic_lines: []const []const u8) Error!@import("../core/pump.zig").Outcome {
            _ = Pump;
            return self.advanceWithPolicy(context, transport, semantic_lines, false);
        }
        /// C embedding retains baseline layout extent while normalizing oversized
        /// raster storage to zero. Encoded-length admission still precedes publication.
        pub fn advanceNormalized(self: *Self, context: anytype, comptime transport: fn (@TypeOf(context), []const u8) Error!void) Error!@import("../core/pump.zig").Outcome {
            return self.advanceWithPolicy(context, transport, &.{}, true);
        }
        fn advanceWithPolicy(self: *Self, context: anytype, comptime transport: fn (@TypeOf(context), []const u8) Error!void, semantic_lines: []const []const u8, normalize: bool) Error!@import("../core/pump.zig").Outcome {
            const size = try self.host.currentSize();
            if (!normalize and !std.meta.eql(size, cells.normalized(size))) return error.FrameTooLarge;
            const candidate = (try self.host.prepare(size)) orelse return .{};
            var pending: Pending = .{ .owner = self, .size = size, .lines = semantic_lines };
            defer if (pending.buffer) |*buffer| buffer.deinit();
            try candidate.stage(&pending, Pending.prepare);
            try candidate.deliver(context, transport);
            var next = pending.buffer.?;
            pending.buffer = null;
            if (self.format == .ansi or self.format == .plain) next.promote();
            self.buffer.deinit();
            self.buffer = next;
            return .{ .produced = true, .follow_up = try self.host.needsFrame() };
        }
        const Pending = struct {
            /// Borrowed owner pointer; this value must never outlive that owner.
            owner: *Self,

            /// Requested frame extent used when allocating the candidate cell buffer.
            size: geo.Size,

            /// Owned staging buffer released on failure or moved into the drawing pump on success.
            buffer: ?cells.CellBuffer = null,

            /// Borrowed semantic lines for this preparation call; empty selects painted cell text.
            lines: []const []const u8 = &.{},
            fn prepare(self: *@This(), frame: Host.Preparation) Error![]const u8 {
                self.buffer = try self.owner.buffer.candidate(self.owner.buffer.allocator, self.size);
                const b = &self.buffer.?;
                try paint(b, frame.tree.*);
                const a = frame.allocator;
                return switch (self.owner.format) {
                    .draw_list => blk: {
                        var commands = try list.DrawList.from(a, b);
                        defer commands.deinit();
                        break :blk try commands.encode(a);
                    },
                    .html => @import("html.zig").HTMLSerializer.serialize(a, b),
                    .ansi => @import("presenters.zig").AnsiPresenter.prepare(a, b),
                    .plain => blk: {
                        var lines = try @import("presenters.zig").StreamPresenter.prepare(a, b);
                        defer lines.deinit(a);
                        var out: std.ArrayList(u8) = .empty;
                        // Adapter framing: each chronology record receives one LF.
                        for (if (self.lines.len != 0) self.lines else lines.items) |line| {
                            try out.appendSlice(a, line);
                            try out.append(a, '\n');
                        }
                        break :blk try out.toOwnedSlice(a);
                    },
                };
            }
        };
    };
}
