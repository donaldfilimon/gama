const std = @import("std");
const g = @import("gama");
const a = g.authoring;
test "progress exact baseline IR" {
    var frame = g.FrameStorage.init(std.testing.allocator);
    defer frame.deinit();
    var context = frame.context();
    const node = try (a.Progress{ .value = 0.5, .width = 1 }).render(&context);
    try std.testing.expectEqualStrings("[▌] 50%", node.text.content);
}
test "scene requires primary" {
    try std.testing.expectError(error.MissingPrimaryScene, g.scenes.validate(App, &.{}));
}

const Node = g.Node;
const Context = g.BuildContext;
const Error = g.Error;
const Token = g.context.BindingToken;
const binding: Token = .{ .owner = 1, .index = 2, .generation = 3 };
const Probe = struct {
    pub fn render(_: *const Probe, ctx: *Context) Error!Node {
        return .{ .interactive = .{ .id = ctx.id, .focusable = ctx.environment.enabled, .child = try ctx.box(.empty) } };
    }
};
const Recorder = struct {
    items: [32]g.context.Registration = undefined,
    count: usize = 0,
    offset_value: i64 = 0,
    offset_calls: usize = 0,
    last_offset_id: g.NodeID = .root,
    sum: u64 = 0,
    fn register(raw: *anyopaque, value: g.context.Registration) Error!void {
        const self: *Recorder = @ptrCast(@alignCast(raw));
        self.items[self.count] = value;
        self.count += 1;
    }
    fn offset(raw: *anyopaque, id: g.NodeID, slot: u32) Error!i64 {
        const self: *Recorder = @ptrCast(@alignCast(raw));
        self.offset_calls += 1;
        self.last_offset_id = id;
        if (slot != 0) return error.InvalidHandle;
        return self.offset_value;
    }
    fn hooks(self: *Recorder) g.context.Hooks {
        return .{ .host = self, .register_fn = register, .offset_fn = offset };
    }
};
fn add(capture: *const u64, raw: *anyopaque) Error!void {
    const host: *Recorder = @ptrCast(@alignCast(raw));
    host.sum += capture.*;
}
fn emptyScene(_: *struct {}, _: *Context) Error!Node {
    return .empty;
}

