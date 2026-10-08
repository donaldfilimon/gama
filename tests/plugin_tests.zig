const std = @import("std");
const g = @import("gama");
const p = g.plugins;
const a = std.testing.allocator;
const Plugin = struct {
    saved: *?p.Context,
    pub fn manifest(_: *Plugin) p.Manifest {
        return .{ .id = "a" };
    }
    pub fn activate(self: *Plugin, context: p.Context) g.Error!void {
        self.saved.* = context;
    }
};
test "saved installation context revokes and cannot resurrect on reinstall" {
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, .{});
    defer runtime.destroy() catch unreachable;
    try runtime.install(Plugin{ .saved = &saved });
    const old = saved.?;
    try old.invalidate();
    try runtime.uninstall("a");
    try std.testing.expectError(error.InvalidHandle, old.invalidate());
    try runtime.install(Plugin{ .saved = &saved });
    try std.testing.expectError(error.InvalidHandle, old.invalidate());
    try saved.?.invalidate();
}

const Recorder = struct {
    events: std.ArrayList([]const u8) = .empty,
    logs: usize = 0,
    reads: usize = 0,
    writes: usize = 0,
    dirty: usize = 0,
    last_scope: ?p.Scope = null,
    fn deinit(self: *Recorder) void {
        for (self.events.items) |v| a.free(v);
        self.events.deinit(a);
    }
    fn event(self: *Recorder, verb: []const u8, id: []const u8) g.Error!void {
        const bytes = try std.fmt.allocPrint(a, "{s}:{s}", .{ verb, id });
        errdefer a.free(bytes);
        try self.events.append(a, bytes);
    }
    fn notify(raw: ?*anyopaque) void {
        const self: *Recorder = @ptrCast(@alignCast(raw.?));
        self.dirty += 1;
        self.events.append(a, a.dupe(u8, "invalidate") catch unreachable) catch unreachable;
    }
    fn log(raw: ?*anyopaque, _: []const u8, _: []const u8) g.Error!void {
        @as(*Recorder, @ptrCast(@alignCast(raw.?))).logs += 1;
    }
    fn clock(_: ?*anyopaque) g.Error!u64 {
        return 42;
    }
    fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, scope: p.Scope) g.Error![]u8 {
        const self: *Recorder = @ptrCast(@alignCast(raw.?));
        self.reads += 1;
        self.last_scope = scope;
        return allocator.dupe(u8, "data");
    }
    fn write(raw: ?*anyopaque, _: []const u8, _: []const u8, scope: p.Scope) g.Error!void {
        const self: *Recorder = @ptrCast(@alignCast(raw.?));
        self.writes += 1;
        self.last_scope = scope;
    }
    fn services(self: *Recorder) p.Services {
        return .{ .userdata = self, .log = log, .clock = clock, .read = read, .write = write };
    }
};
const Basic = struct {
    id: []const u8 = "a",
    abi: u32 = 1,
    required: []const p.Capability = &.{},
    optional: []const p.Capability = &.{},
    recorder: *Recorder,
    saved: *?p.Context,
    signal: ?*g.Signal(i64) = null,
    fail: bool = false,
    pub fn manifest(self: *Basic) p.Manifest {
        return .{ .id = self.id, .abi = self.abi, .requires = self.required, .optional = self.optional };
    }
    pub fn activate(self: *Basic, context: p.Context) g.Error!void {
        self.saved.* = context;
        try self.recorder.event("activate", self.id);
        if (self.signal) |signal| try context.observe(signal);
        if (self.fail) return error.ActivationFailed;
    }
    pub fn deactivate(self: *Basic) void {
        self.recorder.event("deactivate", self.id) catch unreachable;
    }
    fn run(context: p.Context) g.Error!void {
        // Tests inject the same Recorder as the portable provider userdata.
        const recorder: *Recorder = @ptrCast(@alignCast(context.lease.services.userdata.?));
        try recorder.event("run", try context.pluginID());
    }
    pub fn commands(_: *Basic) g.Error![]const p.CommandDefinition {
        return &.{.{ .id = "run", .title = "Run", .action = run }};
    }
    pub fn render(self: *Basic, _: []const u8, context: p.Context, build: *g.BuildContext) g.Error!g.Node {
        const action = try build.action(context, struct {
            fn call(value: *const p.Context, _: *anyopaque) g.Error!void {
                try Basic.run(value.*);
                try value.invalidate();
            }
        }.call);
        try build.register(.{ .action = .{ .id = build.id, .action = action, .identity = null } });
        return .{ .interactive = .{ .id = build.id, .focusable = true, .child = try build.box(.{ .text = .{ .content = self.id } }) } };
    }
};
const all_caps = [_]p.Capability{ .log, .clock, .{ .filesystem = .{ .prefix = "/a", .writable = true } } };
fn grants(id: []const u8, caps: []const p.Capability, storage: *[1]p.Grant) p.Grants {
    storage.* = .{.{ .id = id, .capabilities = caps }};
    return .{ .entries = storage };
}

