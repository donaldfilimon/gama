//! Explicit tuple, branch and collection lowering. Identity follows the Swift baseline.
const std = @import("std");
const c = @import("context.zig");
const Node = @import("node.zig").Node;
const NodeID = @import("identity.zig").NodeID;
/// Compile-time validate the required render signature.
pub fn validateComponent(comptime T: type) void {
    if (@typeInfo(T) != .@"struct" or !@hasDecl(T, "render")) @compileError("component.render-signature");
    if (@TypeOf(T.render) != fn (*const T, *c.BuildContext) c.Error!Node) @compileError("component.render-signature");
}
/// Lower this component into frame-owned nodes using the supplied build context.
pub fn render(view: anytype, ctx: *c.BuildContext) c.Error!Node {
    const T = @TypeOf(view);
    comptime validateComponent(T);
    return view.render(ctx);
}
/// Zero-content component lowering to Node.empty without allocation.
pub const Empty = struct {
    /// Lower this component into frame-owned nodes using the supplied build context.
    pub fn render(_: *const Empty, _: *c.BuildContext) c.Error!Node {
        return .empty;
    }
};
/// Construct ordered heterogeneous children without allocation until rendering.
pub fn Tuple(comptime T: type) type {
    return struct {
        /// Ordered children; their order participates in positional identity and layout.
        children: T,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            const fields = @typeInfo(T).@"struct".field_names;
            const nodes = try ctx.allocator.alloc(Node, fields.len);
            inline for (fields, 0..) |field, i| {
                var child = ctx.child(@intCast(i));
                nodes[i] = try renderValue(@field(self.children, field), &child);
            }
            return .{ .group = nodes };
        }
    };
}
const renderValue = render;
/// Construct ordered heterogeneous children without allocation until rendering.
pub fn tuple(children: anytype) Tuple(@TypeOf(children)) {
    return .{ .children = children };
}
/// Return a typed conditional component preserving branch structure.
pub fn Branch(comptime First: type, comptime Second: type) type {
    return struct {
        /// Selected branch payload; changing branches changes the child identity discriminator.
        value: union(enum) {
            /// Component rendered only when the condition selects the first branch.
            first: First,
            /// Component rendered only when the condition selects the second branch.
            second: Second,
        },

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            return switch (self.value) {
                .first => |v| blk: {
                    var sub = ctx.child(0);
                    break :blk try renderValue(v, &sub);
                },
                .second => |v| blk: {
                    var sub = ctx.child(1);
                    break :blk try renderValue(v, &sub);
                },
            };
        }
    };
}
/// Derive a child context from a stable caller identity.
pub fn Scoped(comptime T: type) type {
    return struct {
        /// Child component value rendered under the explicit identity scope.
        content: T,

        /// Replacement identity for the child context; controls state retention across reorderings.
        id: NodeID,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            var sub = ctx.scoped(self.id);
            return renderValue(self.content, &sub);
        }
    };
}
/// Bind child state to an explicit stable identity rather than position.
pub fn stateScope(view: anytype, id: NodeID) Scoped(@TypeOf(view)) {
    return .{ .content = view, .id = id };
}
/// Execute content each build. start_index is the collection's actual signed index.
pub fn ForEach(comptime Item: type, comptime View: type) type {
    return struct {
        /// Borrowed item slice; iteration does not retain it beyond rendering.
        data: []const Item,

        /// Starting positional child index used when identity is null.
        start_index: i64 = 0,

        /// Produce a view for each borrowed item during rendering.
        content: *const fn (Item) View,

        /// Optional stable item identity; null uses start_index plus array position.
        identity: ?*const fn (Item) NodeID = null,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            const nodes = try ctx.allocator.alloc(Node, self.data.len);
            for (self.data, 0..) |item, i| {
                var sub = if (self.identity) |id| ctx.scoped(id(item)) else blk: {
                    const position = std.math.cast(i64, i) orelse return error.CollectionTooLarge;
                    const index = std.math.add(i64, self.start_index, position) catch return error.CollectionTooLarge;
                    break :blk ctx.child(index);
                };
                nodes[i] = try renderValue(self.content(item), &sub);
            }
            return .{ .group = nodes };
        }
    };
}
/// Builder-loop equivalents enumerate previously constructed values.
pub fn Views(comptime T: type) type {
    return struct {
        /// Borrowed view slice rendered with positional child identities.
        values: []const T,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            const nodes = try ctx.allocator.alloc(Node, self.values.len);
            for (self.values, 0..) |v, i| {
                var sub = ctx.child(std.math.cast(i64, i) orelse return error.CollectionTooLarge);
                nodes[i] = try renderValue(v, &sub);
            }
            return .{ .group = nodes };
        }
    };
}
/// Flatten group nodes into frame-owned ordered children.
pub fn flatten(ctx: *c.BuildContext, node: Node) c.Error![]const Node {
    var list: std.ArrayList(Node) = .empty;
    try appendFlat(ctx, &list, node);
    return list.toOwnedSlice(ctx.allocator);
}
fn appendFlat(ctx: *c.BuildContext, list: *std.ArrayList(Node), node: Node) c.Error!void {
    switch (node) {
        .empty => {},
        .group => |children| for (children) |n| try appendFlat(ctx, list, n),
        else => try list.append(ctx.allocator, node),
    }
}