test "palette rgb attributes style and border baseline" {
    try std.testing.expect(!std.meta.eql(g.Color.default, g.Color.black));
    try std.testing.expectEqual(g.Color.init(255, 136, 0), g.rgb("#F80"));
    try std.testing.expectEqual(g.Color.init(18, 171, 239), comptime g.rgb("12ABef"));
    const style = (g.TextStyle{ .foreground = .red, .attributes = 1 }).merging(.{ .background = .blue, .attributes = 62 });
    try std.testing.expectEqual(g.Color.red, style.foreground);
    try std.testing.expectEqual(@as(u8, 63), style.attributes);
    try std.testing.expectEqual(@as(u8, 16), g.Color.black.xterm256());
    try std.testing.expectEqual(@as(u8, 231), g.Color.white.xterm256());
    try std.testing.expectEqual(@as(i64, 7), try g.style.borderTitleWidth("abc"));
    try std.testing.expectEqual(@as(i64, 0), try g.style.borderTitleWidth(""));
    const families = [_]g.style.BorderStyle{ .single, .double, .rounded, .heavy, .ascii };
    const corners = [_][]const u8{ "┌", "╔", "╭", "┏", "+" };
    for (families, corners) |family, corner| try std.testing.expectEqualStrings(corner, family.glyphs().top_left);
}
test "tuple branches state scope and flatten identity trace" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    const branch: a.Branch(Probe, Probe) = .{ .value = .{ .second = .{} } };
    const tree = a.tuple(.{ Probe{}, branch, a.stateScope(Probe{}, .{ .raw = 99 }) });
    const node = try a.render(tree, &ctx);
    try std.testing.expectEqual(g.NodeID.root.child(0), node.group[0].interactive.id);
    try std.testing.expectEqual(g.NodeID.root.child(1).child(1), node.group[1].interactive.id);
    try std.testing.expectEqual(@as(u64, 99), node.group[2].interactive.id.raw);
    const stack = try a.render(a.vStack(a.tuple(.{ a.Empty{}, a.tuple(.{ Probe{}, a.Empty{} }), a.zStack(a.Empty{}, .center) }), .{}), &ctx);
    try std.testing.expectEqual(@as(usize, 2), stack.stack.children.len);
    try std.testing.expectEqual(g.NodeID.root.child(0).child(1).child(0), stack.stack.children[0].interactive.id);
    try std.testing.expect(stack.stack.children[1] == .overlay);
    try std.testing.expectEqual(@as(usize, 0), stack.stack.children[1].overlay.children.len);
    const optional: a.Branch(Probe, a.Empty) = .{ .value = .{ .second = .{} } };
    try std.testing.expect((try optional.render(&ctx)) == .empty);
}
fn probeFor(_: i64) Probe {
    return .{};
}
fn itemID(item: i64) g.NodeID {
    return .{ .raw = @intCast(item) };
}
test "collections use actual index explicit identity and enumerate views" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var collection: a.ForEach(i64, Probe) = .{ .data = &.{ 5, 8 }, .start_index = 7, .content = probeFor };
    var node = try collection.render(&ctx);
    try std.testing.expectEqual(g.NodeID.root.child(7), node.group[0].interactive.id);
    try std.testing.expectEqual(g.NodeID.root.child(8), node.group[1].interactive.id);
    collection.start_index = std.math.maxInt(i64);
    collection.identity = itemID;
    node = try collection.render(&ctx);
    try std.testing.expectEqual(@as(u64, 5), node.group[0].interactive.id.raw);
    try std.testing.expectEqual(@as(u64, 8), node.group[1].interactive.id.raw);
    collection.identity = null;
    collection.start_index = std.math.maxInt(i64);
    try std.testing.expectError(error.CollectionTooLarge, collection.render(&ctx));
    const views: a.Views(Probe) = .{ .values = &.{ .{}, .{} } };
    node = try views.render(&ctx);
    try std.testing.expectEqual(g.NodeID.root.child(1), node.group[1].interactive.id);
}
test "visual modifiers descend while environments preserve identity and nearest wins" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var node = try a.render(a.disabled(a.disabled(Probe{}, false), true), &ctx);
    try std.testing.expectEqual(g.NodeID.root, node.interactive.id);
    try std.testing.expect(node.interactive.focusable);
    node = try a.render(a.paddingAll(a.border(a.frame(a.flexFrame(Probe{}, .{ .max_width = std.math.maxInt(i64) }), .{ .width = -2 }), .{}), 1), &ctx);
    try std.testing.expectEqual(g.NodeID.root.child(0).child(0).child(0).child(0), node.padding.child.border.child.frame.child.flex_frame.child.interactive.id);
    try std.testing.expectEqual(@as(?i64, -2), node.padding.child.border.child.frame.width);
    try std.testing.expectEqual(@as(u8, 0), node.flexPriority(.horizontal));
    try std.testing.expectEqual(@as(u8, 1), node.padding.child.border.child.frame.child.flexPriority(.horizontal));
    try std.testing.expectEqual(@as(u8, 0), node.padding.child.border.child.frame.child.flexPriority(.vertical));
}
test "stack list overlay spacer divider defaults and style cascade IR" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    const h = try a.render(a.hStack(a.Text{ .content = "a" }, .{}), &ctx);
    try std.testing.expectEqual(g.geometry.Axis.horizontal, h.stack.axis);
    try std.testing.expectEqual(g.geometry.Alignment{ .horizontal = .leading, .vertical = .center }, h.stack.alignment);
    const l = try a.render(a.list(a.Text{ .content = "b" }), &ctx);
    try std.testing.expectEqual(g.geometry.Alignment.top_leading, l.stack.alignment);
    const v = try a.render(a.vStack(a.Empty{}, .{}), &ctx);
    try std.testing.expectEqual(@as(i64, 0), v.stack.spacing);
    try std.testing.expectEqual(g.geometry.Alignment.top_leading, v.stack.alignment);
    try std.testing.expectEqual(@as(i64, 0), (try (a.Spacer{}).render(&ctx)).spacer);
    ctx.inherited_style = .{ .foreground = .red };
    const divider = try (a.Divider{}).render(&ctx);
    try std.testing.expectEqual(g.Color.gray, divider.divider.style.foreground);
    try std.testing.expectEqual(@as(?g.geometry.Axis, null), divider.divider.axis);
    const text = (a.Text{ .content = "hello" }).bold().italic().underline();
    const styled = try a.render(a.styled(a.foregroundColor(text, .blue), .{ .foreground = .green }), &ctx);
    try std.testing.expectEqual(g.Color.green, styled.styled.style.foreground);
    try std.testing.expectEqual(g.Color.blue, styled.styled.child.styled.child.text.style.foreground);
    try std.testing.expectEqual(@as(u8, 13), styled.styled.child.styled.child.text.style.attributes);
    const bg = try a.render(a.background(Probe{}, .yellow), &ctx);
    try std.testing.expectEqual(g.Color.yellow, bg.background.color);
    try std.testing.expectEqual(g.NodeID.root.child(0), bg.background.child.interactive.id);
}
test "button registrations captures labels disabled focus and named identity" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var recorder: Recorder = .{};
    ctx.hooks = recorder.hooks();
    ctx.focus = ctx.id;
    var captured: u64 = 7;
    const action = try ctx.action(captured, add);
    captured = 99;
    var name = [_]u8{ 's', 'a', 'v', 'e' };
    const button = try a.buttonTitle(&ctx, "OK", action);
    const named = a.actionIdentity(a.actionIdentity(button, .{ .id = &name, .shortcut = .{ .codepoint = 's' } }), .{ .id = "outer" });
    const node = try a.render(named, &ctx);
    name[0] = 'X';
    try std.testing.expectEqual(@as(usize, 1), recorder.count);
    try std.testing.expectEqualStrings("save", recorder.items[0].action.identity.?.id);
    try std.testing.expectEqual(g.NodeID.root, recorder.items[0].action.id);
    try recorder.items[0].action.action.invoke(&recorder);
    try std.testing.expectEqual(@as(u64, 7), recorder.sum);
    try std.testing.expectEqualStrings(" OK ", node.interactive.child.styled.child.text.content);
    try std.testing.expectEqual(g.Color.cyan, node.interactive.child.styled.style.background);
    try std.testing.expectEqual(g.Color.black, node.interactive.child.styled.style.foreground);
    const off = try a.render(a.disabled(button, true), &ctx);
    try std.testing.expectEqual(@as(usize, 1), recorder.count);
    try std.testing.expect(!off.interactive.focusable);
    try std.testing.expectEqual(g.Color.gray, off.interactive.child.styled.style.foreground);
}
test "text field snapshot and toggle preserve synthetic IR and host requests" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var recorder: Recorder = .{};
    ctx.hooks = recorder.hooks();
    ctx.inherited_style = .{ .foreground = .red };
    ctx.environment.action_identity = .{ .id = "ignored-by-field" };
    const field: a.TextField = .{ .value = "", .placeholder = "Name", .binding = binding };
    const node = try field.render(&ctx);
    try std.testing.expectEqualStrings(" Name ", node.interactive.child.styled.child.text.content);
    try std.testing.expectEqual(g.TextStyle.plain, node.interactive.child.styled.child.text.style);
    try std.testing.expectEqual(g.style.Attributes.dim, node.interactive.child.styled.style.attributes);
    try std.testing.expectEqual(binding, recorder.items[0].text_field.binding);
    try std.testing.expectEqual(@as(u32, 0), recorder.items[0].text_field.cursor_slot);
    const toggle: a.Checkbox = .{ .title = "Check", .value = true, .binding = binding };
    const t = try toggle.render(&ctx);
    try std.testing.expectEqualStrings("[x] Check", t.interactive.child.styled.child.text.content);
    try std.testing.expectEqualStrings("ignored-by-field", recorder.items[1].toggle.identity.?.id);
    const off = try a.render(a.disabled(field, true), &ctx);
    try std.testing.expectEqual(@as(usize, 2), recorder.count);
    try std.testing.expect(!off.interactive.focusable);
}
test "progress special fractions exact strings and bounded width" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    const cases = [_]struct { p: a.Progress, expected: []const u8 }{
        .{ .p = .{ .value = 0.99 }, .expected = "[███████████████████▊] 99%" },
        .{ .p = .{ .value = 0.5, .width = 0 }, .expected = "[] 50%" },
        .{ .p = .{ .value = 0.999999, .width = 1 }, .expected = "[▉] 99%" },
        .{ .p = .{ .value = std.math.nan(f64), .width = 1 }, .expected = "[░] 0%" },
        .{ .p = .{ .value = std.math.inf(f64), .width = 1 }, .expected = "[█] 100%" },
        .{ .p = .{ .value = 1, .total = 0, .width = 1 }, .expected = "[░] 0%" },
        .{ .p = .{ .value = 1, .width = -1, .label = "" }, .expected = " [] 100%" },
        .{ .p = .{ .value = 0, .width = 1, .label = "Load" }, .expected = "Load [░] 0%" },
    };
    for (cases) |case| try std.testing.expectEqualStrings(case.expected, (try case.p.render(&ctx)).text.content);
    const max = try (a.Progress{ .value = 1, .width = std.math.maxInt(i64) }).render(&ctx);
    try std.testing.expectEqual(@as(usize, 4096 * 3 + 7), max.text.content.len);
}
const Row = @TypeOf(a.tuple(.{ Probe{}, Probe{} }));
fn groupedRow(_: i64) Row {
    return a.tuple(.{ Probe{}, Probe{} });
}
test "virtualized rows bind disabled state and do not flatten" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var recorder: Recorder = .{ .offset_value = 99 };
    ctx.hooks = recorder.hooks();
    ctx.surface_size = .{ .width = 20, .height = 4 };
    const view: a.VirtualizedList(i64, Row) = .{ .data = &.{ 10, 11, 12, 13, 14 }, .row_height = 2, .identity = itemID, .content = groupedRow };
    const node = try view.render(&ctx);
    try std.testing.expectEqual(@as(usize, 1), recorder.offset_calls);
    try std.testing.expectEqual(@as(usize, 2), recorder.items[0].virtual_list.capacity);
    try std.testing.expectEqual(@as(usize, 3), recorder.items[0].virtual_list.max_offset);
    const rows = node.interactive.child.stack.children;
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual((g.NodeID{ .raw = 13 }).child(0), rows[0].group[0].interactive.id);
    try std.testing.expectEqual((g.NodeID{ .raw = 14 }).child(1), rows[1].group[1].interactive.id);
    _ = try a.render(a.disabled(view, true), &ctx);
    try std.testing.expectEqual(@as(usize, 2), recorder.offset_calls);
    try std.testing.expectEqual(@as(usize, 1), recorder.count);
    try std.testing.expectEqual(a.VirtualWindow{ .offset = 0, .end = 0, .capacity = 0, .max_offset = 0 }, a.virtualWindow(0, null, 0, 9));
    try std.testing.expectEqual(@as(usize, 1), a.virtualWindow(5, -99, -1, -1).capacity);
    try std.testing.expectEqual(@as(usize, 5), a.virtualWindow(5, null, 1, 9).end);
}
test "native fallback registers disabled and descends through greedy frame" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var recorder: Recorder = .{};
    ctx.hooks = recorder.hooks();
    var region = [_]u8{'r'};
    const view: a.NativeRegion(Probe) = .{ .fallback = .{}, .region_id = &region };
    const node = try a.render(a.disabled(view, true), &ctx);
    region[0] = 'x';
    try std.testing.expectEqualStrings("r", recorder.items[0].native_region.region_id);
    try std.testing.expect(!node.interactive.focusable);
    try std.testing.expectEqual(g.NodeID.root.child(0).child(0), node.interactive.child.flex_frame.child.interactive.id);
    try std.testing.expectEqual(@as(u8, 1), node.flexPriority(.horizontal));
    try std.testing.expectEqual(@as(u8, 1), node.flexPriority(.vertical));
}
fn windowProbe(window: a.WindowContext) Probe {
    std.debug.assert(!window.open("aux") and !window.dismiss());
    std.debug.assert(window.instance_id == 42);
    return .{};
}
test "window reader uses fixed unavailable operations and child identity" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    ctx.environment.window_context.instance_id = 42;
    const reader: a.WindowContextReader(Probe) = .{ .content = windowProbe };
    try std.testing.expectEqual(g.NodeID.root.child(0), (try reader.render(&ctx)).interactive.id);
}
const App = struct {
    renders: usize = 0,
    fn scene(self: *App, ctx: *Context) Error!Node {
        self.renders += 1;
        return (Probe{}).render(ctx);
    }
};
const Scene = g.scenes.Descriptor(App);
test "scene validation order primary selection and launch payload presence" {
    const aux: Scene = .{ .id = "aux", .render = App.scene };
    const main: Scene = .{ .id = "main", .role = .primary, .render = App.scene };
    try std.testing.expectEqual(@as(usize, 1), try g.scenes.validate(App, &.{ aux, main }));
    try std.testing.expectError(error.DuplicateSceneID, g.scenes.validate(App, &.{ aux, aux }));
    var other = main;
    other.id = "other";
    try std.testing.expectError(error.MultiplePrimaryScenes, g.scenes.validate(App, &.{ main, other }));
    other.initial_payload = .absent;
    try std.testing.expectError(error.MissingInitialPayload, g.scenes.validate(App, &.{ main, other }));
    other.initial_payload = .present;
    try std.testing.expectEqual(@as(usize, 0), try g.scenes.validate(App, &.{other}));
    var group = aux;
    group.initial_payload = .absent;
    try std.testing.expectEqual(@as(usize, 0), try g.scenes.validate(App, &.{ main, group }));
    group.launch = .open_at_launch;
    try std.testing.expectError(error.MissingInitialPayload, g.scenes.validate(App, &.{ main, group }));
    try std.testing.expectEqual(g.scenes.Launch.on_demand, aux.resolvedLaunch());
    try std.testing.expectEqual(g.scenes.Launch.open_at_launch, main.resolvedLaunch());
    other.launch = .on_demand;
    other.initial_payload = .absent;
    try std.testing.expectError(error.MissingInitialPayload, g.scenes.validate(App, &.{other}));
}
test "compiled scenes copy declarations and reevaluate content without identity descent" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var app: App = .{};
    var name = [_]u8{'m'};
    const main: Scene = .{ .id = &name, .role = .primary, .render = App.scene };
    const optional: ?Scene = null;
    const descriptors = try g.scenes.collect(App, std.testing.allocator, .{ optional, main });
    defer std.testing.allocator.free(descriptors);
    var graph = try g.scenes.Graph(App).init(std.testing.allocator, descriptors);
    defer graph.deinit();
    name[0] = 'X';
    try std.testing.expectEqualStrings("m", graph.descriptors[0].id);
    try std.testing.expectEqual(g.NodeID.root, (try graph.renderPrimary(&app, &ctx)).interactive.id);
    _ = try graph.renderPrimary(&app, &ctx);
    try std.testing.expectEqual(@as(usize, 2), app.renders);
}
test "frame owns borrowed text children titles and action captures" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var bytes = [_]u8{ 'o', 'k' };
    var title = [_]u8{'t'};
    var child: Node = .{ .text = .{ .content = &bytes } };
    var children = [_]Node{child};
    const group: Node = .{ .group = &children };
    const outer: Node = .{ .border = .{ .title = &title, .child = &group } };
    const owned = try ctx.retain(outer);
    bytes[0] = 'X';
    title[0] = 'X';
    child = .empty;
    children[0] = .empty;
    try std.testing.expectEqualStrings("ok", owned.border.child.group[0].text.content);
    try std.testing.expectEqualStrings("t", owned.border.title.?);
    try std.testing.expectError(error.InvalidUtf8, (a.Text{ .content = "\xff" }).render(&ctx));
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var storage = g.FrameStorage.init(allocator);
    defer storage.deinit();
    var ctx = storage.context();
    const act = try ctx.action(@as(u64, 4), add);
    const button = try a.buttonTitle(&ctx, "a", act);
    var recorder: Recorder = .{};
    ctx.hooks = recorder.hooks();
    const content = a.vStack(a.tuple(.{ a.actionIdentity(button, .{ .id = "named" }), a.Progress{ .value = 0.99 }, a.border(a.Text{ .content = "large enough owned title" }, .{ .title = "border" }) }), .{});
    _ = try a.render(content, &ctx);
    _ = try ctx.retain(try a.render(content, &ctx));
    const scenes = [_]Scene{ .{ .id = "primary", .role = .primary, .render = App.scene }, .{ .id = "aux", .render = App.scene } };
    var graph = try g.scenes.Graph(App).init(allocator, &scenes);
    defer graph.deinit();
}
test "every allocation failure releases candidate storage and graph" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
test "copied contexts preserve whole-surface environment hooks and focused identity" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var recorder: Recorder = .{};
    ctx.hooks = recorder.hooks();
    ctx.focus = .{ .raw = 13 };
    ctx.surface_size = .{ .width = 80, .height = 24 };
    ctx.environment = .{ .enabled = false, .action_identity = .{ .id = "copy" } };
    ctx.inherited_style = .{ .foreground = .red };
    const child = ctx.child(-1);
    try std.testing.expectEqual(ctx.surface_size, child.surface_size);
    try std.testing.expectEqual(ctx.focus, child.focus);
    try std.testing.expectEqual(ctx.hooks.host, child.hooks.host);
    try std.testing.expectEqual(ctx.inherited_style, child.inherited_style);
    try std.testing.expectEqualStrings("copy", child.environment.action_identity.?.id);
    try std.testing.expect(!child.environment.enabled);
    try std.testing.expectEqual(g.NodeID.root.child(-1), child.id);
}

