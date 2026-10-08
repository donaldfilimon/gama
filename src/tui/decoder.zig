//! Bounded scalar decoder. Events borrow scalar scratch until the next call.
//! Completed unknown sequences are consumed; unfinished sequences are discarded
//! at 256 bytes or 250 ms. A lone ESC retains the baseline 25 ms grace.
const std = @import("std");
const Event = @import("../core/host.zig").Event;
const Key = @import("../core/input.zig").Key;
/// Bounded incremental UTF-8/escape decoder; event slices borrow its internal buffers.
pub const Decoder = struct {
    /// Maximum pending escape-sequence bytes before deterministic rejection/recovery.
    pub const capacity = 256;

    /// Inline pending input buffer, compacted as complete events are decoded.
    bytes: [capacity]u8 = undefined,

    /// Number of initialized pending bytes; feed rejects input beyond capacity.
    len: usize = 0,

    /// Timestamp when the pending escape sequence began, used for timeout disambiguation.
    started: ?u64 = null,

    /// Storage for the currently emitted UTF-8 scalar; reused by the next decoded event.
    scalar: [4]u8 = undefined,

    /// Append bounded raw input bytes without dropping incomplete escape/UTF-8 sequences.
    pub fn feed(self: *Decoder, input: []const u8) error{
        /// Incoming bytes exceed the decoder's remaining fixed buffer capacity.
        InputFull,
    }!void {
        if (input.len > capacity - self.len) return error.InputFull;
        @memcpy(self.bytes[self.len..][0..input.len], input);
        self.len += input.len;
    }
    fn consume(self: *Decoder, count: usize) void {
        std.mem.copyForwards(u8, &self.bytes, self.bytes[count..self.len]);
        self.len -= count;
        self.started = null;
    }
    fn incomplete(self: *Decoder, now: u64) ?Event {
        const start = self.started orelse now;
        self.started = start;
        const lone = self.len == 1 and self.bytes[0] == 27;
        if (self.len == capacity or now -| start >= (if (lone) @as(u64, 25) else 250)) {
            self.consume(self.len);
            if (lone) return .{ .key = .escape };
        }
        return null;
    }

    /// Decode one event using now (milliseconds) for escape timeout; character bytes borrow scalar scratch.
    /// Null means no event, including empty/incomplete input or discarded malformed/unsupported input;
    /// additional bytes may remain buffered. Consume a character borrow before the next call.
    pub fn next(self: *Decoder, now: u64) ?Event {
        if (self.len == 0) return null;
        const first = self.bytes[0];
        if (first == 27) {
            if (self.len == 1) return self.incomplete(now);
            if (self.bytes[1] == 'O') {
                if (self.len < 3) return self.incomplete(now);
                const f = self.bytes[2];
                self.consume(3);
                return if (f >= 'P' and f <= 'S') .{ .key = .{ .function = f - 'P' + 1 } } else null;
            }
            if (self.bytes[1] != '[') {
                self.consume(1);
                return .{ .key = .escape };
            }
            var end: usize = 2;
            while (end < self.len and (self.bytes[end] < 0x40 or self.bytes[end] > 0x7e)) : (end += 1) {}
            if (end == self.len) return self.incomplete(now);
            const event = csi(self.bytes[2..end], self.bytes[end]);
            self.consume(end + 1);
            return event;
        }
        const key: ?Key = switch (first) {
            13, 10 => .enter,
            9 => .tab,
            127, 8 => .backspace,
            1...7, 11...12, 14...26 => .{ .shortcut = .{ .codepoint = 'a' + first - 1, .control = true } },
            else => null,
        };
        if (key) |k| {
            self.consume(1);
            return .{ .key = k };
        }
        const n = std.unicode.utf8ByteSequenceLength(first) catch {
            self.consume(1);
            return null;
        };
        if (self.len < n) return self.incomplete(now);
        _ = std.unicode.utf8Decode(self.bytes[0..n]) catch {
            self.consume(1);
            return null;
        };
        @memcpy(self.scalar[0..n], self.bytes[0..n]);
        self.consume(n);
        return .{ .key = .{ .character = self.scalar[0..n] } };
    }
    fn csi(params: []const u8, final: u8) ?Event {
        if ((final == 'M' or final == 'm') and std.mem.startsWith(u8, params, "<")) {
            var fields = std.mem.tokenizeScalar(u8, params[1..], ';');
            _ = fields.next() orelse return null; // Baseline deliberately ignores button field.
            const x = std.fmt.parseInt(i64, fields.next() orelse return null, 10) catch return null;
            const y = std.fmt.parseInt(i64, fields.next() orelse return null, 10) catch return null;
            if (fields.next() != null or x == std.math.minInt(i64) or y == std.math.minInt(i64)) return null;
            return if (final == 'M') .{ .pointer = .{ .x = x - 1, .y = y - 1 } } else .pointer_release;
        }
        const k: Key = switch (final) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            'H' => .home,
            'F' => .end,
            'Z' => .back_tab,
            '~' => blk: {
                const n = std.fmt.parseInt(u8, params, 10) catch return null;
                break :blk switch (n) {
                    1, 7 => .home,
                    3 => .delete,
                    4, 8 => .end,
                    5 => .page_up,
                    6 => .page_down,
                    11...15 => .{ .function = n - 10 },
                    17...21 => .{ .function = n - 11 },
                    23...24 => .{ .function = n - 12 },
                    else => return null,
                };
            },
            else => return null,
        };
        return .{ .key = k };
    }
};
