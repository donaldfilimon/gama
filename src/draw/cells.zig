//! Planes own copied glyphs. No cell borrows model or host arena storage.
//! Mutations may change the pending back plane; front changes only on promotion.
const std = @import("std");
const geo = @import("../core/geometry.zig");
const style = @import("../core/style.zig");
const text = @import("../core/text.zig");
const unicode = @import("../core/unicode.zig");
const Error = @import("../core/state.zig").Error;
const A = std.mem.Allocator;
/// Upper bound on the product of width and height admitted by cell normalization.
pub const maximum_cell_count = 16 * 1024 * 1024;
/// Cell glyph/style plus wide-glyph continuation marker; glyph bytes are borrowed.
pub const Cell = struct {
    /// One UTF-8 grapheme, or a continuation placeholder; storage belongs to its plane.
    glyph: []const u8 = " ",

    /// Foreground, background and decoration bits for this cell.
    style: style.TextStyle = .plain,

    /// Marks the trailing cell of a wide grapheme; it carries no separate text.
    continuation: bool = false,

    /// Compare the semantic contents without transferring ownership.
    pub fn eql(x: Cell, y: Cell) bool {
        return x.continuation == y.continuation and std.meta.eql(x.style, y.style) and std.mem.eql(u8, x.glyph, y.glyph);
    }
};
/// Owned cell array and glyph arena for one front/back plane.
pub const Plane = struct {
    /// Row-major owned cell storage; glyph slices borrow this plane's arena or static text.
    cells: []Cell,

    /// Owns copied non-space glyph bytes; reset only when no plane glyph is still used.
    glyphs: std.heap.ArenaAllocator,
    fn init(a: A, n: usize) Error!Plane {
        const cells = try a.alloc(Cell, n);
        @memset(cells, .{});
        return .{ .cells = cells, .glyphs = .init(a) };
    }
    fn deinit(self: *Plane, a: A) void {
        a.free(self.cells);
        self.glyphs.deinit();
        self.* = undefined;
    }
    fn copyGlyph(self: *Plane, glyph: []const u8) Error![]const u8 {
        if (std.mem.eql(u8, glyph, " ")) return " ";
        return self.glyphs.allocator().dupe(u8, glyph);
    }
};
/// Presentation color policy; unknown and monochrome suppress explicit color sequences.
pub const ColorDepth = enum {
    /// Unspecified terminal capability; suppress explicit color escape sequences.
    unknown,
    /// Suppress explicit foreground/background color escape sequences.
    monochrome,
    /// Quantize explicit colors to the 16-color ANSI palette.
    ansi16,
    /// Quantize explicit colors to the xterm 256-color palette.
    ansi256,
    /// Emit explicit colors as 24-bit RGB sequences.
    true_color,
};
/// Normalize invalid or oversized raster dimensions to the retained zero-size representation.
pub fn normalized(size: geo.Size) geo.Size {
    if (size.width < 0 or size.height < 0) return .{};
    const n = @as(u128, @intCast(size.width)) * @as(u128, @intCast(size.height));
    return if (n > maximum_cell_count) .{} else size;
}
/// Owns two cell planes; mutate the back plane and promote only after successful presentation.
pub const CellBuffer = struct {
    /// Allocator owning both planes; retain until buffer deinit.
    allocator: A,

    /// Normalized cell dimensions matching both plane allocations.
    size: geo.Size,

    /// Last successfully presented plane; replace only after successful publication.
    front: Plane,

    /// Pending plane; writes do not change the last successful presentation.
    back: Plane,

    /// Force complete presentation after initialization or extent changes.
    force_full: bool = true,

    /// Presenter color capability; unknown deliberately emits no color SGR.
    color_depth: ColorDepth = .unknown,

    /// Normalize requested size and allocate both planes; caller must deinit using the retained allocator.
    pub fn init(a: A, requested: geo.Size) Error!CellBuffer {
        const size = normalized(requested);
        const n: usize = @intCast(size.width * size.height);
        var front = try Plane.init(a, n);
        errdefer front.deinit(a);
        return .{ .allocator = a, .size = size, .front = front, .back = try Plane.init(a, n) };
    }

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *CellBuffer) void {
        self.front.deinit(self.allocator);
        self.back.deinit(self.allocator);
        self.* = undefined;
    }
    /// Allocate both replacements before releasing either old plane.
    pub fn resize(self: *CellBuffer, requested: geo.Size) Error!void {
        var next = try init(self.allocator, requested);
        next.color_depth = self.color_depth;
        self.deinit();
        self.* = next;
    }

    /// Replace both planes only when normalized dimensions change.
    pub fn resizeIfNeeded(self: *CellBuffer, requested: geo.Size) Error!void {
        if (!std.meta.eql(self.size, normalized(requested))) try self.resize(requested);
    }
    /// Fresh candidate with an independently owned comparison plane; old buffer is untouched.
    pub fn candidate(self: *const CellBuffer, a: A, requested: geo.Size) Error!CellBuffer {
        var next = try init(a, requested);
        errdefer next.deinit();
        next.color_depth = self.color_depth;
        if (std.meta.eql(next.size, self.size)) {
            next.force_full = self.force_full;
            for (self.front.cells, next.front.cells) |old, *dest| {
                dest.* = old;
                dest.glyph = try next.front.copyGlyph(old.glyph);
            }
        }
        return next;
    }

    /// Clear pending cells and release their glyph arena without changing the front plane.
    pub fn clearBack(self: *CellBuffer) void {
        @memset(self.back.cells, .{});
        _ = self.back.glyphs.reset(.free_all);
    }

    /// Swap completed planes without allocating.
    pub fn promote(self: *CellBuffer) void {
        std.mem.swap(Plane, &self.front, &self.back);
        self.force_full = false;
    }
    fn index(self: *const CellBuffer, x: i64, y: i64) ?usize {
        if (x < 0 or y < 0 or x >= self.size.width or y >= self.size.height) return null;
        return @intCast(y * self.size.width + x);
    }

    /// Borrow/read the pending cell at a valid coordinate, or return null outside the plane.
    pub fn cell(self: *const CellBuffer, x: i64, y: i64) ?Cell {
        return self.back.cells[self.index(x, y) orelse return null];
    }
    fn clearGlyph(self: *CellBuffer, i: usize) void {
        const old = self.back.cells[i];
        if (old.continuation and i > 0) self.back.cells[i - 1] = .{};
        if (!old.continuation and (text.displayWidth(old.glyph) catch 0) == 2 and i + 1 < self.back.cells.len and self.back.cells[i + 1].continuation) self.back.cells[i + 1] = .{};
        self.back.cells[i] = .{};
    }
    /// Exactly one grapheme. Invalid text/OOM is nonmutating; valid zero-width writes clear overlap.
    pub fn put(self: *CellBuffer, x: i64, y: i64, glyph: []const u8, s: style.TextStyle) Error!void {
        const i = self.index(x, y) orelse return;
        if (try unicode.count(glyph) != 1) return error.InvalidCharacter;
        const width = try text.displayWidth(glyph);
        const owned = if (width == 0 or (width == 2 and x + 1 >= self.size.width)) "" else try self.back.copyGlyph(glyph);
        self.clearGlyph(i);
        if (owned.len == 0) return;
        self.back.cells[i] = .{ .glyph = owned, .style = s };
        if (width == 2) {
            self.clearGlyph(i + 1);
            self.back.cells[i + 1] = .{ .style = s, .continuation = true };
        }
    }

    /// Write complete graphemes to the pending plane using shared width/clipping rules.
    pub fn putText(self: *CellBuffer, x: i64, y: i64, value: []const u8, s: style.TextStyle, width: i64) Error!void {
        if (self.back.cells.len == 0) return;
        var wrapped = try text.wrap(self.allocator, value, width);
        defer wrapped.deinit(self.allocator);
        for (wrapped.lines, 0..) |line, row| {
            const yy = y +| @as(i64, @intCast(row));
            if (yy < 0 or yy >= self.size.height) continue;
            var xx = x;
            var it = try unicode.Graphemes.init(line);
            while (it.next()) |glyph| {
                try self.put(xx, yy, glyph, s);
                xx +|= try text.displayWidth(glyph);
            }
        }
    }

    /// Fill the bounded rectangle in the pending plane with the supplied cell style.
    pub fn fill(self: *CellBuffer, rect: geo.Rect, value: Cell) Error!void {
        const r = rect.intersection(.{ .size = self.size });
        if (r.size.width == 0 or r.size.height == 0) return;
        if (try unicode.count(value.glyph) != 1) return error.InvalidCharacter;
        var owned = value;
        owned.glyph = try self.back.copyGlyph(value.glyph);
        var y = r.minY();
        while (y < r.maxY()) : (y += 1) {
            var x = r.minX();
            while (x < r.maxX()) : (x += 1) {
                const i = self.index(x, y).?;
                self.clearGlyph(i);
                self.back.cells[i] = owned;
            }
        }
    }

    /// Apply background color within the clipped pending-plane rectangle.
    pub fn fillBackground(self: *CellBuffer, rect: geo.Rect, color: style.Color) void {
        const r = rect.intersection(.{ .size = self.size });
        var y = r.minY();
        while (y < r.maxY()) : (y += 1) {
            var x = r.minX();
            while (x < r.maxX()) : (x += 1) self.back.cells[self.index(x, y).?].style.background = color;
        }
    }

    /// Compare pending and front cells for the selected row.
    pub fn rowChanged(self: *const CellBuffer, y: i64) bool {
        if (y < 0 or y >= self.size.height) return false;
        if (self.force_full) return true;
        const start: usize = @intCast(y * self.size.width);
        const end: usize = @intCast((y + 1) * self.size.width);
        for (self.back.cells[start..end], self.front.cells[start..end]) |b, f| if (!b.eql(f)) return true;
        return false;
    }

    /// Allocate back-row text with trailing exact-space graphemes removed; free the slice with a.
    /// An out-of-range row returns an empty slice, also safe to free with a.
    pub fn rowText(self: *const CellBuffer, a: A, y: i64) Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        if (y >= 0 and y < self.size.height) {
            const start: usize = @intCast(y * self.size.width);
            const end: usize = @intCast((y + 1) * self.size.width);
            for (self.back.cells[start..end]) |c| if (!c.continuation) {
                try out.appendSlice(a, c.glyph);
            };
        }
        // Trim exact space graphemes, including the decorated-punctuation case.
        var it = try unicode.Graphemes.init(out.items);
        var last: usize = 0;
        while (it.next()) |glyph| if (!std.mem.eql(u8, glyph, " ")) {
            last = it.offset;
        };
        out.shrinkRetainingCapacity(last);
        return out.toOwnedSlice(a);
    }

    /// Maximal contiguous run of equal-style cells within one row, including continuation cells.
    pub const Run = struct {
        /// Zero-based row in the cell plane.
        row: i64,
        /// Zero-based column in the cell plane.
        column: i64,
        /// Number of cells spanned by the run, including wide-glyph continuations.
        width: i64,
        /// Borrowed back-plane cells spanning the run; invalidated by buffer mutation.
        cells: []const Cell,
        /// Style shared by all cells in this run.
        style: style.TextStyle,
    };

    /// Iterator over back-plane rows/runs; buffer must remain unchanged during iteration.
    pub const Runs = struct {
        /// Borrowed cell buffer whose back plane is being scanned.
        buffer: *const CellBuffer,

        /// Next row-major back-plane cell index; advanced only by next.
        offset: usize = 0,

        /// Borrow the next maximal equal-style row segment; null after all cells are consumed.
        pub fn next(self: *Runs) ?Run {
            const b = self.buffer;
            if (self.offset >= b.back.cells.len) return null;
            const w: usize = @intCast(b.size.width);
            const start = self.offset;
            const row_end = (start / w + 1) * w;
            self.offset += 1;
            while (self.offset < row_end and std.meta.eql(b.back.cells[start].style, b.back.cells[self.offset].style)) self.offset += 1;
            return .{ .row = @intCast(start / w), .column = @intCast(start % w), .width = @intCast(self.offset - start), .cells = b.back.cells[start..self.offset], .style = b.back.cells[start].style };
        }
    };

    /// Iterate maximal equal-style runs in the pending plane without promotion.
    pub fn runs(self: *const CellBuffer) Runs {
        return .{ .buffer = self };
    }
};
