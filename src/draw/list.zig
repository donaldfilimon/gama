//! GAMA v1. DrawList owns its commands and strings through an arena.
const std = @import("std");
const geo = @import("../core/geometry.zig");
const s = @import("../core/style.zig");
const unicode = @import("../core/unicode.zig");
const cells = @import("cells.zig");
const A = std.mem.Allocator;
/// Shared recoverable state, rendering, transport and allocation error set.
pub const Error = @import("../core/state.zig").Error;
/// Portable fill or text draw command; text bytes borrow the owning list/frame.
pub const Command = union(enum) {
    /// Paint a rectangle with the specified color.
    fill: struct {
        /// Rectangle to fill in cell coordinates.
        rect: geo.Rect,
        /// Color of this drawing or decoration operation.
        color: s.Color,
    },

    /// Paint UTF-8 text at a cell coordinate using a text style.
    text: struct {
        /// Starting cell coordinate of the text command.
        at: geo.Point,
        /// Text foreground/background colors and decoration bits.
        style: s.TextStyle,
        /// Borrowed UTF-8 bytes, owned by the list arena in constructed/decoded lists.
        value: []const u8,
    },
};
/// Owned ordered draw commands and copied text; release all storage with deinit.
pub const DrawList = struct {
    /// Arena owning command storage and text; release through DrawList.deinit.
    arena: std.heap.ArenaAllocator,

    /// Caller-supplied drawing extent, copied unchanged by init. Callers must supply nonnegative
    /// dimensions for valid wire output; decode rejects negative dimensions in incoming headers.
    size: geo.Size,

    /// Ordered drawing or plugin commands owned by the documented producing collection.
    commands: []const Command,

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *DrawList) void {
        self.arena.deinit();
        self.* = undefined;
    }
    /// Copy caller commands and all string storage.
    pub fn init(a: A, size: geo.Size, input: []const Command) Error!DrawList {
        var arena = std.heap.ArenaAllocator.init(a);
        errdefer arena.deinit();
        const alloc = arena.allocator();
        const commands = try alloc.dupe(Command, input);
        for (commands) |*cmd| if (cmd.* == .text) {
            _ = try unicode.Graphemes.init(cmd.text.value);
            cmd.text.value = try alloc.dupe(u8, cmd.text.value);
        };
        return .{ .arena = arena, .size = size, .commands = commands };
    }

    /// Copy visible styled runs into an owned DrawList without swapping planes.
    pub fn from(a: A, buffer: *const cells.CellBuffer) Error!DrawList {
        var arena = std.heap.ArenaAllocator.init(a);
        errdefer arena.deinit();
        const alloc = arena.allocator();
        var commands: std.ArrayList(Command) = .empty;
        var runs = buffer.runs();
        while (runs.next()) |run| {
            if (!run.style.background.is_default) try commands.append(alloc, .{ .fill = .{ .rect = .{ .origin = .{ .x = run.column, .y = run.row }, .size = .{ .width = run.width, .height = 1 } }, .color = run.style.background } });
            var joined: std.ArrayList(u8) = .empty;
            for (run.cells) |c| if (!c.continuation) {
                try joined.appendSlice(alloc, c.glyph);
            };
            var it = try unicode.Graphemes.init(joined.items);
            var first: ?usize = null;
            var last: usize = 0;
            var leading: i64 = 0;
            while (it.next()) |glyph| {
                if (!std.mem.eql(u8, glyph, " ")) {
                    if (first == null) first = it.offset - glyph.len;
                    last = it.offset;
                } else if (first == null) leading += 1;
            }
            if (first) |start| try commands.append(alloc, .{ .text = .{ .at = .{ .x = run.column + leading, .y = run.row }, .style = run.style, .value = joined.items[start..last] } });
        }
        return .{ .arena = arena, .size = buffer.size, .commands = try commands.toOwnedSlice(alloc) };
    }

    /// Allocate GAMA v1 bytes; the caller releases the returned slice with the supplied allocator.
    pub fn encode(self: *const DrawList, a: A) Error![]u8 {
        if (self.commands.len > std.math.maxInt(u32)) return error.CollectionTooLarge;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        try integer(&out, a, u32, 0x414d4147);
        try integer(&out, a, u32, 1);
        try signed(&out, a, self.size.width);
        try signed(&out, a, self.size.height);
        try integer(&out, a, u32, @intCast(self.commands.len));
        for (self.commands) |cmd| switch (cmd) {
            .fill => |v| {
                try out.append(a, 0);
                for ([_]i64{ v.rect.minX(), v.rect.minY(), v.rect.size.width, v.rect.size.height }) |n| try signed(&out, a, n);
                try color(&out, a, v.color);
            },
            .text => |v| {
                if (v.value.len > std.math.maxInt(u32)) return error.TextTooLarge;
                _ = try unicode.Graphemes.init(v.value);
                try out.append(a, 1);
                try signed(&out, a, v.at.x);
                try signed(&out, a, v.at.y);
                try color(&out, a, v.style.foreground);
                try color(&out, a, v.style.background);
                try integer(&out, a, u16, v.style.attributes);
                try integer(&out, a, u32, @intCast(v.value.len));
                try out.appendSlice(a, v.value);
            },
        };
        return out.toOwnedSlice(a);
    }
    /// Validate complete input before allocating. Strings/counts cannot exceed available bytes.
    /// Unknown flag bits are ignored, default RGB canonicalized, SGR truncated to its low byte.
    pub fn decode(a: A, bytes: []const u8) Error!DrawList {
        var validation: Reader = .{ .bytes = bytes };
        const header = try validation.header();
        for (0..header.count) |_| _ = try validation.command();
        if (validation.offset != bytes.len) return error.TrailingBytes;
        var arena = std.heap.ArenaAllocator.init(a);
        errdefer arena.deinit();
        const alloc = arena.allocator();
        const commands = try alloc.alloc(Command, header.count);
        var reader: Reader = .{ .bytes = bytes, .offset = 20 };
        for (commands) |*cmd| {
            cmd.* = try reader.command();
            if (cmd.* == .text) cmd.text.value = try alloc.dupe(u8, cmd.text.value);
        }
        return .{ .arena = arena, .size = header.size, .commands = commands };
    }
};
/// Non-mutating serializer producing an owned DrawList; encode separately for wire bytes.
pub const DrawListSerializer = struct {
    /// Copy back-plane draw commands and text into an owned DrawList; release via DrawList.deinit.
    pub fn serialize(a: A, buffer: *const cells.CellBuffer) Error!DrawList {
        return DrawList.from(a, buffer);
    }
};
fn integer(out: *std.ArrayList(u8), a: A, comptime T: type, value: T) Error!void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    try out.appendSlice(a, &bytes);
}
fn signed(out: *std.ArrayList(u8), a: A, value: i64) Error!void {
    try integer(out, a, i32, @intCast(std.math.clamp(value, std.math.minInt(i32), std.math.maxInt(i32))));
}
fn color(out: *std.ArrayList(u8), a: A, value: s.Color) Error!void {
    try out.appendSlice(a, &.{ value.r, value.g, value.b, @intFromBool(value.is_default) });
}
const Reader = struct {
    /// Borrowed wire bytes, kept unchanged while the reader advances.
    bytes: []const u8,

    /// Next unread byte offset, advanced only after bounds checks.
    offset: usize = 0,
    fn read(self: *Reader, comptime T: type) Error!T {
        if (self.bytes.len - self.offset < @sizeOf(T)) return error.Truncated;
        const value = std.mem.readInt(T, self.bytes[self.offset..][0..@sizeOf(T)], .little);
        self.offset += @sizeOf(T);
        return value;
    }
    fn colorValue(self: *Reader) Error!s.Color {
        const r = try self.read(u8);
        const g = try self.read(u8);
        const b = try self.read(u8);
        const flags = try self.read(u8);
        return if (flags & 1 != 0) .default else .init(r, g, b);
    }
    fn header(self: *Reader) Error!struct {
        /// Nonnegative dimensions decoded from the wire header.
        size: geo.Size,
        /// Number of encoded commands, checked against available minimum command bytes.
        count: usize,
    } {
        if (try self.read(u32) != 0x414d4147) return error.BadMagic;
        if (try self.read(u32) != 1) return error.UnsupportedVersion;
        const w = try self.read(i32);
        const h = try self.read(i32);
        const n = try self.read(u32);
        if (w < 0 or h < 0) return error.NegativeDimensions;
        if (n > (self.bytes.len - 20) / 17) return error.CommandCountOverflow;
        return .{ .size = .{ .width = w, .height = h }, .count = @intCast(n) };
    }
    fn command(self: *Reader) Error!Command {
        switch (try self.read(u8)) {
            0 => {
                const x = try self.read(i32);
                const y = try self.read(i32);
                const w = try self.read(i32);
                const h = try self.read(i32);
                const c = try self.colorValue();
                if (w < 0 or h < 0) return error.NegativeRect;
                return .{ .fill = .{ .rect = .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } }, .color = c } };
            },
            1 => {
                const x = try self.read(i32);
                const y = try self.read(i32);
                const fg = try self.colorValue();
                const bg = try self.colorValue();
                const attrs = try self.read(u16);
                const n = try self.read(u32);
                if (n > self.bytes.len - self.offset) return error.Truncated;
                const value = self.bytes[self.offset..][0..@intCast(n)];
                if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
                self.offset += @intCast(n);
                return .{ .text = .{ .at = .{ .x = x, .y = y }, .style = .{ .foreground = fg, .background = bg, .attributes = @truncate(attrs) }, .value = value } };
            },
            else => return error.UnknownCommandKind,
        }
    }
};