test "ABI duplicate and per-declaration grant/service precedence before callbacks" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    var table: [1]p.Grant = undefined;
    const runtime = try g.PluginRuntime.create(a, grants("a", &all_caps, &table), .{});
    defer runtime.destroy() catch unreachable;
    var plugin = Basic{ .recorder = &r, .saved = &saved, .abi = 2, .required = &.{.log} };
    try std.testing.expectError(error.ABIMismatch, runtime.install(plugin));
    plugin.abi = 1;
    try std.testing.expectError(error.ServiceUnavailable, runtime.install(plugin));
    plugin.required = &.{ .clock, .{ .filesystem = .{ .prefix = "/absent" } } };
    try std.testing.expectError(error.ServiceUnavailable, runtime.install(plugin));
    plugin.required = &.{ .{ .filesystem = .{ .prefix = "/absent" } }, .clock };
    try std.testing.expectError(error.MissingRequiredCapability, runtime.install(plugin));
    try std.testing.expectEqual(@as(usize, 0), r.events.items.len);
    plugin.required = &.{};
    try runtime.install(plugin);
    try std.testing.expectError(error.DuplicatePlugin, runtime.install(plugin));
    plugin.abi = 2;
    try std.testing.expectError(error.ABIMismatch, runtime.install(plugin));
}
test "optional absent filtering exact grants and unrequested grants" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    var table: [1]p.Grant = undefined;
    const runtime = try g.PluginRuntime.create(a, grants("a", &all_caps, &table), .{ .userdata = &r, .log = Recorder.log });
    defer runtime.destroy() catch unreachable;
    try runtime.install(Basic{ .recorder = &r, .saved = &saved, .optional = &all_caps });
    try std.testing.expect((try saved.?.log()) != null);
    try std.testing.expect((try saved.?.clock()) == null);
    try std.testing.expect((try saved.?.filesystem()) == null);
    try runtime.uninstall("a");
    try runtime.install(Basic{ .recorder = &r, .saved = &saved });
    try std.testing.expect((try saved.?.log()) == null);
    try runtime.uninstall("a");
    try std.testing.expectError(error.MissingRequiredCapability, runtime.install(Basic{ .recorder = &r, .saved = &saved, .required = &.{.{ .filesystem = .{ .prefix = "/a" } }} }));
    try std.testing.expectError(error.MissingRequiredCapability, runtime.install(Basic{ .recorder = &r, .saved = &saved, .required = &.{.{ .filesystem = .{ .prefix = "/a/", .writable = true } }} }));
}
test "all capabilities contexts commands and subscription controls revoke before provider calls" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    var table: [1]p.Grant = undefined;
    const runtime = try g.PluginRuntime.create(a, grants("a", &all_caps, &table), r.services());
    defer runtime.destroy() catch unreachable;
    const signal = try g.Signal(i64).create(a, 0);
    defer signal.destroy() catch unreachable;
    const plugin = Basic{ .recorder = &r, .saved = &saved, .required = &all_caps };
    try runtime.install(plugin);
    const old = saved.?;
    const log = (try old.log()).?;
    const clock = (try old.clock()).?;
    const fs = (try old.filesystem()).?;
    const commands = try runtime.commands(a);
    defer a.free(commands);
    try log.write("hello");
    try std.testing.expectEqual(@as(u64, 42), try clock.nowMillis());
    try std.testing.expectError(error.AccessDenied, fs.read(a, "/ab"));
    try std.testing.expectEqual(@as(usize, 0), r.reads);
    const bytes = try fs.read(a, "/a/x");
    a.free(bytes);
    try fs.write("/a/x", "x");
    try runtime.uninstall("a");
    try runtime.install(plugin);
    try std.testing.expectError(error.InvalidHandle, commands[0].perform());
    try std.testing.expectError(error.InvalidHandle, old.invalidate());
    try std.testing.expectError(error.InvalidHandle, old.cancelAll());
    try std.testing.expectError(error.InvalidHandle, old.observe(signal));
    try std.testing.expectError(error.InvalidHandle, log.write("no"));
    try std.testing.expectError(error.InvalidHandle, clock.nowMillis());
    try std.testing.expectError(error.InvalidHandle, fs.read(a, "/a/x"));
    try std.testing.expectError(error.InvalidHandle, fs.write("/a/x", "x"));
    try std.testing.expectEqual(@as(usize, 1), r.logs);
    try std.testing.expectEqual(@as(usize, 1), r.reads);
    try std.testing.expectEqual(@as(usize, 1), r.writes);
}
test "filesystem first matching scope preserves required optional order and duplicates" {
    const caps = [_]p.Capability{ .{ .filesystem = .{ .prefix = "/a/b" } }, .{ .filesystem = .{ .prefix = "/a", .writable = true } }, .{ .filesystem = .{ .prefix = "/a/b" } } };
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    var table: [1]p.Grant = undefined;
    const runtime = try g.PluginRuntime.create(a, grants("a", &caps, &table), r.services());
    defer runtime.destroy() catch unreachable;
    try runtime.install(Basic{ .recorder = &r, .saved = &saved, .required = caps[0..1], .optional = caps[1..] });
    try std.testing.expectEqual(@as(usize, 3), saved.?.lease.capabilities.len);
    const fs = (try saved.?.filesystem()).?;
    const bytes = try fs.read(a, "/a/b/c");
    a.free(bytes);
    try std.testing.expectEqualStrings("/a/b", r.last_scope.?.prefix);
    try fs.write("/a/b/c", "x");
    try std.testing.expectEqualStrings("/a", r.last_scope.?.prefix);
}
test "lexical baseline matrix and hostile prefixes" {
    const fixture = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/plugins.json"), .{});
    defer fixture.deinit();
    const scope = p.Scope{ .prefix = "/a", .writable = true };
    for (fixture.value.object.get("paths").?.array.items) |v| {
        const path = v.object.get("path").?.string;
        try std.testing.expectEqual(v.object.get("read").?.bool, scope.permits(path, false));
        try std.testing.expectEqual(v.object.get("write").?.bool, scope.permits(path, true));
    }
    for ([_][]const u8{ "", "a", "//", "/a//", "/a/.", "/a/../b" }) |prefix| try std.testing.expect(!(p.Scope{ .prefix = prefix, .writable = true }).permits("/a/b", false));
    for ([_][]const u8{ "/a", "/a/", "/a/b", "/a/b/" }) |path| try std.testing.expect((p.Scope{ .prefix = "/a/" }).permits(path, false));
    try std.testing.expect((p.Scope{ .prefix = "/" }).permits("/anything", false));
    try std.testing.expect(!(p.Scope{ .prefix = "/" }).permits("//", false));
}

