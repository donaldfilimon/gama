//! Artifact-only probe: force the portable API to be analyzed in freestanding builds.
const gama = @import("gama");

export fn gama_cell_admission_probe(width: u32, height: u32) u32 {
    return @intCast(gama.checkedCellCount(width, height) catch return 0xffff_ffff);
}

export fn gama_identity_probe(index: i64) u64 {
    return gama.NodeID.root.child(index).raw;
}
export fn gama_geometry_probe(origin: i64, size: i64, inset: i64) i64 {
    const rect: gama.geometry.Rect = .{ .origin = .{ .x = origin }, .size = .{ .width = size } };
    return rect.inset(.{ .leading = inset, .trailing = inset }).maxX();
}
export fn gama_grapheme_probe(bytes: [*]const u8, len: u32) u32 {
    return @intCast(gama.unicode.count(bytes[0..len]) catch return 0xffff_ffff);
}
export fn gama_width_probe(bytes: [*]const u8, len: u32) i64 {
    return gama.text.displayWidth(bytes[0..len]) catch return -1;
}
export fn gama_edit_probe() i64 {
    const std = @import("std");
    var buffer: [64]u8 = undefined;
    var arena = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = arena.allocator();
    var edit = gama.text.insert(allocator, "e", .{ .anchor = 1, .head = 1 }, "\u{301}") catch return -1;
    defer edit.deinit(allocator);
    var wrapped = gama.text.wrap(allocator, edit.value, 1) catch return -2;
    defer wrapped.deinit(allocator);
    const lower = gama.unicode.lowercased(allocator, "İ") catch return -3;
    defer allocator.free(lower);
    return edit.selection.head;
}

export fn gama_authoring_probe() u64 {
    const std = @import("std");
    var bytes: [8192]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&bytes);
    var frame = gama.FrameStorage.init(fixed.allocator());
    defer frame.deinit();
    var ctx = frame.context();
    const a = gama.authoring;
    const component = a.vStack(a.tuple(.{
        a.foregroundColor(a.Text{ .content = "portable" }, comptime gama.rgb("#F80")),
        a.Progress{ .value = 0.5, .width = 1 },
        a.NativeRegion(a.Spacer){ .region_id = "fallback", .fallback = .{} },
    }), .{});
    const node = a.render(component, &ctx) catch return 0;
    const copy = ctx.retain(node) catch return 0;
    return @as(u64, copy.stack.children.len) + copy.stack.children[2].flexPriority(.horizontal);
}

const ProbeApp = struct {
    value: ?gama.StateRef(i64) = null,
    owner: ?*gama.Host(@This()) = null,
    pub const scenes = [_]gama.scenes.Descriptor(@This()){.{ .id = "probe", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *gama.BuildContext) gama.Error!gama.Node {
        if (self.owner) |owner| {
            owner.invalidate() catch |err| {
                if (err != error.Reentrant) return err;
            };
        }
        self.value = try ctx.state(i64, 1, 9);
        const children = try ctx.allocator.alloc(gama.Node, 2);
        children[0] = .{ .text = .{ .content = "core" } };
        children[1] = .{ .interactive = .{ .id = ctx.id.child(1), .focusable = true, .child = try ctx.box(.{ .spacer = 1 }) } };
        return .{ .stack = .{ .axis = .horizontal, .spacing = 1, .alignment = .top_leading, .children = children } };
    }
};
export fn gama_host_probe() i64 {
    const std = @import("std");
    var bytes: [16384]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&bytes);
    var app: ProbeApp = .{};
    const host = gama.Host(ProbeApp).create(fixed.allocator(), &app) catch return -1;
    defer host.destroy() catch {};
    app.owner = host;
    host.rebuild(.{}) catch return -2;
    app.value.?.set(13) catch return -3;
    host.invalidate() catch return -4;
    const candidate = (host.prepare(.{}) catch return -5) orelse return -6;
    candidate.abort() catch return -7;
    const signal = gama.Signal(i64).create(fixed.allocator(), 0) catch return -8;
    defer signal.destroy() catch {};
    host.observe(signal) catch return -9;
    defer host.cancelAll() catch {};
    const bridge = host.bind(signal.reference() catch return -13) catch return -14;
    bridge.set(1) catch return -10;
    _ = bridge.read() catch return -15;
    host.handle(.tick) catch return -11;
    return (app.value.?.read() catch return -12).*;
}

