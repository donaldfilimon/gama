//! Baseline integer measurement and placement. Allocate into caller-owned frame storage.
//! LaidNode is a borrow: its IR and children expire with that storage. Geometry is
//! intentionally not parent-clipped; the painter clips at the final cell buffer.
const std = @import("std");
const geo = @import("geometry.zig");
const Node = @import("node.zig").Node;
const NodeID = @import("identity.zig").NodeID;
const TextStyle = @import("style.zig").TextStyle;
const Error = @import("state.zig").Error;
const Allocator = std.mem.Allocator;
/// Optional portable providers. Context and callback borrows must outlive the call.
pub const Metrics = struct {
    /// Borrowed userdata passed to metric callbacks; must survive layout/measurement.
    context: ?*const anyopaque = null,

    /// Optional unit conversion callback; null leaves integer cell units unchanged.
    units_fn: ?*const fn (?*const anyopaque, i64, geo.Axis) i64 = null,

    /// Optional text measurement callback; result/errors replace the portable measurement.
    text_fn: ?*const fn (?*const anyopaque, Allocator, []const u8, TextStyle, ?i64) Error!geo.Size = null,

    /// Optional identity-based native-control measurement; null result uses portable layout.
    control_fn: ?*const fn (?*const anyopaque, NodeID, geo.ProposedSize) ?geo.Size = null,

    /// Thickness of divider nodes in layout units, defaulting to one cell.
    divider_thickness: i64 = 1,

    /// Convert the layout proposal into bounded integer cell units.
    pub fn units(self: Metrics, value: i64, axis: geo.Axis) i64 {
        return if (self.units_fn) |f| f(self.context, value, axis) else value;
    }
    fn control(self: Metrics, id: NodeID, proposal: geo.ProposedSize) ?geo.Size {
        return if (self.control_fn) |f| f(self.context, id, proposal) else null;
    }
    fn edges(self: Metrics, e: geo.EdgeInsets) geo.EdgeInsets {
        return .{ .leading = self.units(e.leading, .horizontal), .trailing = self.units(e.trailing, .horizontal), .top = self.units(e.top, .vertical), .bottom = self.units(e.bottom, .vertical) };
    }
    fn border(self: Metrics) geo.EdgeInsets {
        return self.edges(.{ .leading = 1, .trailing = 1, .top = 1, .bottom = 1 });
    }
};
/// Laid-out node and children; all borrowed content/storage must survive paint traversal.
pub const LaidNode = struct {
    /// Original render node associated with this computed rectangle.
    node: Node,
    /// Resolved cell rectangle of this laid-out node.
    frame: geo.Rect,
    /// Ordered children; their order participates in positional identity and layout.
    children: []const LaidNode = &.{},
};
fn axisSize(size: geo.Size, axis: geo.Axis) i64 {
    return if (axis == .horizontal) size.width else size.height;
}
fn crossAxis(axis: geo.Axis) geo.Axis {
    return if (axis == .horizontal) .vertical else .horizontal;
}
fn dimensions(main: i64, cross: i64, axis: geo.Axis) geo.Size {
    return if (axis == .horizontal) .{ .width = main, .height = cross } else .{ .width = cross, .height = main };
}
fn opened(proposal: geo.ProposedSize, axis: geo.Axis) geo.ProposedSize {
    return if (axis == .horizontal) .{ .height = proposal.height } else .{ .width = proposal.width };
}
fn proposalFor(size: geo.Size) geo.ProposedSize {
    return .{ .width = size.width, .height = size.height };
}
fn insetProposal(p: geo.ProposedSize, e: geo.EdgeInsets) geo.ProposedSize {
    return .{ .width = if (p.width) |v| @max(0, v -| e.horizontal()) else null, .height = if (p.height) |v| @max(0, v -| e.vertical()) else null };
}
fn spacingTotal(value: i64, count: usize) i64 {
    return value *| @as(i64, @intCast(@min(count -| 1, std.math.maxInt(i64))));
}
fn bounded(value: i64, minimum: ?i64, maximum: ?i64, proposed: ?i64, axis: geo.Axis, m: Metrics) i64 {
    var result = value;
    if (maximum) |v| result = if (v == std.math.maxInt(i64)) proposed orelse value else @min(result, m.units(v, axis));
    if (minimum) |v| result = @max(result, m.units(v, axis));
    return result;
}
/// Measure intrinsic component extent against the supplied per-axis proposal.
pub fn measure(a: Allocator, node: Node, proposal: geo.ProposedSize, m: Metrics) Error!geo.Size {
    return switch (node) {
        .empty => .{},
        .text => |v| if (m.text_fn) |f| try f(m.context, a, v.content, v.style, proposal.width) else try @import("text.zig").size(a, v.content, proposal.width),
        .spacer => |v| .{ .width = m.units(v, .horizontal), .height = m.units(v, .vertical) },
        .divider => .{ .width = m.divider_thickness, .height = m.divider_thickness },
        .background => |v| try measure(a, v.child.*, proposal, m),
        .styled => |v| try measure(a, v.child.*, proposal, m),
        .interactive => |v| m.control(v.id, proposal) orelse try measure(a, v.child.*, proposal, m),
        .padding => |v| blk: {
            const e = m.edges(v.insets);
            const child = try measure(a, v.child.*, insetProposal(proposal, e), m);
            break :blk .{ .width = child.width +| e.horizontal(), .height = child.height +| e.vertical() };
        },
        .border => |v| blk: {
            const e = m.border();
            const child = try measure(a, v.child.*, insetProposal(proposal, e), m);
            const title_min = if (v.title) |t| if (t.len == 0) 0 else (try @import("text.zig").displayWidth(t)) +| 4 else 0;
            break :blk .{ .width = @max(child.width +| e.horizontal(), m.units(title_min, .horizontal)), .height = child.height +| e.vertical() };
        },
        .frame => |v| blk: {
            const w = if (v.width) |n| m.units(n, .horizontal) else proposal.width;
            const h = if (v.height) |n| m.units(n, .vertical) else proposal.height;
            const child = try measure(a, v.child.*, .{ .width = w, .height = h }, m);
            break :blk .{ .width = if (v.width != null) w.? else child.width, .height = if (v.height != null) h.? else child.height };
        },
        .flex_frame => |v| blk: {
            const child = try measure(a, v.child.*, proposal, m);
            break :blk .{ .width = bounded(child.width, v.min_width, v.max_width, proposal.width, .horizontal, m), .height = bounded(child.height, v.min_height, v.max_height, proposal.height, .vertical, m) };
        },
        .group => |children| try measureOverlay(a, children, proposal, m),
        .overlay => |v| try measureOverlay(a, v.children, proposal, m),
        .stack => |v| blk: {
            if (v.children.len == 0) break :blk .{};
            var main: i64 = 0;
            var cross: i64 = 0;
            var flexible = false;
            const open = opened(proposal, v.axis);
            for (v.children) |child| {
                if (child == .divider) {
                    main +|= m.divider_thickness;
                } else if (child.flexPriority(v.axis) != 0) {
                    flexible = true;
                    main +|= try floor(a, child, v.axis, open, m);
                    if (child != .spacer) cross = @max(cross, axisSize(try measure(a, child, open, m), crossAxis(v.axis)));
                } else {
                    const size = try measure(a, child, open, m);
                    main +|= axisSize(size, v.axis);
                    cross = @max(cross, axisSize(size, crossAxis(v.axis)));
                }
            }
            main +|= spacingTotal(m.units(v.spacing, v.axis), v.children.len);
            const proposed = if (v.axis == .horizontal) proposal.width else proposal.height;
            if (flexible) if (proposed) |p| {
                main = @max(main, p);
            };
            break :blk dimensions(main, if (cross == 0) 1 else cross, v.axis);
        },
    };
}
fn measureOverlay(a: Allocator, children: []const Node, p: geo.ProposedSize, m: Metrics) Error!geo.Size {
    var result: geo.Size = .{};
    for (children) |child| {
        const size = try measure(a, child, p, m);
        result.width = @max(result.width, size.width);
        result.height = @max(result.height, size.height);
    }
    return result;
}
fn floor(a: Allocator, node: Node, axis: geo.Axis, p: geo.ProposedSize, m: Metrics) Error!i64 {
    return switch (node) {
        .spacer => |v| m.units(v, axis),
        .flex_frame => |v| m.units((if (axis == .horizontal) v.min_width else v.min_height) orelse 0, axis),
        .padding => |v| (try floor(a, v.child.*, axis, p, m)) +| (if (axis == .horizontal) m.edges(v.insets).horizontal() else m.edges(v.insets).vertical()),
        .border => |v| (try floor(a, v.child.*, axis, p, m)) +| (2 *| m.units(1, axis)),
        .styled => |v| try floor(a, v.child.*, axis, p, m),
        .background => |v| try floor(a, v.child.*, axis, p, m),
        .interactive => |v| if (m.control(v.id, p)) |size| axisSize(size, axis) else try floor(a, v.child.*, axis, p, m),
        else => 0,
    };
}
fn aligned(size: geo.Size, bounds: geo.Rect, alignment: geo.Alignment) geo.Rect {
    return .{ .size = size, .origin = .{
        .x = switch (alignment.horizontal) {
            .leading => bounds.origin.x,
            .center => bounds.origin.x +| @max(0, @divTrunc(bounds.size.width -| size.width, 2)),
            .trailing => bounds.maxX() -| size.width,
        },
        .y = switch (alignment.vertical) {
            .top => bounds.origin.y,
            .center => bounds.origin.y +| @max(0, @divTrunc(bounds.size.height -| size.height, 2)),
            .bottom => bounds.maxY() -| size.height,
        },
    } };
}
/// Allocations belong to a candidate arena; discard that arena on any failure.
pub fn place(a: Allocator, node: Node, bounds: geo.Rect, m: Metrics) Error!LaidNode {
    var result: LaidNode = .{ .node = node, .frame = bounds };
    var child: ?*const Node = null;
    var child_bounds = bounds;
    switch (node) {
        .padding => |v| {
            child = v.child;
            child_bounds = bounds.inset(m.edges(v.insets));
        },
        .border => |v| {
            child = v.child;
            child_bounds = bounds.inset(m.border());
        },
        .background => |v| child = v.child,
        .styled => |v| child = v.child,
        .interactive => |v| child = v.child,
        .frame => |v| {
            child = v.child;
            result.frame = aligned((try measure(a, node, proposalFor(bounds.size), m)).clamped(bounds.size), bounds, v.alignment);
            child_bounds = aligned((try measure(a, v.child.*, proposalFor(result.frame.size), m)).clamped(result.frame.size), result.frame, v.alignment);
        },
        .flex_frame => |v| {
            child = v.child;
            child_bounds = aligned((try measure(a, v.child.*, proposalFor(bounds.size), m)).clamped(bounds.size), bounds, v.alignment);
        },
        .group => |children| {
            result.node = .{ .overlay = .{ .alignment = .top_leading, .children = children } };
            result.children = try placeOverlay(a, children, bounds, .top_leading, m);
        },
        .overlay => |v| result.children = try placeOverlay(a, v.children, bounds, v.alignment, m),
        .stack => |v| {
            const children = try a.alloc(LaidNode, v.children.len);
            const sizes = try a.alloc(geo.Size, v.children.len);
            defer a.free(sizes);
            const spacing = m.units(v.spacing, v.axis);
            const cross = axisSize(bounds.size, crossAxis(v.axis));
            const open = opened(proposalFor(bounds.size), v.axis);
            var used: i64 = 0;
            var weight: usize = 0;
            for (v.children, 0..) |n, i| {
                sizes[i] = if (n == .divider) dimensions(m.divider_thickness, cross, v.axis) else if (n.flexPriority(v.axis) != 0) dimensions(try floor(a, n, v.axis, open, m), cross, v.axis) else try measure(a, n, open, m);
                used +|= axisSize(sizes[i], v.axis);
                if (n.flexPriority(v.axis) != 0) weight += 1;
            }
            var remaining: i64 = @max(0, axisSize(bounds.size, v.axis) -| used -| spacingTotal(spacing, v.children.len));
            var cursor = if (v.axis == .horizontal) bounds.origin.x else bounds.origin.y;
            for (v.children, 0..) |n, i| {
                if (n.flexPriority(v.axis) != 0) {
                    const w: i64 = @intCast(@min(weight, std.math.maxInt(i64)));
                    const grant = @divTrunc(remaining, w) + @intFromBool(@rem(remaining, w) != 0);
                    remaining -= grant;
                    weight -= 1;
                    sizes[i] = dimensions(axisSize(sizes[i], v.axis) +| grant, cross, v.axis);
                }
                const free = @max(0, cross -| axisSize(sizes[i], crossAxis(v.axis)));
                const offset = if (v.axis == .horizontal) switch (v.alignment.vertical) {
                    .top => @as(i64, 0),
                    .center => @divTrunc(free, 2),
                    .bottom => free,
                } else switch (v.alignment.horizontal) {
                    .leading => @as(i64, 0),
                    .center => @divTrunc(free, 2),
                    .trailing => free,
                };
                const rect: geo.Rect = .{ .size = sizes[i], .origin = if (v.axis == .horizontal) .{ .x = cursor, .y = bounds.origin.y +| offset } else .{ .x = bounds.origin.x +| offset, .y = cursor } };
                var resolved = n;
                if (resolved == .divider) resolved.divider.axis = v.axis;
                children[i] = try place(a, resolved, rect, m);
                cursor +|= axisSize(sizes[i], v.axis) +| spacing;
            }
            result.children = children;
        },
        else => {},
    }
    if (child) |n| {
        const children = try a.alloc(LaidNode, 1);
        children[0] = try place(a, n.*, child_bounds, m);
        result.children = children;
    }
    return result;
}
fn placeOverlay(a: Allocator, nodes: []const Node, bounds: geo.Rect, alignment: geo.Alignment, m: Metrics) Error![]const LaidNode {
    const children = try a.alloc(LaidNode, nodes.len);
    for (nodes, 0..) |node, i| children[i] = try place(a, node, aligned((try measure(a, node, proposalFor(bounds.size), m)).clamped(bounds.size), bounds, alignment), m);
    return children;
}