fn checkTree(node: g.Node, order: []const u8, golden: []const u8) !void {
    try std.testing.expectEqual(order.len, node.group.len);
    for (node.group, order) |child, label| {
        const id: u64 = if (label == 'a') 8565616715163743237 else 8565616715163743238;
        try std.testing.expectEqual(id, child.interactive.id.raw);
        try std.testing.expect(child.interactive.focusable);
        try std.testing.expectEqualStrings(&.{label}, child.interactive.child.text.content);
        const needle = try std.fmt.allocPrint(a, "id = {d} : i64", .{id});
        defer a.free(needle);
        try std.testing.expect(std.mem.indexOf(u8, golden, needle) != null);
    }
}
test "frozen plugin event corpus and retained IR identity order across removal reinstall" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, r.services());
    defer runtime.destroy() catch unreachable;
    try runtime.setInvalidation(.{ .userdata = &r, .notify = Recorder.notify });
    try std.testing.expectError(error.MissingRequiredCapability, runtime.install(Basic{ .id = "denied", .required = &.{.log}, .recorder = &r, .saved = &saved }));
    const pa = Basic{ .recorder = &r, .saved = &saved };
    const pb = Basic{ .id = "b", .recorder = &r, .saved = &saved };
    try runtime.install(pa);
    try runtime.install(pb);
    const before_commands = try runtime.commands(a);
    defer a.free(before_commands);
    try before_commands[0].perform();
    var frame = g.FrameStorage.init(a);
    defer frame.deinit();
    var ctx = frame.context();
    try checkTree(try runtime.render("main", &ctx), "ab", @embedFile("parity/swift-baseline/plugins-before.mlir"));
    try runtime.uninstall("a");
    try std.testing.expectError(error.InvalidHandle, before_commands[0].perform());
    try before_commands[1].perform();
    try checkTree(try runtime.render("main", &ctx), "b", @embedFile("parity/swift-baseline/plugins-after.mlir"));
    try runtime.install(pa);
    try checkTree(try runtime.render("main", &ctx), "ba", @embedFile("parity/swift-baseline/plugins-reinstall.mlir"));
    const ids = try runtime.installed(a);
    defer a.free(ids);
    try std.testing.expectEqualStrings("b", ids[0]);
    try std.testing.expectEqualStrings("a", ids[1]);
    try runtime.uninstall("a");
    try runtime.uninstall("b");
    const json = try std.json.parseFromSlice(std.json.Value, a, @embedFile("parity/swift-baseline/plugins.json"), .{});
    defer json.deinit();
    const events = json.value.object.get("events").?.array.items;
    try std.testing.expectEqual(events.len, r.events.items.len);
    for (events, r.events.items) |expected, actual| try std.testing.expectEqualStrings(expected.string, actual);
    try std.testing.expect((try runtime.render("main", &ctx)) == .empty);
    const dirty = r.dirty;
    try runtime.uninstall("missing");
    try std.testing.expectEqual(dirty, r.dirty);
}