fn prepareProbe(_: void, prep: gama.Host(ProbeApp).Preparation) gama.Error![]const u8 {
    const bytes = try prep.allocator.alloc(u8, 2);
    bytes[0] = @intCast(@max(0, @min(255, prep.tree.frame.size.width)));
    bytes[1] = @intCast(@max(0, @min(255, prep.tree.frame.size.height)));
    return bytes;
}
/// Real core+pump instantiation using bounded caller-owned storage, no hosted allocator.
export fn gama_pump_probe(memory: [*]u8, length: u32) i64 {
    const std = @import("std");
    var fixed = std.heap.FixedBufferAllocator.init(memory[0..length]);
    var app: ProbeApp = .{};
    const host = gama.Host(ProbeApp).create(fixed.allocator(), &app) catch return -1;
    defer host.destroy() catch {};
    const pump: gama.HostPump(ProbeApp) = .{ .host = host };
    pump.handle(.{ .resize = .{ .width = 10, .height = 3 } }) catch return -2;
    const first = pump.advance({}, prepareProbe) catch return -3;
    if (!first.produced) return -4;
    pump.handle(.{ .pointer = .{ .x = 1, .y = 1 } }) catch return -5;
    pump.handle(.{ .key = .right }) catch return -6;
    const tree = (host.currentTree() catch return -7) orelse return -8;
    return tree.frame.size.width;
}

/// Instantiates actual owned raster, painting, serializers, codec and presenters.
/// Caller storage bounds every allocation; this remains relocatable-object proof.
export fn gama_drawing_probe(memory: [*]u8, length: u32) i64 {
    const std = @import("std");
    var fixed = std.heap.FixedBufferAllocator.init(memory[0..length]);
    const a = fixed.allocator();
    var app: ProbeApp = .{};
    const host = gama.Host(ProbeApp).create(a, &app) catch return -1;
    defer host.destroy() catch {};
    host.handle(.{ .resize = .{ .width = 10, .height = 3 } }) catch return -2;
    var adapter = gama.DrawingPump(ProbeApp).init(a, host, .draw_list) catch return -3;
    defer adapter.deinit();
    _ = adapter.advance() catch return -4;
    var list = gama.draw.DrawList.decode(a, host.currentOutput() catch return -5) catch return -6;
    defer list.deinit();
    const html = gama.draw.HTMLSerializer.serialize(a, &adapter.buffer) catch return -7;
    defer a.free(html);
    const ansi = gama.draw.AnsiPresenter.prepare(a, &adapter.buffer) catch return -8;
    defer a.free(ansi);
    var plain = gama.draw.StreamPresenter.prepare(a, &adapter.buffer) catch return -9;
    defer plain.deinit(a);
    gama.draw.AnsiPresenter.promote(&adapter.buffer);
    return @intCast(list.commands.len + html.len + ansi.len + plain.items.len);
}

const PortablePlugin = struct {
    required: bool,
    pub fn manifest(self: *PortablePlugin) gama.plugins.Manifest {
        return .{ .id = "portable", .requires = if (self.required) &.{.clock} else &.{} };
    }
    pub fn activate(_: *PortablePlugin, _: gama.plugins.Context) gama.Error!void {}
    pub fn render(_: *PortablePlugin, _: []const u8, context: gama.plugins.Context, build: *gama.BuildContext) gama.Error!gama.Node {
        try context.invalidate();
        return .{ .text = .{ .content = try build.copyText("plugin") } };
    }
};
/// Emitted reachable unavailable-service path and static lifecycle, no hosted services.
export fn gama_plugin_probe(required: bool) i32 {
    const std = @import("std");
    var bytes: [32768]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&bytes);
    const runtime = gama.PluginRuntime.create(fixed.allocator(), .{ .entries = &.{.{ .id = "portable", .capabilities = &.{.clock} }} }, .{}) catch return -1;
    defer runtime.destroy() catch {};
    runtime.install(PortablePlugin{ .required = required }) catch |err| return if (err == error.ServiceUnavailable) -2 else -3;
    var frame = gama.FrameStorage.init(fixed.allocator());
    defer frame.deinit();
    var ctx = frame.context();
    const node = runtime.render("slot", &ctx) catch return -4;
    runtime.uninstall("portable") catch return -5;
    return @intCast(node.group.len);
}
