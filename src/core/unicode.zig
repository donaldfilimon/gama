//! Unicode17 UAX29 extended graphemes. Every public UTF8 entry rejects malformed
//! input before yielding data. Iterators borrow immutable input; no allocation.
const std = @import("std");
const tables = @import("unicode/tables.zig");
/// Unicode data version used for grapheme, alphabetic and lowercase tables.
pub const version = "17.0.0";
/// Validation failure shared by UTF-8 and grapheme helpers.
pub const Error = error{
    /// Input bytes are not a valid UTF-8 sequence.
    InvalidUtf8,
};
const Gcb = enum(u8) {
    /// Grapheme-break class without a specialized joining rule.
    other,
    /// Carriage return; joins a following line feed.
    cr,
    /// Line feed; breaks except after carriage return.
    lf,
    /// Control class forcing a grapheme boundary.
    control,
    /// Extending mark joined to the preceding grapheme.
    extend,
    /// Zero-width joiner used by the emoji sequence rule.
    zwj,
    /// Regional indicator paired according to preceding run parity.
    regional_indicator,
    /// Prepending character joined to the following grapheme.
    prepend,
    /// Spacing combining mark joined to its predecessor.
    spacing_mark,
    /// Hangul leading consonant class.
    l,
    /// Hangul vowel class.
    v,
    /// Hangul trailing consonant class.
    t,
    /// Hangul leading-vowel syllable class.
    lv,
    /// Hangul leading-vowel-trailing syllable class.
    lvt,
};
const Incb = enum(u8) {
    /// No Indic-conjunct participation; clears conjunct state.
    none,
    /// Indic consonant starting or completing a conjunct.
    consonant,
    /// Indic extending character preserving conjunct state.
    extend,
    /// Indic linker permitting the following consonant to join.
    linker,
};
fn property(cp: u21, ranges: []const tables.Range) u8 {
    var lo: usize = 0;
    var hi = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = ranges[mid];
        if (cp < r.lo) hi = mid else if (cp > r.hi) lo = mid + 1 else return r.value;
    }
    return 0;
}
fn gcb(cp: u21) Gcb {
    return @fromBackingInt(@intCast(property(cp, &tables.gcb)));
}
fn incb(cp: u21) Incb {
    return @fromBackingInt(@intCast(property(cp, &tables.incb)));
}
fn pictographic(cp: u21) bool {
    return property(cp, &tables.pictographic) != 0;
}
/// Validate UTF-8 bytes without allocation; return InvalidUtf8 for malformed encoding.
pub fn validate(bytes: []const u8) Error!void {
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
}
const Scalar = struct {
    /// Decoded Unicode scalar from previously validated input.
    cp: u21,
    /// Exclusive byte offset immediately after the decoded scalar.
    end: usize,
};
// Only called after whole-input validation.
fn scalarAt(bytes: []const u8, offset: usize) Scalar {
    const length = std.unicode.utf8ByteSequenceLength(bytes[offset]) catch unreachable;
    const end = offset + length;
    return .{ .cp = std.unicode.utf8Decode(bytes[offset..end]) catch unreachable, .end = end };
}
const State = struct {
    /// Grapheme-break class of the last consumed scalar.
    previous: Gcb,

    /// True when the current regional-indicator run has odd length.
    ri_odd: bool = false,

    /// An extended pictograph followed only by extending marks has been seen.
    ep_extend: bool = false,

    /// The last ZWJ follows an extended-pictograph/extend sequence.
    zwj_from_ep: bool = false,

    /// An Indic consonant has started the current conjunct candidate.
    indic_consonant: bool = false,

    /// An Indic linker has occurred after the remembered consonant.
    indic_linker: bool = false,
    fn consume(self: *State, cp: u21) void {
        const prop = gcb(cp);
        self.ri_odd = if (prop == .regional_indicator) !self.ri_odd else false;
        self.zwj_from_ep = prop == .zwj and self.ep_extend;
        self.ep_extend = pictographic(cp) or (prop == .extend and self.ep_extend);
        switch (incb(cp)) {
            .consonant => {
                self.indic_consonant = true;
                self.indic_linker = false;
            },
            .linker => {
                if (self.indic_consonant) self.indic_linker = true;
            },
            .extend => {},
            .none => {
                self.indic_consonant = false;
                self.indic_linker = false;
            },
        }
        self.previous = prop;
    }
    fn breaks(self: State, cp: u21) bool {
        const a = self.previous;
        const b = gcb(cp);
        if (a == .cr and b == .lf) return false; // GB3
        if (a == .control or a == .cr or a == .lf or b == .control or b == .cr or b == .lf) return true; // GB4/5
        if (a == .l and (b == .l or b == .v or b == .lv or b == .lvt)) return false;
        if ((a == .lv or a == .v) and (b == .v or b == .t)) return false;
        if ((a == .lvt or a == .t) and b == .t) return false;
        if (b == .extend or b == .zwj or b == .spacing_mark or a == .prepend) return false;
        if (incb(cp) == .consonant and self.indic_consonant and self.indic_linker) return false; // GB9c
        if (pictographic(cp) and a == .zwj and self.zwj_from_ep) return false; // GB11
        if (a == .regional_indicator and b == .regional_indicator and self.ri_odd) return false;
        return true;
    }
};
/// Allocation-free iterator borrowing validated UTF-8; yielded slices borrow that input.
pub const Graphemes = struct {
    /// Borrowed validated UTF-8 input; keep it unchanged while iterating or using yielded slices.
    bytes: []const u8,

    /// Exclusive byte offset of the previous grapheme; iterator-owned cursor.
    offset: usize = 0,

    /// Validate UTF-8 and borrow bytes at offset zero; returns InvalidUtf8 without allocation.
    pub fn init(bytes: []const u8) Error!Graphemes {
        try validate(bytes);
        return .{ .bytes = bytes };
    }

    /// Return the next borrowed extended grapheme and advance offset; null only at end of input.
    pub fn next(self: *Graphemes) ?[]const u8 {
        if (self.offset == self.bytes.len) return null;
        const start = self.offset;
        var state: State = .{ .previous = .other };
        const first = scalarAt(self.bytes, start);
        state.consume(first.cp);
        self.offset = first.end;
        while (self.offset < self.bytes.len) {
            const scalar = scalarAt(self.bytes, self.offset);
            if (state.breaks(scalar.cp)) break;
            state.consume(scalar.cp);
            self.offset = scalar.end;
        }
        return self.bytes[start..self.offset];
    }
};
/// Count extended grapheme clusters after validating UTF-8.
pub fn count(bytes: []const u8) Error!usize {
    var it = try Graphemes.init(bytes);
    var n: usize = 0;
    while (it.next() != null) n += 1;
    return n;
}
/// Swift Character.isLetter: first scalar's Alphabetic, using qualified baseline data.
pub fn isLetter(character: []const u8) Error!bool {
    var it = try Graphemes.init(character);
    if (it.next() == null or it.next() != null) return false;
    return isAlphabetic(scalarAt(character, 0).cp);
}
/// Classify a scalar with the pinned Unicode Alphabetic property.
pub fn isAlphabetic(cp: u21) bool {
    return property(cp, &tables.alphabetic) != 0;
}
/// Default lowercase expansion of one scalar; only scalars[0..len] is meaningful.
pub const LowercaseMapping = struct {
    /// Up to three mapped scalars; trailing slots outside len are not output.
    scalars: [3]u21,
    /// Number of mapped scalars in the meaningful prefix, between one and three.
    len: u8,
};
/// Unconditional scalar lowercase, including multi-scalar mappings; no contextual sigma.
pub fn lowercaseMapping(cp: u21) LowercaseMapping {
    var lo: usize = 0;
    var hi = tables.lowercase.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = tables.lowercase[mid];
        if (cp < r.cp) hi = mid else if (cp > r.cp) lo = mid + 1 else return .{ .scalars = r.scalars, .len = r.len };
    }
    return .{ .scalars = .{ cp, 0, 0 }, .len = 1 };
}
/// Caller owns returned UTF8. Whole-input validation precedes allocation; OOM leaves input intact.
pub fn lowercased(allocator: std.mem.Allocator, bytes: []const u8) (Error || std.mem.Allocator.Error)![]u8 {
    try validate(bytes);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var offset: usize = 0;
    while (offset < bytes.len) {
        const scalar = scalarAt(bytes, offset);
        offset = scalar.end;
        const mapping = lowercaseMapping(scalar.cp);
        for (mapping.scalars[0..mapping.len]) |cp| {
            var buffer: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cp, &buffer) catch unreachable;
            try out.appendSlice(allocator, buffer[0..n]);
        }
    }
    return out.toOwnedSlice(allocator);
}