const SlotApp = struct {
    runtime: *g.PluginRuntime,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        return self.runtime.render("main", ctx);
    }
};
test "host contribution actions reject after removal before rebuild and reinstall" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, r.services());
    var app = SlotApp{ .runtime = runtime };
    const host = try g.Host(SlotApp).create(a, &app);
    defer host.destroy() catch unreachable;
    defer runtime.destroy() catch unreachable;
    try runtime.setInvalidation(p.Invalidation.host(host));
    const plugin = Basic{ .recorder = &r, .saved = &saved };
    try runtime.install(plugin);
    try host.rebuild(.{ .width = 10, .height = 3 });
    const action = (try host.actionHandle(g.NodeID.root.child(0))).?;
    _ = try action.invoke();
    try std.testing.expect(try host.needsFrame());
    try runtime.uninstall("a");
    try std.testing.expectError(error.InvalidHandle, action.invoke());
    try runtime.install(plugin);
    try std.testing.expectError(error.InvalidHandle, action.invoke());
    try host.rebuild(.{ .width = 10, .height = 3 });
    _ = try (try host.actionHandle(g.NodeID.root.child(0))).?.invoke();
}

test "failed activation revokes saved context cancels only candidate and never deactivates" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved_a: ?p.Context = null;
    var saved_b: ?p.Context = null;
    const source = try g.Signal(i64).create(a, 0);
    defer source.destroy() catch unreachable;
    const runtime = try g.PluginRuntime.create(a, .{}, r.services());
    var app = SlotApp{ .runtime = runtime };
    const host = try g.Host(SlotApp).create(a, &app);
    defer host.destroy() catch unreachable;
    defer runtime.destroy() catch unreachable;
    try host.observe(source);
    try runtime.setInvalidation(p.Invalidation.host(host));
    try runtime.install(Basic{ .id = "a", .recorder = &r, .saved = &saved_a, .signal = source });
    try host.rebuild(.{});
    try std.testing.expectError(error.ActivationFailed, runtime.install(Basic{ .id = "b", .recorder = &r, .saved = &saved_b, .signal = source, .fail = true }));
    try std.testing.expect(!(try host.needsFrame()));
    try std.testing.expectError(error.InvalidHandle, saved_b.?.observe(source));
    try source.set(1);
    try std.testing.expect(try host.needsFrame());
    try host.rebuild(.{});
    try runtime.uninstall("a");
    try host.rebuild(.{});
    try source.set(2);
    try std.testing.expect(try host.needsFrame());
    for (r.events.items) |event| try std.testing.expect(!std.mem.eql(u8, event, "deactivate:b"));
}
test "per-installation observations preserve peer cancellation and source-first detach" {
    var one: Recorder = .{};
    defer one.deinit();
    var two: Recorder = .{};
    defer two.deinit();
    var saved: ?p.Context = null;
    const source = try g.Signal(i64).create(a, 0);
    const r1 = try g.PluginRuntime.create(a, .{}, one.services());
    defer r1.destroy() catch unreachable;
    const r2 = try g.PluginRuntime.create(a, .{}, two.services());
    defer r2.destroy() catch unreachable;
    try r1.setInvalidation(.{ .userdata = &one, .notify = Recorder.notify });
    try r2.setInvalidation(.{ .userdata = &two, .notify = Recorder.notify });
    try r1.install(Basic{ .id = "a", .recorder = &one, .saved = &saved, .signal = source });
    try r1.install(Basic{ .id = "b", .recorder = &one, .saved = &saved, .signal = source });
    try r2.install(Basic{ .recorder = &two, .saved = &saved, .signal = source });
    try r1.uninstall("a");
    one.dirty = 0;
    two.dirty = 0;
    try source.set(1);
    try std.testing.expectEqual(@as(usize, 1), one.dirty);
    try std.testing.expectEqual(@as(usize, 1), two.dirty);
    try saved.?.cancelAll();
    try saved.?.cancelAll();
    try saved.?.observe(source);
    try saved.?.observe(source);
    try source.destroy();
    try r1.uninstall("b");
    try r2.uninstall("a");
}

const Snapshot = struct {
    runtime: *g.PluginRuntime,
    recorder: *Recorder,
    saved: *?p.Context,
    source: *g.Signal(i64),
    invoked: usize = 0,
    fn invoke(raw: *const anyopaque, _: g.SignalRef(i64)) g.Error!void {
        const self: *Snapshot = @ptrCast(@alignCast(@constCast(raw)));
        self.invoked += 1;
        try self.runtime.uninstall("a");
        try self.runtime.install(Basic{ .recorder = self.recorder, .saved = self.saved, .signal = self.source });
        self.runtime.destroy() catch |err| {
            if (err == error.Reentrant) return;
            return err;
        };
        return error.Unavailable;
    }
};
test "uninstall reinstall in snapshot keeps old lease attached until safe destroy retry" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, r.services());
    const source = try g.Signal(i64).create(a, 0);
    defer source.destroy() catch unreachable;
    var snapshot = Snapshot{ .runtime = runtime, .recorder = &r, .saved = &saved, .source = source };
    const token = try source.observeOwner(&snapshot, Snapshot.invoke);
    defer source.cancel(token) catch unreachable;
    try runtime.setInvalidation(.{ .userdata = &r, .notify = Recorder.notify });
    try runtime.install(Basic{ .recorder = &r, .saved = &saved, .signal = source });
    const old = saved.?;
    r.dirty = 0;
    try source.set(1);
    try std.testing.expectEqual(@as(usize, 1), snapshot.invoked);
    // Uninstall and reinstall invalidate, canceled snapshot must not notify old lease.
    try std.testing.expectEqual(@as(usize, 2), r.dirty);
    try std.testing.expectError(error.InvalidHandle, old.cancelAll());
    try runtime.destroy();
}

