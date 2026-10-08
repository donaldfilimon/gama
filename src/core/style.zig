//! Portable colors retain an independent inherited/default bit.
const text = @import("text.zig");
/// Copyable RGB value with an independent terminal-default flag.
pub const Color = struct {
    /// Red channel, 0 through 255; ignored when is_default is true.
    r: u8 = 0,

    /// Green channel, 0 through 255; ignored when is_default is true.
    g: u8 = 0,

    /// Blue channel, 0 through 255; ignored when is_default is true.
    b: u8 = 0,

    /// Select the inherited/terminal default instead of the stored RGB channels.
    is_default: bool = true,

    /// Construct an explicit RGB color, setting is_default to false; no allocation.
    pub fn init(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .is_default = false };
    }

    /// Inherited/terminal-default color; stored zero channels are not explicit black.
    pub const default: Color = .{};

    /// Explicit RGB (0, 0, 0).
    pub const black = init(0, 0, 0);

    /// Explicit RGB (255, 255, 255).
    pub const white = init(255, 255, 255);

    /// Explicit RGB (224, 64, 64).
    pub const red = init(224, 64, 64);

    /// Explicit RGB (64, 200, 100).
    pub const green = init(64, 200, 100);

    /// Explicit RGB (80, 128, 255).
    pub const blue = init(80, 128, 255);

    /// Explicit RGB (232, 200, 72).
    pub const yellow = init(232, 200, 72);

    /// Explicit RGB (72, 208, 208).
    pub const cyan = init(72, 208, 208);

    /// Explicit RGB (208, 96, 208).
    pub const magenta = init(208, 96, 208);

    /// Explicit RGB (128, 128, 128).
    pub const gray = init(128, 128, 128);

    /// Map RGB values to the retained xterm-256 palette index.
    pub fn xterm256(self: Color) u8 {
        if (self.is_default) return 0;
        if (self.r == self.g and self.g == self.b) {
            if (self.r < 8) return 16;
            if (self.r > 248) return 231;
            return @intCast(232 + ((@as(u16, self.r) - 8) * 24) / 247);
        }
        return 16 + 36 * cube(self.r) + 6 * cube(self.g) + cube(self.b);
    }
    fn cube(v: u8) u8 {
        return if (v < 48) 0 else if (v < 114) 1 else (v - 35) / 40;
    }
};
/// Bit masks combined in TextStyle.attributes.
pub const Attributes = struct {
    /// Bold/intense text attribute mask.
    pub const bold: u8 = 1;

    /// Dim/faint text attribute mask.
    pub const dim: u8 = 2;

    /// Italic text attribute mask.
    pub const italic: u8 = 4;

    /// Underline text attribute mask.
    pub const underline: u8 = 8;

    /// Reverse foreground/background attribute mask.
    pub const inverse: u8 = 16;

    /// Struck-through text attribute mask.
    pub const strikethrough: u8 = 32;
};
/// Copyable foreground/background colors and additive decoration bits.
pub const TextStyle = struct {
    /// Foreground color; default delegates to the terminal or surrounding style.
    foreground: Color = .default,

    /// Background color; default leaves the underlying presentation unchanged.
    background: Color = .default,

    /// Bitset of supported text decorations.
    attributes: u8 = 0,

    /// Inherited colors with no decoration bits set.
    pub const plain: TextStyle = .{};

    /// Merge explicitly supplied colors and combine attribute bits.
    pub fn merging(self: TextStyle, other: TextStyle) TextStyle {
        return .{ .foreground = if (other.foreground.is_default) self.foreground else other.foreground, .background = if (other.background.is_default) self.background else other.background, .attributes = self.attributes | other.attributes };
    }
};
/// Parse a compile-time RGB literal and reject malformed/out-of-range input.
pub fn rgb(comptime literal: []const u8) Color {
    return comptime parseRgb(literal);
}
fn parseRgb(comptime literal: []const u8) Color {
    const s = if (literal.len > 0 and literal[0] == '#') literal[1..] else literal;
    if (s.len != 3 and s.len != 6) @compileError("rgb.malformed");
    var digits: [6]u8 = undefined;
    for (s, 0..) |c, i| digits[i] = switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => @compileError("rgb.malformed"),
    };
    return if (s.len == 3) Color.init(digits[0] * 17, digits[1] * 17, digits[2] * 17) else Color.init(digits[0] * 16 + digits[1], digits[2] * 16 + digits[3], digits[4] * 16 + digits[5]);
}
/// Borrowed UTF-8 glyphs for the eight border positions; no owned allocation.
pub const BorderGlyphs = struct {
    /// Upper-left corner glyph.
    top_left: []const u8,
    /// Horizontal glyph repeated along the top edge.
    top: []const u8,
    /// Upper-right corner glyph.
    top_right: []const u8,
    /// Vertical glyph repeated along the left edge.
    left: []const u8,
    /// Vertical glyph repeated along the right edge.
    right: []const u8,
    /// Lower-left corner glyph.
    bottom_left: []const u8,
    /// Horizontal glyph repeated along the bottom edge.
    bottom: []const u8,
    /// Lower-right corner glyph.
    bottom_right: []const u8,
};
/// Select a built-in border glyph set; glyphs returns static borrowed strings.
pub const BorderStyle = enum {
    /// Single-line Unicode box drawing.
    single,

    /// Double-line Unicode box drawing.
    double,

    /// Single-line edges with rounded Unicode corners.
    rounded,

    /// Heavy Unicode box drawing.
    heavy,

    /// ASCII plus, hyphen and vertical-bar border.
    ascii,

    /// Return the box-drawing glyph set for this border style.
    pub fn glyphs(self: BorderStyle) BorderGlyphs {
        const row: [8][]const u8 = switch (self) {
            .single => .{ "┌", "─", "┐", "│", "│", "└", "─", "┘" },
            .double => .{ "╔", "═", "╗", "║", "║", "╚", "═", "╝" },
            .rounded => .{ "╭", "─", "╮", "│", "│", "╰", "─", "╯" },
            .heavy => .{ "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" },
            .ascii => .{ "+", "-", "+", "|", "|", "+", "-", "+" },
        };
        return .{ .top_left = row[0], .top = row[1], .top_right = row[2], .left = row[3], .right = row[4], .bottom_left = row[5], .bottom = row[6], .bottom_right = row[7] };
    }
};
/// Measure the padded border title using the shared grapheme width policy.
pub fn borderTitleWidth(title: ?[]const u8) error{
    /// Input bytes are not a valid UTF-8 sequence.
    InvalidUtf8,
}!i64 {
    const s = title orelse return 0;
    return if (s.len == 0) 0 else (try text.displayWidth(s)) +| 4;
}
