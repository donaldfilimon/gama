//! Raw Node construction does not copy referenced storage. Use BuildContext.retain for borrowed external IR.
//! Retained IR borrows exclusively from its owning frame storage.
const geo = @import("geometry.zig");
const style = @import("style.zig");
const NodeID = @import("identity.zig").NodeID;
/// Portable render tree; slices/pointers borrow storage that must survive layout and paint.
pub const Node = union(enum) {
    /// No content and zero intrinsic extent.
    empty,

    /// UTF-8 text leaf measured and painted with a text style.
    text: struct {
        /// Borrowed UTF-8 text; storage must survive layout and painting.
        content: []const u8,
        /// Text properties merged with inherited painter style.
        style: style.TextStyle = .plain,
    },

    /// Ordered child sequence without its own arrangement wrapper.
    group: []const Node,

    /// Children arranged along one axis with spacing and cross-axis alignment.
    stack: struct {
        /// Main axis for child placement and space distribution.
        axis: geo.Axis,
        /// Inter-child spacing in integer cells.
        spacing: i64 = 0,
        /// Placement rule used when the allocated extent exceeds intrinsic content size.
        alignment: geo.Alignment,
        /// Ordered children; their order participates in positional identity and layout.
        children: []const Node,
    },

    /// Children sharing a rectangle, painted in slice order.
    overlay: struct {
        /// Placement rule used when the allocated extent exceeds intrinsic content size.
        alignment: geo.Alignment = .center,
        /// Ordered children; their order participates in positional identity and layout.
        children: []const Node,
    },

    /// Flexible blank space with the supplied minimum cell length.
    spacer: i64,

    /// Rule drawn along an explicit or layout-derived axis.
    divider: struct {
        /// Text style for the divider glyphs, gray by default.
        style: style.TextStyle = .{ .foreground = .gray },
        /// Explicit rule axis; null lets layout choose from the containing axis.
        axis: ?geo.Axis = null,
    },

    /// Wrapper adding edge offsets around one child.
    padding: struct {
        /// Signed edge cell counts applied to the child frame.
        insets: geo.EdgeInsets,
        /// Borrowed child node; must survive traversal of this tree.
        child: *const Node,
    },

    /// Box-drawing wrapper with an optional title along the upper edge.
    border: struct {
        /// Built-in box-drawing glyph set.
        style: style.BorderStyle = .single,
        /// Text style used to paint border glyphs and title.
        text_style: style.TextStyle = .plain,
        /// Optional borrowed UTF-8 border title; must survive paint.
        title: ?[]const u8 = null,
        /// Borrowed node enclosed by the border.
        child: *const Node,
    },

    /// Background-fill wrapper painted before its borrowed child.
    background: struct {
        /// Color of this drawing or decoration operation.
        color: style.Color,
        /// Borrowed node painted over the background fill.
        child: *const Node,
    },

    /// Optional fixed dimensions and alignment around one child.
    frame: struct {
        /// Fixed cell width, or null to use intrinsic child width.
        width: ?i64 = null,
        /// Fixed cell height, or null to use intrinsic child height.
        height: ?i64 = null,
        /// Placement rule used when the allocated extent exceeds intrinsic content size.
        alignment: geo.Alignment = .center,
        /// Borrowed node aligned inside the fixed-size frame.
        child: *const Node,
    },

    /// Per-axis flexible constraints around one child.
    flex_frame: struct {
        /// Optional minimum width in cells.
        min_width: ?i64 = null,
        /// Optional maximum width; maxInt(i64) grants horizontal flexibility.
        max_width: ?i64 = null,
        /// Optional minimum height in cells.
        min_height: ?i64 = null,
        /// Optional maximum height; maxInt(i64) grants vertical flexibility.
        max_height: ?i64 = null,
        /// Placement rule used when the allocated extent exceeds intrinsic content size.
        alignment: geo.Alignment = .center,
        /// Borrowed node receiving the constrained proposal.
        child: *const Node,
    },

    /// Text-style wrapper whose properties merge into descendant paint styles.
    styled: struct {
        /// Text properties merged into descendant painting.
        style: style.TextStyle,
        /// Borrowed node receiving the merged style.
        child: *const Node,
    },

    /// Identity and focus metadata around a painted subtree; actions are registered separately.
    interactive: struct {
        /// Node identity used for focus and hit-test registration lookup.
        id: NodeID,
        /// Whether the interaction may participate in focus traversal.
        focusable: bool,
        /// Borrowed visual subtree associated with this interactive identity.
        child: *const Node,
    },

    /// Return flexibility priority for the specified axis independently.
    pub fn flexPriority(self: Node, axis: geo.Axis) u8 {
        return switch (self) {
            .spacer => 1,
            .flex_frame => |f| if ((if (axis == .horizontal) f.max_width else f.max_height) == @as(?i64, 0x7fff_ffff_ffff_ffff)) 1 else 0,
            .padding => |v| v.child.flexPriority(axis),
            .border => |v| v.child.flexPriority(axis),
            .background => |v| v.child.flexPriority(axis),
            .styled => |v| v.child.flexPriority(axis),
            .interactive => |v| v.child.flexPriority(axis),
            else => 0,
        };
    }
};