test "authored identity trace matches frozen Swift paths exactly" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    const main = a.tuple(.{ a.tuple(.{ a.Empty{}, a.Empty{}, a.Empty{}, Probe{} }), a.tuple(.{ a.Empty{}, a.Empty{}, a.Empty{}, Probe{} }) });
    const n = try a.render(main, &ctx);
    // tests/parity/swift-baseline/geometry-identity.json, paths [0,3] and [1,3].
    try std.testing.expectEqual(@as(u64, 11956973032611051944), n.group[0].group[3].interactive.id.raw);
    try std.testing.expectEqual(@as(u64, 11956974132122677969), n.group[1].group[3].interactive.id.raw);
    const wrapped = try a.render(a.paddingAll(a.frame(a.background(Probe{}, .black), .{}), 1), &ctx);
    try std.testing.expectEqual(@as(u64, 18345957804900032645), wrapped.padding.child.frame.child.background.child.interactive.id.raw);
    const branch: a.Branch(Probe, Probe) = .{ .value = .{ .first = .{} } };
    try std.testing.expectEqual(@as(u64, 8565616715163743237), (try branch.render(&ctx)).interactive.id.raw);
    const single = try a.render(Probe{}, &ctx);
    try std.testing.expectEqual(@as(u64, 14695981039346656037), single.interactive.id.raw);
}
fn rejectRegistration(_: *anyopaque, _: g.context.Registration) Error!void {
    return error.OutOfMemory;
}
fn disable(env: *g.context.Environment) void {
    env.enabled = false;
}
test "host registration failure propagates and environment callback replaces enabled" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    var recorder: Recorder = .{};
    ctx.hooks = .{ .host = &recorder, .register_fn = rejectRegistration };
    const action = try ctx.action(@as(u64, 1), add);
    const button = try a.buttonTitle(&ctx, "Error", action);
    try std.testing.expectError(error.OutOfMemory, button.render(&ctx));
    const off = try a.render(a.environment(button, disable), &ctx);
    try std.testing.expect(!off.interactive.focusable);
    ctx.hooks.host = null;
    try std.testing.expectError(error.Unavailable, button.render(&ctx));
}
test "focused disabled field style focus overrides gray and toggle off glyph" {
    var storage = g.FrameStorage.init(std.testing.allocator);
    defer storage.deinit();
    var ctx = storage.context();
    ctx.focus = ctx.id;
    const field: a.TextField = .{ .value = "value", .binding = binding };
    const node = try a.render(a.disabled(field, true), &ctx);
    try std.testing.expectEqual(g.Color.black, node.interactive.child.styled.style.foreground);
    try std.testing.expectEqual(g.Color.cyan, node.interactive.child.styled.style.background);
    try std.testing.expectEqual(g.style.Attributes.dim, node.interactive.child.styled.style.attributes);
    try std.testing.expectEqualStrings(" value ", node.interactive.child.styled.child.text.content);
    const toggle: a.Toggle = .{ .title = "Off", .value = false, .binding = binding };
    try std.testing.expectEqualStrings("[ ] Off", (try toggle.render(&ctx)).interactive.child.styled.child.text.content);
}