const Declarations = struct {
    recorder: *Recorder,
    saved: *?p.Context,
    primary: bool = false,
    pub fn manifest(_: *Declarations) p.Manifest {
        return .{ .id = "x/y" };
    }
    pub fn scenes(self: *Declarations, context: p.Context) g.Error![]const p.SceneDefinition {
        self.saved.* = context;
        try self.recorder.event("scenes", "x/y");
        return if (self.primary) &.{.{ .name = "bad", .role = .primary, .render = renderScene }} else &.{ .{ .name = "tool/one", .title = "Tool", .size = .{ .width = 33, .height = 7 }, .resizable = false, .render = renderScene }, .{ .name = "tool/one", .render = renderScene } };
    }
    pub fn commands(self: *Declarations) g.Error![]const p.CommandDefinition {
        try self.recorder.event("commands", "x/y");
        return &.{};
    }
    pub fn activate(self: *Declarations, _: p.Context) g.Error!void {
        try self.recorder.event("activate", "x/y");
    }
    fn renderScene(context: p.Context, ctx: *g.BuildContext) g.Error!g.Node {
        return .{ .text = .{ .content = try ctx.copyText(try context.pluginID()) } };
    }
};
test "scene and command declarations precede activation primary rejected duplicate IDs downstream" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, .{});
    defer runtime.destroy() catch unreachable;
    try std.testing.expectError(error.PrimarySceneContribution, runtime.install(Declarations{ .recorder = &r, .saved = &saved, .primary = true }));
    try std.testing.expectEqual(@as(usize, 1), r.events.items.len);
    try std.testing.expectError(error.InvalidHandle, saved.?.invalidate());
    try runtime.install(Declarations{ .recorder = &r, .saved = &saved });
    try std.testing.expectEqualStrings("scenes:x/y", r.events.items[1]);
    try std.testing.expectEqualStrings("commands:x/y", r.events.items[2]);
    try std.testing.expectEqualStrings("activate:x/y", r.events.items[3]);
    const scenes = try runtime.contributedScenes(a);
    defer a.free(scenes);
    try std.testing.expectEqual(@as(usize, 2), scenes.len);
    try std.testing.expectEqualStrings("plugin/x/y/tool/one", scenes[0].id);
    try std.testing.expectEqualStrings(scenes[0].id, scenes[1].id);
    try std.testing.expectEqual(@as(i64, 33), scenes[0].size.width);
    try std.testing.expect(!scenes[0].resizable);
    var frame = g.FrameStorage.init(a);
    defer frame.deinit();
    var ctx = frame.context();
    try std.testing.expectEqualStrings("x/y", (try scenes[0].render(&ctx)).text.content);
    const SceneApp = struct {
        contribution: p.Scene,
        fn get(self: *@This()) p.Scene {
            return self.contribution;
        }
        fn primary(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
            return .empty;
        }
    };
    var app_scene = SceneApp{ .contribution = scenes[0] };
    const descriptor = scenes[0].descriptor(SceneApp, SceneApp.get);
    const primary: g.scenes.Descriptor(SceneApp) = .{ .id = "main", .role = .primary, .render = SceneApp.primary };
    try std.testing.expectError(error.DuplicateSceneID, g.scenes.validate(SceneApp, &.{ primary, descriptor, descriptor }));
    var graph = try g.scenes.Graph(SceneApp).init(a, &.{ primary, descriptor });
    defer graph.deinit();
    try std.testing.expectEqualStrings("x/y", (try graph.descriptors[1].render(&app_scene, &ctx)).text.content);
    try runtime.uninstall("x/y");
    try std.testing.expectError(error.InvalidHandle, scenes[0].render(&ctx));
}

