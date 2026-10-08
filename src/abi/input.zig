//! Exact scalar/code translation. Storage is inline; obtain key only after the
//! Decoded value reaches its final address, and consume its borrow synchronously.
const std = @import("std");
const g = @import("../root.zig");
/// Validated pull-ABI key classification and its semantic payload.
pub const Decoded = struct {
    /// Discriminant selecting the semantic operation represented by this value.
    kind: enum {
        /// Use the decoded semantic key directly.
        semantic,
        /// Emit a character key borrowing the inline decoded bytes.
        character,
        /// Interpret the inline lowercase expansion as a control shortcut only when it is one scalar.
        control,
    },

    /// Semantic key value used when kind is semantic; otherwise ignored.
    semantic: g.Key = .escape,

    /// Inline UTF-8 storage for the decoded scalar or full lowercase expansion.
    bytes: [12]u8 = undefined,

    /// Initialized byte count in bytes; at most twelve.
    len: u8 = 0,
    /// Return the semantic key or a character slice borrowing this stable Decoded value.
    /// Return null for multi-scalar lowercase control expansions; never collapse dotted I to i.
    pub fn key(self: *const Decoded) ?g.Key {
        return switch (self.kind) {
            .semantic => self.semantic,
            .character => .{ .character = self.bytes[0..self.len] },
            .control => blk: {
                var it = (std.unicode.Utf8View.init(self.bytes[0..self.len]) catch unreachable).iterator();
                const cp = it.nextCodepoint().?;
                if (it.nextCodepoint() != null) break :blk null;
                break :blk .{ .shortcut = .{ .codepoint = cp, .control = true } };
            },
        };
    }
};
/// Translate integer ABI key/scalar/modifier input into inline Decoded storage without allocation.
/// Reject unknown codes and invalid character scalars; character key() borrows the value at its final address.
pub fn decode(code: i32, scalar: i32, shift: i32, control: i32) g.Error!Decoded {
    if (code == 0) {
        if (scalar < 0 or scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff)) return error.InvalidCharacter;
        const cp: u21 = @intCast(scalar);
        var result: Decoded = .{ .kind = .character };
        if (control != 0 and g.unicode.isAlphabetic(cp)) {
            result.kind = .control;
            const mapping = g.unicode.lowercaseMapping(cp);
            for (mapping.scalars[0..mapping.len]) |lower| {
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(lower, &buf) catch unreachable;
                @memcpy(result.bytes[result.len..][0..n], buf[0..n]);
                result.len += n;
            }
        } else {
            var buf: [4]u8 = undefined;
            result.len = std.unicode.utf8Encode(cp, &buf) catch unreachable;
            @memcpy(result.bytes[0..result.len], buf[0..result.len]);
        }
        return result;
    }
    return .{ .kind = .semantic, .semantic = switch (code) {
        1 => .up,
        2 => .down,
        3 => .left,
        4 => .right,
        5 => .enter,
        6 => .escape,
        7 => if (shift != 0) .back_tab else .tab,
        8 => .backspace,
        9 => .delete,
        10 => .home,
        11 => .end,
        12 => .page_up,
        13 => .page_down,
        100...112 => .{ .function = @intCast(code - 99) },
        else => return error.InvalidCharacter,
    } };
}
