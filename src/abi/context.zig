//! Owned diagnostic application + shared Host/DrawingPump. No adapter raster or layout.
//! All public methods require the owner executor and reject reentry. Context and
//! borrowed bytes must not outlive destroy; input/resize do not invalidate bytes.
const std = @import("std");
const g = @import("../root.zig");
const input = @import("input.zig");
/// Reference embedding application displaying and incrementing a shared count signal.
pub const App = struct {
    /// Borrowed count signal owned alongside this application by Context.
    count: *g.Signal(u64),

    /// Single primary scene rendering the embedding counter.
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};

    /// Subscribe the host to count changes so signal updates mark its next frame dirty.
    pub fn connect(self: *@This(), host: *g.Host(@This())) g.Error!void {
        try host.observe(self.count);
    }
    fn increment(ref: *const g.SignalRef(u64), _: *anyopaque) g.Error!void {
        try ref.set((try ref.read()).* +| 1);
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        const label: g.authoring.Text = .{ .content = try std.fmt.allocPrint(ctx.allocator, "Gama C Embed {d}", .{(try self.count.read()).*}) };
        const button = try g.authoring.buttonTitle(ctx, "Increment", try ctx.action(try self.count.reference(), increment));
        const stack = g.authoring.vStack(g.composition.tuple(.{ label, button }), .{});
        return stack.render(ctx);
    }
};
/// Stable embedding owner for app, signal, host and drawing pump; destroy invalidates borrowed outputs.
pub const Context = struct {
    /// Allocator used for owned storage; it must remain usable until deinitialization.
    allocator: std.mem.Allocator,

    /// Embedded application value borrowing this context's count signal.
    app: App,

    /// Borrowed host pointer; keep the host alive until this value is released.
    host: *g.Host(App),

    /// Owned drawing pump producing binary DrawList output from host frames.
    drawing: g.DrawingPump(App),

    /// Context reentry guard around ABI operations.
    busy: bool = false,

    /// Allocate the embedding app, signal, host and drawing pump; allocator must remain usable until destroy.
    pub fn create(a: std.mem.Allocator, columns: i32, rows: i32) g.Error!*Context {
        const self = try a.create(Context);
        errdefer a.destroy(self);
        const count = try g.Signal(u64).create(a, 0);
        errdefer count.destroy() catch unreachable;
        self.allocator = a;
        self.app = .{ .count = count };
        self.host = try g.Host(App).create(a, &self.app);
        errdefer self.host.destroy() catch unreachable;
        self.drawing = try g.DrawingPump(App).init(a, self.host, .draw_list);
        errdefer self.drawing.deinit();
        self.busy = false;
        try self.host.handle(.{ .resize = dimensions(columns, rows) });
        return self;
    }
    fn enter(self: *Context) g.Error!void {
        try self.host.checkExecutor();
        if (self.busy) return error.Reentrant;
        self.busy = true;
    }

    /// Release the stable owner and its resources; no handle may be used afterward.
    pub fn destroy(self: *Context) g.Error!void {
        try self.enter();
        self.host.destroy() catch |e| {
            self.busy = false;
            return e;
        };
        self.drawing.deinit();
        self.app.count.destroy() catch unreachable;
        self.allocator.destroy(self);
    }

    /// Clamp dimensions to at least one cell and send a resize event to the host.
    /// Drawing allocation/admission occurs on a later frame call; existing output bytes remain borrowed.
    pub fn resize(self: *Context, columns: i32, rows: i32) g.Error!void {
        try self.enter();
        defer self.busy = false;
        try self.host.handle(.{ .resize = dimensions(columns, rows) });
    }

    /// Validate and dispatch a semantic ABI key to the installed context.
    pub fn key(self: *Context, code: i32, scalar: i32, shift: i32, control: i32) g.Error!void {
        try self.enter();
        defer self.busy = false;
        var decoded = try input.decode(code, scalar, shift, control);
        if (decoded.key()) |key_event| try self.host.handle(.{ .key = key_event });
    }

    /// Dispatch signed cell coordinates as a press when pressed is nonzero, otherwise release.
    /// Hit testing uses the last published layout; coordinates are not pre-clamped.
    pub fn pointer(self: *Context, column: i32, row: i32, pressed: i32) g.Error!void {
        try self.enter();
        defer self.busy = false;
        try self.host.handle(if (pressed != 0) .{ .pointer = .{ .x = column, .y = row } } else .pointer_release);
    }

    /// Report whether pending state/input requires another publication.
    pub fn needsFrame(self: *Context) g.Error!bool {
        try self.enter();
        defer self.busy = false;
        return self.host.needsFrame();
    }
    /// The frame borrow expires on the next frame call, even clean or failed.
    /// Last successful publication remains internally intact after failure.
    pub fn frame(self: *Context, normalize: bool) g.Error!?[]const u8 {
        try self.enter();
        defer self.busy = false;
        // Clean wins before dimension admission, with no allocation or publication.
        if (!try self.host.needsFrame()) return null;
        const result = if (normalize) try self.drawing.advanceNormalized({}, admitBytes) else try self.drawing.advanceDelivered({}, admitBytes, &.{});
        return if (result.produced) try self.host.currentOutput() else null;
    }
};
/// Clamp signed ABI dimensions to at least one cell; allocation admission is checked separately.
pub fn dimensions(columns: i32, rows: i32) g.geometry.Size {
    return .{ .width = @max(1, columns), .height = @max(1, rows) };
}
/// Used at the nonallocating delivery boundary, before Host publication.
pub fn admitLength(length: usize) g.Error!void {
    if (length > std.math.maxInt(i32)) return error.FrameTooLarge;
}
fn admitBytes(_: void, bytes: []const u8) g.Error!void {
    try admitLength(bytes.len);
}
/// Map shared errors to the versioned adapter status codes.
pub fn status(err: g.Error) i32 {
    return switch (err) {
        error.InvalidCharacter => -2,
        error.FrameTooLarge => -3,
        error.OutOfMemory => -4,
        else => -1,
    };
}