const Foreign = struct {
    runtime: *g.PluginRuntime,
    context: p.Context,
    source: *g.Signal(i64),
    failure: ?anyerror = null,
    fn run(self: *Foreign) void {
        self.check() catch |err| {
            self.failure = err;
        };
    }
    fn check(self: *Foreign) !void {
        try std.testing.expectError(error.WrongThread, self.runtime.install(Plugin{ .saved = undefined }));
        try std.testing.expectError(error.WrongThread, self.runtime.uninstall("a"));
        try std.testing.expectError(error.WrongThread, self.runtime.destroy());
        try std.testing.expectError(error.WrongThread, self.runtime.commands(a));
        try std.testing.expectError(error.WrongThread, self.runtime.contributedScenes(a));
        try std.testing.expectError(error.WrongThread, self.runtime.installed(a));
        try std.testing.expectError(error.WrongThread, self.context.invalidate());
        try std.testing.expectError(error.WrongThread, self.context.observe(self.source));
        try std.testing.expectError(error.WrongThread, self.context.cancelAll());
        try std.testing.expectError(error.WrongThread, self.context.log());
        try std.testing.expectError(error.WrongThread, self.context.withPlugin(Plugin, struct {
            fn call(_: *Plugin, _: p.Context) g.Error!void {}
        }.call));
        try std.testing.expectError(error.WrongThread, (p.LogAccess{ .context = self.context }).write("x"));
        try std.testing.expectError(error.WrongThread, (p.ClockAccess{ .context = self.context }).nowMillis());
        try std.testing.expectError(error.WrongThread, (p.FilesystemAccess{ .context = self.context }).read(a, "/a"));
        try std.testing.expectError(error.WrongThread, (p.FilesystemAccess{ .context = self.context }).write("/a", "x"));
        try std.testing.expectError(error.WrongThread, (p.Command{ .context = self.context, .id = "x", .title = "x", .action = Basic.run }).perform());
    }
};
test "native executor rejects foreign-thread runtime context and queries before allocator use" {
    var accounting = std.testing.FailingAllocator.init(a, .{});
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(accounting.allocator(), .{}, .{});
    defer runtime.destroy() catch unreachable;
    const source = try g.Signal(i64).create(a, 0);
    defer source.destroy() catch unreachable;
    try runtime.install(Plugin{ .saved = &saved });
    var foreign = Foreign{ .runtime = runtime, .context = saved.?, .source = source };
    const allocations = accounting.allocations;
    const frees = accounting.deallocations;
    const thread = try std.Thread.spawn(.{}, Foreign.run, .{&foreign});
    thread.join();
    if (foreign.failure) |err| return err;
    try std.testing.expectEqual(allocations, accounting.allocations);
    try std.testing.expectEqual(frees, accounting.deallocations);
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(allocator, .{}, .{});
    defer runtime.destroy() catch unreachable;
    const source = try g.Signal(i64).create(allocator, 0);
    defer source.destroy() catch unreachable;
    const Observing = struct {
        source: *g.Signal(i64),
        saved: *?p.Context,
        pub fn manifest(_: *@This()) p.Manifest {
            return .{ .id = "allocation" };
        }
        pub fn activate(self: *@This(), ctx: p.Context) g.Error!void {
            self.saved.* = ctx;
            try ctx.observe(self.source);
        }
        pub fn commands(_: *@This()) g.Error![]const p.CommandDefinition {
            return &.{.{ .id = "x", .title = "X", .action = noop }};
        }
        fn noop(_: p.Context) g.Error!void {}
    };
    try runtime.install(Observing{ .source = source, .saved = &saved });
    const commands = try runtime.commands(allocator);
    defer allocator.free(commands);
    try source.set(1);
    try commands[0].perform();
    try runtime.uninstall("allocation");
    try runtime.install(Observing{ .source = source, .saved = &saved });
}
test "allocation failures unwind candidate observations declarations and payloads" {
    try std.testing.checkAllAllocationFailures(a, allocationScenario, .{});
}

const Controls = struct {
    value: *?g.StateRef(bool),
    text: *?g.StateRef(g.String),
    pub fn manifest(_: *Controls) p.Manifest {
        return .{ .id = "controls" };
    }
    pub fn activate(_: *Controls, _: p.Context) g.Error!void {}
    pub fn render(self: *Controls, _: []const u8, _: p.Context, ctx: *g.BuildContext) g.Error!g.Node {
        var toggle_ctx = ctx.child(0);
        var text_ctx = ctx.child(1);
        self.value.* = try toggle_ctx.state(bool, 0, false);
        self.text.* = try text_ctx.state(g.String, 1, .{ .bytes = "" });
        const nodes = try ctx.allocator.alloc(g.Node, 2);
        nodes[0] = try (g.authoring.Toggle{ .title = "Toggle", .value = false, .binding = self.value.*.?.token }).render(&toggle_ctx);
        nodes[1] = try (g.authoring.TextField{ .value = "", .binding = self.text.*.?.token }).render(&text_ctx);
        return .{ .group = nodes };
    }
};
test "removed plugin toggle and text control reject retained host dispatch before rebuild" {
    const runtime = try g.PluginRuntime.create(a, .{}, .{});
    var app = SlotApp{ .runtime = runtime };
    const host = try g.Host(SlotApp).create(a, &app);
    defer host.destroy() catch unreachable;
    defer runtime.destroy() catch unreachable;
    var value: ?g.StateRef(bool) = null;
    var txt: ?g.StateRef(g.String) = null;
    try runtime.install(Controls{ .value = &value, .text = &txt });
    try host.rebuild(.{ .width = 30, .height = 4 });
    const action = (try host.actionHandle(g.NodeID.root.child(0).child(0))).?;
    try host.handle(.{ .key = .tab });
    try runtime.uninstall("controls");
    try std.testing.expectError(error.InvalidHandle, host.handle(.{ .key = .{ .character = "x" } }));
    try std.testing.expectEqualStrings("", (try txt.?.read()).bytes);
    try std.testing.expectError(error.InvalidHandle, action.invoke());
    try std.testing.expect(!(try value.?.read()).*);
}

