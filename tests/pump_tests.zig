const std = @import("std");
const g = @import("gama");
const a = std.testing.allocator;
const App = struct {
    ref: ?g.StateRef(i64) = null,
    first_only: ?g.StateRef(i64) = null,
    show: bool = true,
    writes: bool = false,
    renders: usize = 0,
    fail: bool = false,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn increment(ref: *const g.StateRef(i64), _: *anyopaque) g.Error!void {
        try ref.set((try ref.read()).* + 1);
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.renders += 1;
        if (self.fail) return error.Unavailable;
        if (!self.show) return .empty;
        self.ref = try ctx.state(i64, 1, 0);
        if (ctx.focus == null) self.first_only = try ctx.state(i64, 2, 9);
        if (self.writes) {
            self.writes = false;
            try self.ref.?.set((try self.ref.?.read()).* + 1);
        }
        const button = try g.authoring.buttonTitle(ctx, if (ctx.focus == null) "unfocused" else "focused", try ctx.action(self.ref.?, increment));
        return button.render(ctx);
    }
};
fn output(_: void, prep: g.Host(App).Preparation) g.Error![]const u8 {
    return prep.allocator.dupe(u8, "encoded-frame");
}
fn failure(_: void, prep: g.Host(App).Preparation) g.Error![]const u8 {
    _ = try prep.allocator.alloc(u8, 3000);
    return error.Unavailable;
}
test "created host dirty, one focus rebuild, final state sweep and clean pump skips work" {
    var app: App = .{};
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    const pump: g.HostPump(App) = .{ .host = host };
    try std.testing.expect(try host.needsFrame());
    try pump.handle(.{ .resize = .{ .width = 12, .height = 4 } });
    const result = try pump.advance({}, output);
    try std.testing.expect(result.produced and !result.follow_up);
    try std.testing.expectEqual(@as(usize, 2), app.renders);
    try std.testing.expectError(error.InvalidHandle, app.first_only.?.read());
    const tree = (try host.currentTree()).?;
    try std.testing.expectEqual(@as(i64, 12), tree.frame.size.width);
    try std.testing.expectEqualStrings(" focused ", tree.children[0].children[0].node.text.content);
    try std.testing.expect(!(try pump.advance({}, failure)).produced);
    try std.testing.expectEqual(@as(usize, 2), app.renders);
    try pump.handle(.{ .resize = .{ .width = 7, .height = 2 } });
    try std.testing.expectEqual(@as(i64, 7), (try host.currentSize()).width);
    try std.testing.expect(try host.needsFrame());
    try std.testing.expect((try host.currentTree()).? == tree);
    _ = try pump.advance({}, output);
    try std.testing.expectEqual(@as(i64, 7), (try host.currentTree()).?.frame.size.width);
}
test "actual invalidation during render and downstream returns follow-up with input between steps" {
    var app: App = .{ .writes = true };
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    const pump: g.HostPump(App) = .{ .host = host };
    const first = try pump.advance({}, output);
    try std.testing.expect(first.follow_up);
    try pump.handle(.{ .key = .enter });
    try std.testing.expectEqual(@as(i64, 2), (try app.ref.?.read()).*);
    try std.testing.expect(!(try pump.advance({}, output)).follow_up);
    const Callback = struct {
        fn run(ref: g.StateRef(i64), _: g.Host(App).Preparation) g.Error![]const u8 {
            try ref.set(4);
            return "new-frame";
        }
    };
    try host.invalidate();
    try std.testing.expect((try pump.advance(app.ref.?, Callback.run)).follow_up);
    try std.testing.expectEqual(@as(i64, 4), (try app.ref.?.read()).*);
}
test "downstream failure preserves published resources focus registrations handles and accepted edits" {
    var app: App = .{};
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    const pump: g.HostPump(App) = .{ .host = host };
    _ = try pump.advance({}, output);
    const previous = (try host.currentTree()).?;
    const focus = (try host.focusedID()).?;
    const action = (try host.actionHandle(focus)).?;
    const ref = app.ref.?;
    try pump.handle(.{ .key = .enter });
    app.show = false;
    try std.testing.expectError(error.Unavailable, pump.advance({}, failure));
    try std.testing.expectEqual(@as(i64, 1), (try ref.read()).*);
    try std.testing.expect(try host.needsFrame());
    try std.testing.expect((try host.currentTree()).? == previous);
    try std.testing.expectEqual(focus, (try host.focusedID()).?);
    try std.testing.expectEqualStrings("encoded-frame", try host.currentOutput());
    try std.testing.expect(try action.invoke());
    _ = try pump.advance({}, output);
    try std.testing.expectError(error.InvalidHandle, ref.read());
    try std.testing.expectError(error.InvalidHandle, action.invoke());
    try std.testing.expectEqual(@as(?g.NodeID, null), try host.focusedID());
    app.show = true;
    try host.invalidate();
    const candidate = (try host.prepare(.{})).?;
    const aborted = app.ref.?;
    try candidate.abort();
    try std.testing.expectError(error.InvalidTransaction, candidate.tree());
    try std.testing.expectError(error.InvalidTransaction, candidate.finish({}, output));
    try std.testing.expectError(error.InvalidHandle, aborted.read());
    _ = try pump.advance({}, output);
    try std.testing.expectError(error.InvalidHandle, aborted.read());
}
fn allocationSweep(allocator: std.mem.Allocator) !void {
    var app: App = .{};
    const host = try g.Host(App).create(allocator, &app);
    defer host.destroy() catch unreachable;
    const pump: g.HostPump(App) = .{ .host = host };
    _ = try pump.advance({}, output);
    const previous = (try host.currentTree()).?;
    try host.invalidate();
    const result = pump.advance({}, output) catch |err| {
        try std.testing.expect((try host.currentTree()).? == previous);
        try std.testing.expect(try host.needsFrame());
        return err;
    };
    try std.testing.expect(result.produced);
}
test "all layout pump downstream allocation failures leak-free and retry dirty" {
    try std.testing.checkAllAllocationFailures(a, allocationSweep, .{});
}
const OracleApp = struct {
    value: ?g.StateRef(g.String) = null,
    count: ?g.StateRef(i64) = null,
    enabled: bool = true,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn increment(ref: *const g.StateRef(i64), _: *anyopaque) g.Error!void {
        try ref.set((try ref.read()).* + 1);
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.value = try ctx.state(g.String, 10, .{ .bytes = "" });
        self.count = try ctx.state(i64, 11, 0);
        const stack_content = ctx.child(0);
        var field_ctx = stack_content.child(0);
        const field: g.authoring.TextField = .{ .value = (try self.value.?.read()).bytes, .placeholder = "Name", .binding = self.value.?.token };
        var button_ctx = stack_content.child(1);
        button_ctx.environment.enabled = self.enabled;
        button_ctx.environment.action_identity = .{ .id = "add", .shortcut = .{ .control = true, .codepoint = 'a' } };
        const button = try g.authoring.buttonTitle(&button_ctx, "Add", try button_ctx.action(self.count.?, increment));
        const children = try ctx.allocator.alloc(g.Node, 2);
        children[0] = try field.render(&field_ctx);
        children[1] = try button.render(&button_ctx);
        return .{ .stack = .{ .axis = .vertical, .alignment = .top_leading, .children = children } };
    }
};
fn compareTree(tree: g.layout.LaidNode, json: std.json.Value) !void {
    const object = json.object;
    try std.testing.expectEqualStrings(object.get("kind").?.string, @tagName(tree.node));
    const rect = [_]i64{ tree.frame.origin.x, tree.frame.origin.y, tree.frame.size.width, tree.frame.size.height };
    for (rect, object.get("frame").?.array.items) |actual, expected| try std.testing.expectEqual(expected.integer, actual);
    if (object.get("text")) |value| try std.testing.expectEqualStrings(value.string, tree.node.text.content);
    if (object.get("id")) |value| try std.testing.expectEqual(try std.fmt.parseInt(u64, value.string, 10), tree.node.interactive.id.raw);
    if (object.get("focusable")) |value| try std.testing.expectEqual(value.bool, tree.node.interactive.focusable);
    const children = object.get("children").?.array.items;
    try std.testing.expectEqual(children.len, tree.children.len);
    for (tree.children, children) |child, expected| try compareTree(child, expected);
}
fn oracleSnapshot(app: *OracleApp, host: *g.Host(OracleApp), dirty: bool, value: std.json.Value) !void {
    const object = value.object;
    try std.testing.expectEqual(object.get("dirty").?.bool, dirty);
    try std.testing.expectEqual(object.get("count").?.integer, (try app.count.?.read()).*);
    try std.testing.expectEqualStrings(object.get("text").?.string, (try app.value.?.read()).bytes);
    try compareTree((try host.currentTree()).?.*, object.get("tree").?);
}
test "frozen focus-action corpus actual controls callbacks text and every rectangle" {
    const parsed = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/focus-actions.json"), .{});
    defer parsed.deinit();
    const records = parsed.value.array.items;
    var app: OracleApp = .{};
    const host = try g.Host(OracleApp).create(a, &app);
    defer host.destroy() catch unreachable;
    const size: g.geometry.Size = .{ .width = 16, .height = 4 };
    try std.testing.expect(!try host.perform("add"));
    try host.rebuild(size);
    try oracleSnapshot(&app, host, try host.needsFrame(), records[0]);
    const events = [_]g.Key{ .{ .character = "a" }, .{ .character = "e\u{301}" }, .left, .{ .character = "Z" }, .tab, .enter, .{ .shortcut = .{ .codepoint = 'a', .control = true } } };
    for (events, 1..) |event, i| {
        try host.handle(.{ .key = event });
        const dirty = try host.needsFrame();
        try host.rebuild(size);
        try oracleSnapshot(&app, host, dirty, records[i]);
    }
    try std.testing.expect(try host.perform("add"));
    try host.rebuild(size);
    try oracleSnapshot(&app, host, try host.needsFrame(), records[8]);
    app.enabled = false;
    try host.invalidate();
    try host.rebuild(size);
    try std.testing.expect(!try host.perform("add"));
    try host.handle(.{ .key = .{ .shortcut = .{ .codepoint = 'a', .control = true } } });
    try host.rebuild(size);
    try oracleSnapshot(&app, host, try host.needsFrame(), records[9]);
}
const RegionApp = struct {
    overlap: bool = false,
    show_first: bool = true,
    nonfocusable_last: bool = false,
    refs: [3]?g.StateRef(i64) = .{ null, null, null },
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        var children: std.ArrayList(g.Node) = .empty;
        for (0..3) |i| {
            if (i == 0 and !self.show_first) continue;
            var sub = ctx.child(@intCast(i));
            self.refs[i] = try sub.state(i64, 1, 0);
            try sub.register(.{ .action = .{ .id = sub.id, .action = try sub.action(self.refs[i].?, App.increment), .identity = null } });
            try sub.register(.{ .native_region = .{ .id = sub.id, .region_id = "fallback" } });
            try children.append(ctx.allocator, .{ .interactive = .{ .id = sub.id, .focusable = !(i == 2 and self.nonfocusable_last), .child = try ctx.box(.{ .frame = .{ .width = 2, .height = 2, .child = try ctx.box(.empty) } }) } });
        }
        return if (self.overlap) .{ .overlay = .{ .alignment = .top_leading, .children = children.items } } else .{ .stack = .{ .axis = .horizontal, .spacing = 1, .alignment = .top_leading, .children = children.items } };
    }
};
test "spatial focus raw last-hit pointer native rectangles and identity reconciliation" {
    var app: RegionApp = .{};
    const host = try g.Host(RegionApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{ .width = 8, .height = 2 });
    try std.testing.expectEqual(g.NodeID.root.child(0), (try host.focusedID()).?);
    try std.testing.expectEqual(@as(usize, 1), (try host.nativeRegions()).len);
    try std.testing.expectEqual(@as(i64, 6), (try host.nativeRegions())[0].frame.origin.x);
    try host.handle(.{ .key = .right });
    try std.testing.expectEqual(g.NodeID.root.child(1), (try host.focusedID()).?);
    try host.handle(.{ .key = .right });
    try std.testing.expectEqual(g.NodeID.root.child(2), (try host.focusedID()).?);
    try host.handle(.{ .key = .right }); // no directional candidate: tab fallback
    try std.testing.expectEqual(g.NodeID.root.child(0), (try host.focusedID()).?);
    try host.handle(.{ .pointer = .{ .x = 4, .y = 1 } });
    try std.testing.expectEqual(@as(i64, 1), (try app.refs[1].?.read()).*);
    app.show_first = false;
    try host.rebuild(.{ .width = 8, .height = 2 });
    try std.testing.expectEqual(g.NodeID.root.child(1), (try host.focusedID()).?);
    app.overlap = true;
    app.nonfocusable_last = true;
    try host.invalidate();
    try host.rebuild(.{ .width = 8, .height = 2 });
    try host.handle(.{ .pointer = .{ .x = 0, .y = 0 } });
    try std.testing.expectEqual(@as(i64, 1), (try app.refs[2].?.read()).*);
    try std.testing.expectEqual(g.NodeID.root.child(1), (try host.focusedID()).?);
    try host.rebuild(.{ .width = 8, .height = 2 });
    try host.handle(.{ .pointer = .{ .x = 2, .y = 2 } }); // exclusive max, miss
    try std.testing.expect(!try host.needsFrame());
}
test "foreign thread and recursive downstream reject before altering candidate" {
    var app: App = .{};
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    const p = (try host.prepare(.{})).?;
    const Foreign = struct {
        fn run(h: *g.Host(App), candidate: g.Host(App).PreparedFrame) void {
            std.testing.expectError(error.WrongThread, candidate.tree()) catch unreachable;
            std.testing.expectError(error.WrongThread, candidate.finish({}, output)) catch unreachable;
            std.testing.expectError(error.WrongThread, h.currentTree()) catch unreachable;
            std.testing.expectError(error.WrongThread, h.currentOutput()) catch unreachable;
            std.testing.expectError(error.WrongThread, h.nativeRegions()) catch unreachable;
            std.testing.expectError(error.WrongThread, h.duplicateNativeRegionIDs()) catch unreachable;
            std.testing.expectError(error.WrongThread, h.currentSize()) catch unreachable;
            std.testing.expectError(error.WrongThread, h.focusedID()) catch unreachable;
            const pump: g.HostPump(App) = .{ .host = h };
            std.testing.expectError(error.WrongThread, pump.advance({}, output)) catch unreachable;
            std.testing.expectError(error.WrongThread, pump.handle(.{ .pointer = .{} })) catch unreachable;
        }
        fn recursive(h: *g.Host(App), _: g.Host(App).Preparation) g.Error![]const u8 {
            const pump: g.HostPump(App) = .{ .host = h };
            if (pump.advance({}, output)) |_| return error.Unavailable else |e| if (e != error.Reentrant) return e;
            if (h.destroy()) |_| return error.Unavailable else |e| if (e != error.Reentrant) return e;
            if (h.handle(.{ .pointer = .{} })) |_| return error.Unavailable else |e| if (e != error.Reentrant) return e;
            return "guarded";
        }
    };
    const thread = try std.Thread.spawn(.{}, Foreign.run, .{ host, p });
    thread.join();
    try p.finish(host, Foreign.recursive);
    try std.testing.expectEqualStrings("guarded", try host.currentOutput());
}
const BridgeApp = struct {
    bridge: g.StateRef(bool),
    first: ?g.StateRef(i64) = null,
    show: bool = true,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        if (!self.show) return .empty;
        if (ctx.focus == null) self.first = try ctx.state(i64, 5, 7);
        const toggle: g.authoring.Toggle = .{ .title = "enabled", .value = (try self.bridge.read()).*, .binding = self.bridge.token };
        return toggle.render(ctx);
    }
};
test "subscription-owned bridge survives focus discovery passes failed downstream and removal sweep" {
    const signal = try g.Signal(bool).create(a, false);
    defer signal.destroy() catch unreachable;
    var app: BridgeApp = .{ .bridge = undefined };
    const host = try g.Host(BridgeApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.observe(signal);
    app.bridge = try host.bind(try signal.reference());
    const Callback = struct {
        fn ok(_: void, _: g.Host(BridgeApp).Preparation) g.Error![]const u8 {
            return "bridge";
        }
        fn fail(_: void, _: g.Host(BridgeApp).Preparation) g.Error![]const u8 {
            return error.Unavailable;
        }
    };
    const pump: g.HostPump(BridgeApp) = .{ .host = host };
    _ = try pump.advance({}, Callback.ok);
    try std.testing.expectError(error.InvalidHandle, app.first.?.read());
    try host.handle(.{ .key = .enter });
    try std.testing.expect((try signal.read()).*);
    app.show = false;
    try std.testing.expectError(error.Unavailable, pump.advance({}, Callback.fail));
    try std.testing.expect((try app.bridge.read()).*);
    _ = try pump.advance({}, Callback.ok);
    try app.bridge.set(false);
    try std.testing.expect(!(try signal.read()).*);
    try host.cancelAll();
    try std.testing.expectError(error.InvalidHandle, app.bridge.read());
}
const EdgeApp = struct {
    changed_second: bool = false,
    calls: usize = 0,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.calls += 1;
        if (self.changed_second and ctx.focus != null) return .empty;
        // All zero-area focusables remain in visual/tab order. Overlapping directional
        // candidates use earliest visual order on score ties.
        const nodes = try ctx.allocator.alloc(g.Node, 3);
        for (nodes, 0..) |*n, i| n.* = .{ .interactive = .{ .id = ctx.id.child(@intCast(i)), .focusable = true, .child = try ctx.box(.{ .frame = .{ .width = if (i == 0) 0 else 2, .height = 0, .child = try ctx.box(.empty) } }) } };
        return .{ .overlay = .{ .children = nodes, .alignment = .top_leading } };
    }
};
test "zero area focus directional ties and single reconciliation even when second tree changes" {
    var app: EdgeApp = .{};
    const host = try g.Host(EdgeApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{ .width = 10, .height = 0 });
    try std.testing.expectEqual(g.NodeID.root.child(0), (try host.focusedID()).?);
    try host.handle(.{ .key = .right });
    try std.testing.expectEqual(g.NodeID.root.child(1), (try host.focusedID()).?);
    try host.rebuild(.{ .width = 10, .height = 0 });
    try host.handle(.{ .pointer = .{} });
    try std.testing.expect(!try host.needsFrame());
    var changing: EdgeApp = .{ .changed_second = true };
    const other = try g.Host(EdgeApp).create(a, &changing);
    defer other.destroy() catch unreachable;
    try other.rebuild(.{ .width = 10, .height = 0 });
    try std.testing.expectEqual(@as(usize, 2), changing.calls);
    try std.testing.expectEqual(g.NodeID.root.child(0), (try other.focusedID()).?);
    try std.testing.expect((try other.currentTree()).?.node == .empty);
    try std.testing.expect(!try other.needsFrame());
}

test "duplicate diagnostics unique first visual order with interleaved repetitions" {
    const DuplicateApp = struct {
        pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
        fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
            const children = try ctx.allocator.alloc(g.Node, 5);
            for (children, [_]i64{ 0, 1, 1, 0, 0 }) |*child, index| child.* = .{ .interactive = .{ .id = ctx.id.child(index), .focusable = false, .child = try ctx.box(.empty) } };
            return .{ .group = children };
        }
    };
    var app: DuplicateApp = .{};
    const host = try g.Host(DuplicateApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    const ids = try host.duplicateInteractiveIDs();
    try std.testing.expectEqual(@as(usize, 2), ids.len);
    try std.testing.expectEqual(g.NodeID.root.child(0), ids[0]);
    try std.testing.expectEqual(g.NodeID.root.child(1), ids[1]);
}
