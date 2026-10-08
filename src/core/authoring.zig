//! Portable primitive lowering. Interaction registrations are consumed by a host.
const std = @import("std");
const c = @import("context.zig");
const comp = @import("composition.zig");
const geo = @import("geometry.zig");
const s = @import("style.zig");
const Node = @import("node.zig").Node;
const NodeID = @import("identity.zig").NodeID;
/// Empty component from composition; lowers to Node.empty.
pub const Empty = comp.Empty;
/// Composition tuple constructor; renders children in tuple order.
pub const tuple = comp.tuple;
/// Composition conditional type preserving separate branch identity scopes.
pub const Branch = comp.Branch;
/// Composition repetition type with optional explicit item identity.
pub const ForEach = comp.ForEach;
/// Composition view slice type with positional child identity.
pub const Views = comp.Views;
/// Composition wrapper that replaces the child identity scope.
pub const stateScope = comp.stateScope;
/// Lower this component into frame-owned nodes using the supplied build context.
pub const render = comp.render;
/// Borrowed UTF-8 text and style; rendering copies text into the frame arena.
pub const Text = struct {
    /// Borrowed UTF-8 bytes, validated and copied into frame storage during render.
    content: []const u8,

    /// Explicit text properties merged with the inherited style.
    style: s.TextStyle = .plain,

    /// Return a text value with bold decoration enabled.
    pub fn bold(self: Text) Text {
        var v = self;
        v.style.attributes |= s.Attributes.bold;
        return v;
    }

    /// Return a text value with italic decoration enabled.
    pub fn italic(self: Text) Text {
        var v = self;
        v.style.attributes |= s.Attributes.italic;
        return v;
    }

    /// Return a text value with underline decoration enabled.
    pub fn underline(self: Text) Text {
        var v = self;
        v.style.attributes |= s.Attributes.underline;
        return v;
    }

    /// Lower this component into frame-owned nodes using the supplied build context.
    pub fn render(self: *const Text, ctx: *c.BuildContext) c.Error!Node {
        return .{ .text = .{ .content = try ctx.copyText(self.content), .style = ctx.inherited_style.merging(self.style) } };
    }
};
/// Flexible empty space with a minimum cell length.
pub const Spacer = struct {
    /// Minimum spacer length in cells.
    min_length: i64 = 0,

    /// Lower this component into frame-owned nodes using the supplied build context.
    pub fn render(self: *const Spacer, _: *c.BuildContext) c.Error!Node {
        return .{ .spacer = self.min_length };
    }
};
/// A divider whose orientation is resolved by the containing layout.
pub const Divider = struct {
    /// Lower this component into frame-owned nodes using the supplied build context.
    pub fn render(_: *const Divider, _: *c.BuildContext) c.Error!Node {
        return .{ .divider = .{} };
    }
};
/// Axis, spacing and child alignment used when lowering a stack.
pub const StackOptions = struct {
    /// Main axis along which children are arranged.
    axis: geo.Axis,
    /// Inter-child spacing in integer cells.
    spacing: i64 = 0,
    /// Placement rule used when the allocated extent exceeds intrinsic content size.
    alignment: geo.Alignment,
};
/// Return a typed stack component; children retain their declared order.
pub fn Stack(comptime T: type) type {
    return struct {
        /// Child component value rendered and flattened into ordered stack children.
        content: T,

        /// Stack arrangement copied into the lowered node.
        options: StackOptions,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            var sub = ctx.child(0);
            return .{ .stack = .{ .axis = self.options.axis, .spacing = self.options.spacing, .alignment = self.options.alignment, .children = try comp.flatten(ctx, try comp.render(self.content, &sub)) } };
        }
    };
}
/// Arrange content vertically with the supplied spacing and horizontal alignment.
pub fn vStack(content: anytype, options: struct {
    /// Inter-child spacing in integer cells.
    spacing: i64 = 0,
    /// Placement rule used when the allocated extent exceeds intrinsic content size.
    alignment: geo.HorizontalAlignment = .leading,
}) Stack(@TypeOf(content)) {
    return .{ .content = content, .options = .{ .axis = .vertical, .spacing = options.spacing, .alignment = .{ .horizontal = options.alignment, .vertical = .top } } };
}
/// Arrange content horizontally with the supplied spacing and vertical alignment.
pub fn hStack(content: anytype, options: struct {
    /// Inter-child spacing in integer cells.
    spacing: i64 = 0,
    /// Placement rule used when the allocated extent exceeds intrinsic content size.
    alignment: geo.VerticalAlignment = .center,
}) Stack(@TypeOf(content)) {
    return .{ .content = content, .options = .{ .axis = .horizontal, .spacing = options.spacing, .alignment = .{ .horizontal = .leading, .vertical = options.alignment } } };
}
/// Construct a leading-aligned vertical list with zero spacing.
pub fn list(content: anytype) Stack(@TypeOf(content)) {
    return vStack(content, .{});
}
/// Return the typed overlay component; children share the allocated extent.
pub fn Overlay(comptime T: type) type {
    return struct {
        /// Child component value rendered and flattened into overlay children.
        content: T,

        /// Placement rule used when the allocated extent exceeds intrinsic content size.
        alignment: geo.Alignment = .center,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            var sub = ctx.child(0);
            return .{ .overlay = .{ .alignment = self.alignment, .children = try comp.flatten(ctx, try comp.render(self.content, &sub)) } };
        }
    };
}
/// Overlay content at the requested alignment.
pub fn zStack(content: anytype, alignment: geo.Alignment) Overlay(@TypeOf(content)) {
    return .{ .content = content, .alignment = alignment };
}
fn focused(ctx: *c.BuildContext) bool {
    return if (ctx.focus) |id| id.raw == ctx.id.raw else false;
}
fn buttonStyle(ctx: *c.BuildContext) s.TextStyle {
    if (!ctx.environment.enabled) return .{ .foreground = .gray, .attributes = s.Attributes.dim };
    return if (focused(ctx)) .{ .foreground = .black, .background = .cyan, .attributes = s.Attributes.bold } else .{ .attributes = s.Attributes.bold };
}
fn interactive(ctx: *c.BuildContext, style: s.TextStyle, child: Node) c.Error!Node {
    return .{ .interactive = .{ .id = ctx.id, .focusable = ctx.environment.enabled, .child = try ctx.box(.{ .styled = .{ .style = style, .child = try ctx.box(child) } }) } };
}
/// Return a typed focusable button component with a frame-owned action.
pub fn Button(comptime Label: type) type {
    return struct {
        /// Component rendered inside the button; its captured data must survive rendering.
        label: Label,

        /// Frame-owned callback capture; the originating frame must outlive registration use.
        action: c.Action,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            if (ctx.environment.enabled) try ctx.register(.{ .action = .{ .id = ctx.id, .action = self.action, .identity = ctx.environment.action_identity } });
            var sub = ctx.child(0);
            return interactive(ctx, buttonStyle(ctx), try comp.render(self.label, &sub));
        }
    };
}
/// Allocate the padded button label in the current frame arena.
pub fn buttonTitle(ctx: *c.BuildContext, title: []const u8, action: c.Action) c.Error!Button(Text) {
    return .{ .label = .{ .content = try std.fmt.allocPrint(ctx.allocator, " {s} ", .{title}) }, .action = action };
}
/// Snapshot is read by the caller from its binding. The host owns cursor slot zero and key handling.
pub const TextField = struct {
    /// Borrowed UTF-8 snapshot read by the caller from binding before rendering.
    value: []const u8,

    /// Borrowed text shown when value is empty; copied during rendering.
    placeholder: []const u8 = "",

    /// Owner-issued typed binding token; never synthesize one from raw pointers.
    binding: c.BindingToken,

    /// Lower this component into frame-owned nodes using the supplied build context.
    pub fn render(self: *const TextField, ctx: *c.BuildContext) c.Error!Node {
        if (ctx.environment.enabled) try ctx.register(.{ .text_field = .{ .id = ctx.id, .binding = self.binding } });
        var style: s.TextStyle = .plain;
        if (self.value.len == 0) style.attributes |= s.Attributes.dim;
        if (!ctx.environment.enabled) {
            style.foreground = .gray;
            style.attributes |= s.Attributes.dim;
        }
        if (focused(ctx)) {
            style.foreground = .black;
            style.background = .cyan;
        }
        const visible = if (self.value.len == 0) self.placeholder else self.value;
        _ = try @import("unicode.zig").count(visible);
        return interactive(ctx, style, .{ .text = .{ .content = try std.fmt.allocPrint(ctx.allocator, " {s} ", .{visible}) } });
    }
};
/// Boolean control displaying a checkbox marker and a borrowed title.
pub const Toggle = struct {
    /// Borrowed UTF-8 label copied into the rendered frame.
    title: []const u8,

    /// Current boolean snapshot; host activation writes through binding.
    value: bool,

    /// Owner-issued typed binding token; never synthesize one from raw pointers.
    binding: c.BindingToken,

    /// Lower this component into frame-owned nodes using the supplied build context.
    pub fn render(self: *const Toggle, ctx: *c.BuildContext) c.Error!Node {
        if (ctx.environment.enabled) try ctx.register(.{ .toggle = .{ .id = ctx.id, .binding = self.binding, .identity = ctx.environment.action_identity } });
        var sub = ctx.child(0);
        const label: Text = .{ .content = try std.fmt.allocPrint(ctx.allocator, "[{s}] {s}", .{ if (self.value) "x" else " ", self.title }) };
        return interactive(ctx, buttonStyle(ctx), try label.render(&sub));
    }
};
/// Alternate name for Toggle, with identical boolean binding behavior.
pub const Checkbox = Toggle;
/// Text progress bar; rendering clamps width to 0...4096 and fraction to 0...1.
pub const Progress = struct {
    /// Completed amount divided by total; fraction clamps nonfinite/out-of-range ratios.
    value: f64,

    /// Denominator for the completion fraction; nonpositive values produce zero progress.
    total: f64 = 1,

    /// Optional borrowed UTF-8 label prefixed to the progress bar.
    label: ?[]const u8 = null,

    /// Requested bar width in cells, clamped to 0...4096 during render.
    width: i64 = 20,

    /// Clamp progress to zero through one, handling invalid totals and non-finite ratios.
    pub fn fraction(self: Progress) f64 {
        if (self.total <= 0) return 0;
        const ratio = self.value / self.total;
        if (!std.math.isFinite(ratio)) return if (ratio > 0) 1 else 0;
        return @max(0, @min(1, ratio));
    }

    /// Lower this component into frame-owned nodes using the supplied build context.
    pub fn render(self: *const Progress, ctx: *c.BuildContext) c.Error!Node {
        const f = self.fraction();
        const width: usize = @intCast(@max(0, @min(4096, self.width)));
        var eighths: usize = @intFromFloat(f * @as(f64, @floatFromInt(width * 8)) + 0.5);
        if (f < 1 and width > 0) eighths = @min(eighths, width * 8 - 1);
        var out: std.ArrayList(u8) = .empty;
        if (self.label) |label| {
            _ = try @import("unicode.zig").count(label);
            try out.appendSlice(ctx.allocator, label);
            try out.append(ctx.allocator, ' ');
        }
        try out.append(ctx.allocator, '[');
        const partials = [_][]const u8{ "░", "▏", "▎", "▍", "▌", "▋", "▊", "▉" };
        for (0..width) |i| try out.appendSlice(ctx.allocator, if (i < eighths / 8) "█" else if (i == eighths / 8) partials[eighths % 8] else "░");
        const percent: usize = if (f >= 1) 100 else @min(99, @as(usize, @intFromFloat(f * 100 + 0.5)));
        try out.appendSlice(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "] {d}%", .{percent}));
        return .{ .text = .{ .content = try out.toOwnedSlice(ctx.allocator), .style = ctx.inherited_style } };
    }
};
/// Alternate name for Progress with the same clamping and rendering rules.
pub const ProgressView = Progress;
/// Computed visible half-open item range and scrolling bounds.
pub const VirtualWindow = struct {
    /// First visible item index, clamped to max_offset.
    offset: usize,
    /// Exclusive visible item index, bounded by the item count.
    end: usize,
    /// Bounded storage or visible-row capacity; callers must respect the declared limit.
    capacity: usize,
    /// Largest valid starting item index after accounting for visible capacity.
    max_offset: usize,
};
/// Compute a bounded visible-row window and clamp the requested scroll offset.
pub fn virtualWindow(count: usize, height: ?i64, row_height: i64, offset: i64) VirtualWindow {
    const step = @max(1, row_height);
    const capacity = if (height) |h| std.math.cast(usize, @max(1, @divTrunc(h, step))) orelse std.math.maxInt(usize) else count;
    const max_offset = count -| capacity;
    const off = @min(std.math.cast(usize, @max(0, offset)) orelse std.math.maxInt(usize), max_offset);
    return .{ .offset = off, .end = @min(count, off +| capacity), .capacity = capacity, .max_offset = max_offset };
}
/// Return a list that renders only the visible rows with stable caller identities.
pub fn VirtualizedList(comptime Item: type, comptime View: type) type {
    return struct {
        /// Borrowed item slice; retained only for the render call.
        data: []const Item,

        /// Cell height used to estimate visible capacity; values below one are treated as one.
        row_height: i64 = 1,

        /// Stable item identity used for state scopes, independent of visible position.
        identity: *const fn (Item) NodeID,

        /// Produce a view for each visible item; called synchronously during render.
        content: *const fn (Item) View,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            const offset = try ctx.offset(); // Host binds state even for a disabled list.
            const window = virtualWindow(self.data.len, if (ctx.surface_size) |size| size.height else null, self.row_height, offset);
            if (ctx.environment.enabled) try ctx.register(.{ .virtual_list = .{ .id = ctx.id, .capacity = window.capacity, .max_offset = window.max_offset } });
            const nodes = try ctx.allocator.alloc(Node, window.end - window.offset);
            for (self.data[window.offset..window.end], 0..) |item, i| {
                var sub = ctx.scoped(self.identity(item));
                nodes[i] = try comp.render(self.content(item), &sub);
            }
            return .{ .interactive = .{ .id = ctx.id, .focusable = ctx.environment.enabled, .child = try ctx.box(.{ .stack = .{ .axis = .vertical, .alignment = .top_leading, .children = nodes } }) } };
        }
    };
}
/// Return a semantic native-region marker with a portable fallback; retained adapters render the fallback.
pub fn NativeRegion(comptime T: type) type {
    return struct {
        /// Portable component rendered even when no native region adapter exists.
        fallback: T,

        /// Borrowed UTF-8 region name copied into the frame registration.
        region_id: []const u8,

        /// Whether the interaction may participate in focus traversal.
        focusable: bool = true,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            try ctx.register(.{ .native_region = .{ .id = ctx.id, .region_id = self.region_id } });
            var sub = ctx.child(0);
            const wrapped = flexFrame(self.fallback, .{ .max_width = std.math.maxInt(i64), .max_height = std.math.maxInt(i64) });
            return .{ .interactive = .{ .id = ctx.id, .focusable = self.focusable and ctx.environment.enabled, .child = try ctx.box(try wrapped.render(&sub)) } };
        }
    };
}
/// Optional fixed cell dimensions and alignment within the resulting frame.
pub const FrameOptions = struct {
    /// Fixed width in cells, or null to retain the child's measured width.
    width: ?i64 = null,
    /// Fixed height in cells, or null to retain the child's measured height.
    height: ?i64 = null,
    /// Placement rule used when the allocated extent exceeds intrinsic content size.
    alignment: geo.Alignment = .center,
};
/// Optional per-axis minimum/maximum cell constraints and child alignment.
pub const FlexOptions = struct {
    /// Minimum width constraint; null leaves the minimum unspecified.
    min_width: ?i64 = null,
    /// Maximum width constraint; maxInt(i64) opts into horizontal flexibility.
    max_width: ?i64 = null,
    /// Minimum height constraint; null leaves the minimum unspecified.
    min_height: ?i64 = null,
    /// Maximum height constraint; maxInt(i64) opts into vertical flexibility.
    max_height: ?i64 = null,
    /// Placement rule used when the allocated extent exceeds intrinsic content size.
    alignment: geo.Alignment = .center,
};
/// Border glyph selection, foreground color and optional borrowed title.
pub const BorderOptions = struct {
    /// Built-in box glyph set used for the border.
    style: s.BorderStyle = .single,
    /// Color of this drawing or decoration operation.
    color: s.Color = .default,
    /// Borrowed UTF-8 title copied into frame storage when rendered.
    title: ?[]const u8 = null,
};
/// One layout or paint wrapper applied around a component.
pub const Modifier = union(enum) {
    /// Inset the child by the supplied edge cell counts.
    padding: geo.EdgeInsets,
    /// Surround the child with a styled border and optional title.
    border: BorderOptions,
    /// Apply optional fixed dimensions and align the child within them.
    frame: FrameOptions,
    /// Apply independent minimum/maximum constraints on each axis.
    flex_frame: FlexOptions,
    /// Merge these properties into inherited and painted text style.
    style: s.TextStyle,
    /// Fill the child rectangle with this background color before painting content.
    background: s.Color,
};
/// Return a typed wrapper that applies one layout or style modifier.
pub fn Modified(comptime T: type) type {
    return struct {
        /// Child component value wrapped by modifier during render.
        content: T,

        /// Wrapper operation applied after rendering content; style also affects inherited style.
        modifier: Modifier,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            var sub = ctx.child(0);
            if (self.modifier == .style) sub.inherited_style = ctx.inherited_style.merging(self.modifier.style);
            const child = try ctx.box(try comp.render(self.content, &sub));
            return switch (self.modifier) {
                .padding => |v| .{ .padding = .{ .insets = v, .child = child } },
                .border => |v| .{ .border = .{ .style = v.style, .text_style = .{ .foreground = v.color }, .title = if (v.title) |t| try ctx.copyText(t) else null, .child = child } },
                .frame => |v| .{ .frame = .{ .width = v.width, .height = v.height, .alignment = v.alignment, .child = child } },
                .flex_frame => |v| .{ .flex_frame = .{ .min_width = v.min_width, .max_width = v.max_width, .min_height = v.min_height, .max_height = v.max_height, .alignment = v.alignment, .child = child } },
                .style => |v| .{ .styled = .{ .style = v, .child = child } },
                .background => |v| .{ .background = .{ .color = v, .child = child } },
            };
        }
    };
}
/// Apply explicit edge insets in cells.
pub fn padding(content: anytype, insets: geo.EdgeInsets) Modified(@TypeOf(content)) {
    return .{ .content = content, .modifier = .{ .padding = insets } };
}
/// Apply equal cell padding on every edge.
pub fn paddingAll(content: anytype, amount: i64) Modified(@TypeOf(content)) {
    return padding(content, .{ .top = amount, .leading = amount, .bottom = amount, .trailing = amount });
}
/// Reserve one cell per edge and paint the selected border/title.
pub fn border(content: anytype, options: BorderOptions) Modified(@TypeOf(content)) {
    return .{ .content = content, .modifier = .{ .border = options } };
}
/// Wrap content with fixed-frame options by value; allocation and node construction occur during render.
pub fn frame(content: anytype, options: FrameOptions) Modified(@TypeOf(content)) {
    return .{ .content = content, .modifier = .{ .frame = options } };
}
/// Apply per-axis minimum/maximum bounds and content alignment.
pub fn flexFrame(content: anytype, options: FlexOptions) Modified(@TypeOf(content)) {
    return .{ .content = content, .modifier = .{ .flex_frame = options } };
}
/// Merge a text-style modifier into the child rendering environment.
pub fn styled(content: anytype, style: s.TextStyle) Modified(@TypeOf(content)) {
    return .{ .content = content, .modifier = .{ .style = style } };
}
/// Apply a foreground color without changing child layout.
pub fn foregroundColor(content: anytype, color: s.Color) Modified(@TypeOf(content)) {
    return styled(content, .{ .foreground = color });
}
/// Apply background color to the wrapper extent before painting children.
pub fn background(content: anytype, color: s.Color) Modified(@TypeOf(content)) {
    return .{ .content = content, .modifier = .{ .background = color } };
}
/// Environment change applied to a copied child context.
pub const EnvChange = union(enum) {
    /// True disables child interaction; false explicitly enables it.
    disabled: bool,
    /// Action name/shortcut inherited by child registrations.
    action_identity: c.ActionIdentity,
    /// Synchronous callback modifying only the copied child environment.
    transform: *const fn (*c.Environment) void,
};
/// Return a typed environment-transforming wrapper.
pub fn EnvironmentView(comptime T: type) type {
    return struct {
        /// Child component value rendered with the modified environment.
        content: T,

        /// Environment update applied before rendering content.
        change: EnvChange,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            var sub = ctx.*;
            switch (self.change) {
                .disabled => |v| sub.environment.enabled = !v,
                .action_identity => |v| sub.environment.action_identity = v,
                .transform => |f| f(&sub.environment),
            }
            return comp.render(self.content, &sub);
        }
    };
}
/// Disable interaction registration while retaining rendered content.
pub fn disabled(content: anytype, flag: bool) EnvironmentView(@TypeOf(content)) {
    return .{ .content = content, .change = .{ .disabled = flag } };
}
/// Attach a named action identity and optional shortcut to descendant registration.
pub fn actionIdentity(content: anytype, identity: c.ActionIdentity) EnvironmentView(@TypeOf(content)) {
    return .{ .content = content, .change = .{ .action_identity = identity } };
}
/// Apply the supplied environment transform before rendering the child.
pub fn environment(content: anytype, transform: *const fn (*c.Environment) void) EnvironmentView(@TypeOf(content)) {
    return .{ .content = content, .change = .{ .transform = transform } };
}
/// Retained adapters expose only their fixed primary surface; native window actions are unavailable.
pub const WindowContext = c.WindowContext;
/// Build content from the current retained scene context.
pub fn WindowContextReader(comptime T: type) type {
    return struct {
        /// Produce a component from the current copied window context.
        content: *const fn (WindowContext) T,

        /// Lower this component into frame-owned nodes using the supplied build context.
        pub fn render(self: *const @This(), ctx: *c.BuildContext) c.Error!Node {
            var sub = ctx.child(0);
            return comp.render(self.content(ctx.environment.window_context), &sub);
        }
    };
}