const ReentrantPlugin = struct {
    runtime: *g.PluginRuntime,
    saved: *?p.Context,
    host: ?*g.Host(SlotApp) = null,
    pub fn manifest(_: *ReentrantPlugin) p.Manifest {
        return .{ .id = "reentrant" };
    }
    pub fn activate(self: *ReentrantPlugin, ctx: p.Context) g.Error!void {
        self.saved.* = ctx;
        try self.probe();
    }
    fn expectReentrant(result: g.Error!void) g.Error!void {
        result catch |err| {
            if (err == error.Reentrant) return;
            return err;
        };
        return error.Unavailable;
    }
    fn probe(self: *ReentrantPlugin) g.Error!void {
        try expectReentrant(self.runtime.destroy());
        try expectReentrant(self.runtime.uninstall("reentrant"));
        try expectReentrant(self.runtime.install(self.*));
    }
    pub fn render(self: *ReentrantPlugin, _: []const u8, ctx: p.Context, _: *g.BuildContext) g.Error!g.Node {
        try self.probe();
        try ctx.invalidate();
        if (self.host) |host| try expectReentrant(host.invalidate());
        return .empty;
    }
};
test "activation and rendering reject recursive mutations but notification requests genuine host followup" {
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, .{});
    var app = SlotApp{ .runtime = runtime };
    const host = try g.Host(SlotApp).create(a, &app);
    defer host.destroy() catch unreachable;
    defer runtime.destroy() catch unreachable;
    try runtime.setInvalidation(p.Invalidation.host(host));
    try runtime.install(ReentrantPlugin{ .runtime = runtime, .saved = &saved, .host = host });
    try host.rebuild(.{});
    try std.testing.expect(try host.needsFrame());
}
const ProviderReentry = struct {
    runtime: *g.PluginRuntime,
    saved: *?p.Context,
    calls: usize = 0,
    fn log(raw: ?*anyopaque, _: []const u8, _: []const u8) g.Error!void {
        const self: *ProviderReentry = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        try ReentrantPlugin.expectReentrant(self.runtime.destroy());
        try ReentrantPlugin.expectReentrant(self.runtime.uninstall("a"));
        try ReentrantPlugin.expectReentrant((try self.saved.*.?.log()).?.write("recursive"));
    }
};
test "service callbacks reject lifecycle and same lease service reentry" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    var provider: ProviderReentry = undefined;
    const runtime = try g.PluginRuntime.create(a, .{ .entries = &.{.{ .id = "a", .capabilities = &.{.log} }} }, .{ .userdata = &provider, .log = ProviderReentry.log });
    defer runtime.destroy() catch unreachable;
    provider = .{ .runtime = runtime, .saved = &saved };
    try runtime.install(Basic{ .recorder = &r, .saved = &saved, .required = &.{.log} });
    try (try saved.?.log()).?.write("once");
    try std.testing.expectEqual(@as(usize, 1), provider.calls);
}
test "constructing a capability wrapper cannot bypass unrequested authority" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, r.services());
    defer runtime.destroy() catch unreachable;
    try runtime.install(Plugin{ .saved = &saved });
    try std.testing.expectError(error.AccessDenied, (p.LogAccess{ .context = saved.? }).write("no grant"));
    try std.testing.expectError(error.AccessDenied, (p.ClockAccess{ .context = saved.? }).nowMillis());
    try std.testing.expectEqual(@as(usize, 0), r.logs);
}

fn frameAllocationScenario(allocator: std.mem.Allocator) !void {
    const runtime = try g.PluginRuntime.create(allocator, .{}, .{});
    var app = SlotApp{ .runtime = runtime };
    const host = g.Host(SlotApp).create(allocator, &app) catch |err| {
        try runtime.destroy();
        return err;
    };
    defer host.destroy() catch unreachable;
    defer runtime.destroy() catch unreachable;
    try runtime.setInvalidation(p.Invalidation.host(host));
    var value: ?g.StateRef(bool) = null;
    var txt: ?g.StateRef(g.String) = null;
    try runtime.install(Controls{ .value = &value, .text = &txt });
    try host.rebuild(.{ .width = 30, .height = 4 });
    _ = try (try host.actionHandle(g.NodeID.root.child(0).child(0))).?.invoke();
    try std.testing.expect((try value.?.read()).*);
    try runtime.uninstall("controls");
    try host.rebuild(.{ .width = 30, .height = 4 });
}
test "plugin frame registration authority OOM preserves safe host teardown" {
    try std.testing.checkAllAllocationFailures(a, frameAllocationScenario, .{});
}

