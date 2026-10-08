//! Baseline signed 64-bit geometry. Saturation is independent of target pointer size.
/// Add signed cell coordinates with saturation at integer limits.
pub fn satAdd(a: i64, b: i64) i64 {
    return a +| b;
}
/// Subtract signed cell coordinates with saturation at integer limits.
pub fn satSub(a: i64, b: i64) i64 {
    return a -| b;
}
/// Signed cell coordinate; arithmetic helpers saturate at i64 limits.
pub const Point = struct {
    /// Horizontal cell coordinate relative to the active surface origin.
    x: i64 = 0,

    /// Vertical cell coordinate relative to the active surface origin.
    y: i64 = 0,

    /// Add points componentwise with saturating coordinate arithmetic.
    pub fn add(a: Point, b: Point) Point {
        return .{ .x = satAdd(a.x, b.x), .y = satAdd(a.y, b.y) };
    }

    /// Subtract points componentwise with saturating coordinate arithmetic.
    pub fn subtract(a: Point, b: Point) Point {
        return .{ .x = satSub(a.x, b.x), .y = satSub(a.y, b.y) };
    }
};
/// Signed width and height in cells; use clamped before requiring nonnegative extents.
pub const Size = struct {
    /// Signed horizontal cell extent; clamped explicitly where nonnegative sizing is required.
    width: i64 = 0,

    /// Signed vertical cell extent; clamped explicitly where nonnegative sizing is required.
    height: i64 = 0,

    /// Clamp each dimension between zero and the corresponding nonnegative maximum.
    pub fn clamped(self: Size, maximum: Size) Size {
        return .{ .width = @max(0, @min(self.width, @max(0, maximum.width))), .height = @max(0, @min(self.height, @max(0, maximum.height))) };
    }
};
/// Signed edge offsets in cells, summed with saturating arithmetic.
pub const EdgeInsets = struct {
    /// Offset applied to the upper edge.
    top: i64 = 0,

    /// Offset applied to the left edge.
    leading: i64 = 0,

    /// Offset applied to the lower edge.
    bottom: i64 = 0,

    /// Offset applied to the right edge.
    trailing: i64 = 0,

    /// Return the sum of leading and trailing insets.
    pub fn horizontal(self: EdgeInsets) i64 {
        return satAdd(self.leading, self.trailing);
    }

    /// Return the sum of top and bottom insets.
    pub fn vertical(self: EdgeInsets) i64 {
        return satAdd(self.top, self.bottom);
    }
};
/// Cell rectangle with inclusive minimum and exclusive maximum coordinates.
pub const Rect = struct {
    /// Upper-left cell coordinate.
    origin: Point = .{},

    /// Cell extent; max-edge and intersection methods treat negative dimensions as empty.
    size: Size = .{},

    /// Empty rectangle at the coordinate origin.
    pub const zero: Rect = .{};

    /// Return the left edge in cell coordinates.
    pub fn minX(self: Rect) i64 {
        return self.origin.x;
    }

    /// Return the top edge in cell coordinates.
    pub fn minY(self: Rect) i64 {
        return self.origin.y;
    }

    /// Return the saturated right edge in cell coordinates.
    pub fn maxX(self: Rect) i64 {
        return satAdd(self.origin.x, @max(0, self.size.width));
    }

    /// Return the saturated bottom edge in cell coordinates.
    pub fn maxY(self: Rect) i64 {
        return satAdd(self.origin.y, @max(0, self.size.height));
    }

    /// Test point containment using the retained half-open rectangle convention.
    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.minX() and point.x < self.maxX() and point.y >= self.minY() and point.y < self.maxY();
    }

    /// Compute the bounded overlap of two rectangles.
    pub fn intersection(self: Rect, other: Rect) Rect {
        const x0 = @max(self.minX(), other.minX());
        const y0 = @max(self.minY(), other.minY());
        const x1 = @min(self.maxX(), other.maxX());
        const y1 = @min(self.maxY(), other.maxY());
        if (x1 <= x0 or y1 <= y0) return .zero;
        return .{ .origin = .{ .x = x0, .y = y0 }, .size = .{ .width = x1 - x0, .height = y1 - y0 } };
    }

    /// Apply edge insets while preventing negative resulting extents.
    pub fn inset(self: Rect, edges: EdgeInsets) Rect {
        return .{ .origin = .{ .x = satAdd(self.minX(), edges.leading), .y = satAdd(self.minY(), edges.top) }, .size = .{ .width = @max(0, satSub(@max(0, self.size.width), edges.horizontal())), .height = @max(0, satSub(@max(0, self.size.height), edges.vertical())) } };
    }
};
/// Per-axis layout proposal; null leaves that axis unspecified.
pub const ProposedSize = struct {
    /// Proposed width in cells, or null when unspecified.
    width: ?i64 = null,

    /// Proposed height in cells, or null when unspecified.
    height: ?i64 = null,

    /// Fill unspecified proposal axes from the supplied fallback extent.
    pub fn replacingUnspecified(self: ProposedSize, fallback: Size) Size {
        return .{ .width = self.width orelse fallback.width, .height = self.height orelse fallback.height };
    }
};

/// Dimension along which a container measures or distributes children.
pub const Axis = enum {
    /// Left-to-right x dimension.
    horizontal,
    /// Top-to-bottom y dimension.
    vertical,
};
/// Horizontal placement within spare width.
pub const HorizontalAlignment = enum {
    /// Align to the left edge.
    leading,
    /// Center horizontally.
    center,
    /// Align to the right edge.
    trailing,
};
/// Vertical placement within spare height.
pub const VerticalAlignment = enum {
    /// Align to the upper edge.
    top,
    /// Center vertically.
    center,
    /// Align to the lower edge.
    bottom,
};
/// Independent horizontal and vertical placement rules.
pub const Alignment = struct {
    /// Placement along the x axis; centered by default.
    horizontal: HorizontalAlignment = .center,

    /// Placement along the y axis; centered by default.
    vertical: VerticalAlignment = .center,

    /// Center on both axes.
    pub const center: Alignment = .{};

    /// Align to the upper-left corner.
    pub const top_leading: Alignment = .{ .horizontal = .leading, .vertical = .top };

    /// Align to the lower-right corner.
    pub const bottom_trailing: Alignment = .{ .horizontal = .trailing, .vertical = .bottom };
};