test "failed activation external effects remain but all saved authority revokes" {
    const Effect = struct {
        saved: *?p.Context,
        pub fn manifest(_: *@This()) p.Manifest {
            return .{ .id = "effect", .requires = &.{.log} };
        }
        pub fn activate(self: *@This(), ctx: p.Context) g.Error!void {
            self.saved.* = ctx;
            try (try ctx.log()).?.write("before failure");
            return error.ActivationFailed;
        }
    };
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{ .entries = &.{.{ .id = "effect", .capabilities = &.{.log} }} }, r.services());
    defer runtime.destroy() catch unreachable;
    try std.testing.expectError(error.ActivationFailed, runtime.install(Effect{ .saved = &saved }));
    try std.testing.expectEqual(@as(usize, 1), r.logs);
    try std.testing.expectError(error.InvalidHandle, saved.?.log());
    const ids = try runtime.installed(a);
    defer a.free(ids);
    try std.testing.expectEqual(@as(usize, 0), ids.len);
}

test "runtime destruction deactivates current install order with no lifecycle invalidation" {
    var r: Recorder = .{};
    defer r.deinit();
    var saved: ?p.Context = null;
    const runtime = try g.PluginRuntime.create(a, .{}, r.services());
    try runtime.setInvalidation(.{ .userdata = &r, .notify = Recorder.notify });
    try runtime.install(Basic{ .id = "b", .recorder = &r, .saved = &saved });
    try runtime.install(Basic{ .id = "a", .recorder = &r, .saved = &saved });
    const dirty = r.dirty;
    try runtime.destroy();
    try std.testing.expectEqual(dirty, r.dirty);
    try std.testing.expectEqualStrings("deactivate:b", r.events.items[r.events.items.len - 2]);
    try std.testing.expectEqualStrings("deactivate:a", r.events.items[r.events.items.len - 1]);
}

const ReactivePlugin = struct {
    source: *g.Signal(i64),
    runtime: *g.PluginRuntime,
    saved: *?p.Context,
    pub fn manifest(_: *ReactivePlugin) p.Manifest {
        return .{ .id = "reactive" };
    }
    pub fn activate(self: *ReactivePlugin, ctx: p.Context) g.Error!void {
        self.saved.* = ctx;
        try ctx.observe(self.source);
    }
    pub fn commands(_: *ReactivePlugin) g.Error![]const p.CommandDefinition {
        return &.{.{ .id = "increment", .title = "Increment", .action = run }};
    }
    fn run(ctx: p.Context) g.Error!void {
        try ctx.withPlugin(ReactivePlugin, increment);
    }
    fn increment(self: *ReactivePlugin, ctx: p.Context) g.Error!void {
        try ReentrantPlugin.expectReentrant(self.runtime.uninstall("reactive"));
        try ReentrantPlugin.expectReentrant(self.runtime.destroy());
        try ReentrantPlugin.expectReentrant(ctx.withPlugin(ReactivePlugin, increment));
        try self.source.set((try self.source.read()).* + 1);
    }
    pub fn render(self: *ReactivePlugin, _: []const u8, _: p.Context, ctx: *g.BuildContext) g.Error!g.Node {
        return .{ .text = .{ .content = try std.fmt.allocPrint(ctx.allocator, "count={d}", .{(try self.source.read()).*}) } };
    }
};
test "typed command plugin borrow updates Signal and host frame while teardown stays protected" {
    var saved: ?p.Context = null;
    const source = try g.Signal(i64).create(a, 0);
    defer source.destroy() catch unreachable;
    const runtime = try g.PluginRuntime.create(a, .{}, .{});
    var app = SlotApp{ .runtime = runtime };
    const host = try g.Host(SlotApp).create(a, &app);
    defer host.destroy() catch unreachable;
    defer runtime.destroy() catch unreachable;
    try runtime.setInvalidation(p.Invalidation.host(host));
    try runtime.install(ReactivePlugin{ .source = source, .runtime = runtime, .saved = &saved });
    try host.rebuild(.{ .width = 20, .height = 2 });
    try std.testing.expectEqualStrings("count=0", (try host.currentNode()).?.group[0].text.content);
    const commands = try runtime.commands(a);
    defer a.free(commands);
    try commands[0].perform();
    try std.testing.expect(try host.needsFrame());
    try host.rebuild(.{ .width = 20, .height = 2 });
    try std.testing.expectEqualStrings("count=1", (try host.currentNode()).?.group[0].text.content);
    const Wrong = struct {
        fn run(_: *u64, _: p.Context) g.Error!void {
            return error.Unavailable;
        }
    };
    try std.testing.expectError(error.InvalidHandle, saved.?.withPlugin(u64, Wrong.run));
    // A direct Context borrow uses the same lifecycle guard even outside Command.perform.
    try saved.?.withPlugin(ReactivePlugin, ReactivePlugin.increment);
    try std.testing.expectEqual(@as(i64, 2), (try source.read()).*);
    const old = saved.?;
    try runtime.uninstall("reactive");
    try std.testing.expectError(error.InvalidHandle, old.withPlugin(ReactivePlugin, ReactivePlugin.increment));
}
