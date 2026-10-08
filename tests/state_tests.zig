const std = @import("std");
const g = @import("gama");
const App = struct {
    value: ?g.StateRef(i64) = null,
    fail: bool = false,
    show: bool = true,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        if (self.show) self.value = try ctx.state(i64, 1, 3);
        if (self.fail) return error.Unavailable;
        return .empty;
    }
};
test "host retains state and abort preserves generations" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    const value = app.value.?;
    try value.set(8);
    app.fail = true;
    try std.testing.expectError(error.Unavailable, host.rebuild(.{}));
    try std.testing.expectEqual(@as(i64, 8), (try value.read()).*);
    app.fail = false;
    app.show = false;
    try host.rebuild(.{});
    try std.testing.expectError(error.InvalidHandle, value.read());
}

const ReplacingApp = struct {
    kind: enum { integer, string, none } = .integer,
    integer: ?g.StateRef(i64) = null,
    string: ?g.StateRef(g.String) = null,
    fail: bool = false,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        switch (self.kind) {
            .integer => self.integer = try ctx.state(i64, 4, 11),
            .string => self.string = try ctx.state(g.String, 4, .{ .bytes = "hello" }),
            .none => {},
        }
        if (self.fail) return error.Unavailable;
        return .empty;
    }
};
test "replacement abort never resurrects handles and successful replacement diagnoses" {
    var app: ReplacingApp = .{};
    const host = try g.Host(ReplacingApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    const old = app.integer.?;
    app.kind = .string;
    app.fail = true;
    try host.invalidate();
    try std.testing.expectError(error.Unavailable, host.rebuild(.{}));
    const aborted = app.string.?;
    try std.testing.expectError(error.InvalidHandle, aborted.read());
    try std.testing.expectEqual(@as(i64, 11), (try old.read()).*);
    app.fail = false;
    try host.rebuild(.{});
    try std.testing.expectError(error.InvalidHandle, old.read());
    try std.testing.expectError(error.InvalidHandle, aborted.read());
    try std.testing.expectEqual(@as(usize, 1), (try host.transientStateIDs()).len);
    try std.testing.expectEqualStrings("hello", (try app.string.?.read()).bytes);
}
test "host isolation and transaction copies reject double close" {
    var app: App = .{};
    const a = try g.Host(App).create(std.testing.allocator, &app);
    defer a.destroy() catch unreachable;
    const b = try g.Host(App).create(std.testing.allocator, &app);
    defer b.destroy() catch unreachable;
    const prepared = (try a.prepare(.{})).?;
    const first = app.value.?;
    try prepared.commit();
    try std.testing.expectError(error.InvalidTransaction, prepared.abort());
    try b.rebuild(.{});
    try app.value.?.set(99);
    try std.testing.expectEqual(@as(i64, 3), (try first.read()).*);
    try std.testing.expectError(error.InvalidTransaction, b.commit(prepared));
}
const ActionApp = struct {
    refs: [2]?g.StateRef(i64) = .{ null, null },
    enabled: bool = true,
    fail: bool = false,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn increment(ref: *const g.StateRef(i64), _: *anyopaque) g.Error!void {
        try ref.set((try ref.read()).* + 1);
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        var children: [2]g.Node = undefined;
        for (&children, 0..) |*child, i| {
            var sub = ctx.child(@intCast(i));
            const ref = try sub.state(i64, 1, 0);
            self.refs[i] = ref;
            sub.environment.enabled = self.enabled;
            sub.environment.action_identity = .{ .id = "shared", .shortcut = if (i == 0) .{ .codepoint = 'a', .control = true } else null };
            const button = try g.authoring.buttonTitle(&sub, "button", try sub.action(ref, increment));
            child.* = try button.render(&sub);
        }
        if (self.fail) return error.Unavailable;
        return .{ .group = try ctx.retainChildren(&children) };
    }
};
test "node named and shortcut registries remain independent and failed frame retains action" {
    var app: ActionApp = .{};
    const host = try g.Host(ActionApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try std.testing.expect(!try host.perform("shared"));
    try host.rebuild(.{});
    const cached = (try host.actionHandle(g.NodeID.root.child(0))).?;
    try host.handle(.{ .key = .enter });
    try host.handle(.{ .key = .{ .shortcut = .{ .codepoint = 'a', .control = true } } });
    try std.testing.expect(try host.perform("shared"));
    try std.testing.expectEqual(@as(i64, 1), (try app.refs[0].?.read()).*);
    try std.testing.expectEqual(@as(i64, 2), (try app.refs[1].?.read()).*);
    app.fail = true;
    try std.testing.expectError(error.Unavailable, host.rebuild(.{}));
    try std.testing.expect(try cached.invoke());
    app.fail = false;
    app.enabled = false;
    try host.rebuild(.{});
    try std.testing.expectError(error.InvalidHandle, cached.invoke());
    try std.testing.expect(!try host.perform("shared"));
    try std.testing.expect(!try host.needsFrame());
    try host.handle(.{ .pointer_press = .{ .id = .root, .focusable = false } });
    try std.testing.expect(try host.needsFrame());
}
test "quit and tab remain reserved and direct action survives quit" {
    var app: ActionApp = .{};
    const host = try g.Host(ActionApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try host.handle(.{ .key = .tab });
    try host.handle(.{ .key = .space });
    try host.handle(.{ .key = .{ .shortcut = .{ .codepoint = 'c', .control = true } } });
    try std.testing.expect(try host.wantsQuit());
    try std.testing.expect(try host.perform("shared"));
    try std.testing.expectEqual(@as(i64, 2), (try app.refs[1].?.read()).*);
}
const ReentrantApp = struct {
    host: ?*g.Host(@This()) = null,
    errors: usize = 0,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.host.?.invalidate() catch |e| {
            if (e != error.Reentrant) return e;
            self.errors += 1;
        };
        const action = try ctx.action(@as(u8, 0), recurse);
        try ctx.register(.{ .action = .{ .id = .root, .action = action, .identity = .{ .id = "recurse" } } });
        return .empty;
    }
    fn recurse(_: *const u8, raw: *anyopaque) g.Error!void {
        const host: *g.Host(@This()) = @ptrCast(@alignCast(raw));
        host.handle(.tick) catch |e| {
            if (e != error.Reentrant) return e;
            host.app.errors += 1;
        };
        host.destroy() catch |e| {
            if (e != error.Reentrant) return e;
            host.app.errors += 1;
        };
    }
};
test "render and action recursion reject and leave owner usable" {
    var app: ReentrantApp = .{};
    const host = try g.Host(ReentrantApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    app.host = host;
    try host.rebuild(.{});
    try std.testing.expect(try host.perform("recurse"));
    try std.testing.expectEqual(@as(usize, 3), app.errors);
    try host.invalidate();
}
test "completion owns first message cancellation preserves lines and result" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    var message = [_]u8{ 'o', 'k' };
    try host.complete(.{ .message = &message });
    message[0] = 'x';
    try host.complete(.{ .code = 9, .message = "ignored" });
    try host.emit("line");
    try host.cancelAll();
    try std.testing.expectEqualStrings("ok", (try host.completionStatus()).?.message.?);
    const lines = try host.drain();
    defer std.testing.allocator.free(lines);
    for (lines) |line| std.testing.allocator.free(line);
    try std.testing.expectEqual(@as(usize, 1), lines.len);
    const empty = try host.drain();
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expect(g.FailureExitCode.init(0) == null);
    try std.testing.expect(g.FailureExitCode.init(256) == null);
    try std.testing.expect((g.Completion{ .code = 0 }).succeeded());
}
test "shared signal subscriptions deduplicate cancel and detach on destroy" {
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    defer signal.destroy() catch unreachable;
    var app: App = .{};
    const a = try g.Host(App).create(std.testing.allocator, &app);
    var a_alive = true;
    defer if (a_alive) a.destroy() catch unreachable;
    const b = try g.Host(App).create(std.testing.allocator, &app);
    defer b.destroy() catch unreachable;
    try a.observe(signal);
    try a.observe(signal);
    try b.observe(signal);
    try std.testing.expectEqual(@as(usize, 2), signal.observers.items.len);
    try a.rebuild(.{});
    try b.rebuild(.{});
    try a.cancelAll();
    try signal.set(1);
    try std.testing.expect(!try a.needsFrame());
    try std.testing.expect(try b.needsFrame());
    try a.observe(signal);
    try a.destroy();
    a_alive = false;
    try signal.set(2);
    try std.testing.expectEqual(@as(usize, 1), signal.observers.items.len);
}
const Foreign = struct {
    host: *g.Host(ActionApp),
    ref: g.StateRef(i64),
    action: g.Host(ActionApp).ActionHandle,
    signal: *g.Signal(i64),
    signal_ref: g.SignalRef(i64),
    bridge: g.StateRef(i64),
    prepared: g.Host(ActionApp).PreparedFrame,
    failure: ?anyerror = null,
    fn run(self: *@This()) void {
        self.check() catch |e| {
            self.failure = e;
        };
    }
    fn check(self: *@This()) !void {
        try std.testing.expectError(error.WrongThread, self.host.invalidate());
        try std.testing.expectError(error.WrongThread, self.host.handle(.tick));
        try std.testing.expectError(error.WrongThread, self.host.prepare(.{}));
        try std.testing.expectError(error.WrongThread, self.host.destroy());
        try std.testing.expectError(error.WrongThread, self.host.complete(.{}));
        try std.testing.expectError(error.WrongThread, self.host.emit("foreign"));
        try std.testing.expectError(error.WrongThread, self.host.drain());
        try std.testing.expectError(error.WrongThread, self.host.perform("shared"));
        try std.testing.expectError(error.WrongThread, self.host.actionHandle(.root));
        try std.testing.expectError(error.WrongThread, self.host.observe(self.signal));
        try std.testing.expectError(error.WrongThread, self.host.cancelAll());
        try std.testing.expectError(error.WrongThread, self.host.bind(self.signal_ref));
        try std.testing.expectError(error.WrongThread, self.bridge.read());
        try std.testing.expectError(error.WrongThread, self.bridge.set(9));
        try std.testing.expectError(error.WrongThread, self.ref.read());
        try std.testing.expectError(error.WrongThread, self.ref.set(19));
        try std.testing.expectError(error.WrongThread, self.action.invoke());
        try std.testing.expectError(error.WrongThread, self.signal.read());
        try std.testing.expectError(error.WrongThread, self.signal.set(3));
        try std.testing.expectError(error.WrongThread, self.signal.destroy());
        try std.testing.expectError(error.WrongThread, self.signal.observe(self.ref, Snapshot.late));
        try std.testing.expectError(error.WrongThread, self.signal.cancel(.{ .owner = 0, .generation = 0 }));
        try std.testing.expectError(error.WrongThread, self.signal_ref.read());
        try std.testing.expectError(error.WrongThread, self.signal_ref.set(5));
        try std.testing.expectError(error.WrongThread, self.prepared.node());
        try std.testing.expectError(error.WrongThread, self.prepared.allocator());
        try std.testing.expectError(error.WrongThread, self.prepared.commit());
        try std.testing.expectError(error.WrongThread, self.prepared.abort());
        try std.testing.expectError(error.WrongThread, self.host.needsFrame());
        try std.testing.expectError(error.WrongThread, self.host.currentNode());
    }
};
test "public native Host and retained paths reject a joined foreign thread" {
    var accounting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var app: ActionApp = .{};
    const host = try g.Host(ActionApp).create(accounting.allocator(), &app);
    defer host.destroy() catch unreachable;
    const signal = try g.Signal(i64).create(accounting.allocator(), 0);
    defer signal.destroy() catch unreachable;
    try host.rebuild(.{});
    try host.invalidate();
    const prepared = (try host.prepare(.{})).?;
    try host.observe(signal);
    const bridge = try host.bind(try signal.reference());
    var foreign: Foreign = .{ .bridge = bridge, .host = host, .ref = app.refs[0].?, .action = (try host.actionHandle(g.NodeID.root.child(0))).?, .signal = signal, .signal_ref = try signal.reference(), .prepared = prepared };
    const allocation_count = accounting.allocations;
    const deallocation_count = accounting.deallocations;
    const thread = try std.Thread.spawn(.{}, Foreign.run, .{&foreign});
    thread.join();
    try std.testing.expectEqual(allocation_count, accounting.allocations);
    try std.testing.expectEqual(deallocation_count, accounting.deallocations);
    if (foreign.failure) |err| return err;
    try std.testing.expectEqual(@as(i64, 0), (try foreign.ref.read()).*);
    try std.testing.expect(!try host.needsFrame());
    try prepared.abort();
    try std.testing.expect(try foreign.action.invoke());
}
fn allocationScenario(a: std.mem.Allocator) !void {
    var app: ReplacingApp = .{};
    const host = try g.Host(ReplacingApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try app.integer.?.set(42);
    app.kind = .string;
    try host.invalidate();
    try host.rebuild(.{});
    try app.string.?.set(.{ .bytes = "replacement" });
    const signal = try g.Signal(g.String).create(a, .{ .bytes = "shared" });
    defer signal.destroy() catch unreachable;
    try host.observe(signal);
    defer host.cancelAll() catch unreachable;
    try signal.set(.{ .bytes = "next" });
    try host.emit("line");
    try host.complete(.{ .code = 1, .message = "failed" });
    try host.invalidate();
    const frame = (try host.prepare(.{})).?;
    try frame.abort();
}
test "all allocation failures construction state managed writes subscription completion and abort leak-free" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

const Snapshot = struct {
    signal: *g.Signal(i64),
    other: *g.Signal(i64),
    token: g.SubscriptionToken = undefined,
    first_token: g.SubscriptionToken = undefined,
    log: g.StateRef(i64),
    calls: usize = 0,
    fn first(raw: *const anyopaque, ref: g.SignalRef(i64)) g.Error!void {
        const self: *@This() = @ptrCast(@alignCast(@constCast(raw)));
        self.calls += 1;
        try self.signal.cancel(self.token);
        try self.other.cancel(self.token); // Colliding numeric ID belongs to another owner.
        try self.signal.cancel(self.first_token);
        try ref.set(2); // Nested set changes the value, without another pass.
        _ = try self.signal.observe(self.log, late);
    }
    fn later(ref: *const g.StateRef(i64), signal: g.SignalRef(i64)) g.Error!void {
        try ref.set((try ref.read()).* * 10 + (try signal.read()).*);
    }
    fn late(ref: *const g.StateRef(i64), _: g.SignalRef(i64)) g.Error!void {
        try ref.set((try ref.read()).* * 10 + 7);
    }
};
test "signal snapshot cancellation holds capture lifetime nested writes coalesce additions defer foreign tokens ignore" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try app.value.?.set(0);
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    defer signal.destroy() catch unreachable;
    const other = try g.Signal(i64).create(std.testing.allocator, 0);
    defer other.destroy() catch unreachable;
    var snapshot: Snapshot = .{ .signal = signal, .other = other, .log = app.value.? };
    snapshot.first_token = try signal.observeOwner(&snapshot, Snapshot.first);
    snapshot.token = try signal.observe(app.value.?, Snapshot.later);
    _ = try other.observe(app.value.?, Snapshot.late);
    _ = try other.observe(app.value.?, Snapshot.late);
    try signal.set(1);
    try std.testing.expectEqual(@as(usize, 1), snapshot.calls);
    try std.testing.expectEqual(@as(i64, 2), (try app.value.?.read()).*);
    try std.testing.expectEqual(@as(usize, 1), signal.observers.items.len);
    try std.testing.expectEqual(@as(usize, 2), other.observers.items.len);
    try signal.set(3);
    try std.testing.expectEqual(@as(i64, 27), (try app.value.?.read()).*);
    try signal.setIfChanged(3);
    try std.testing.expectEqual(@as(i64, 27), (try app.value.?.read()).*);
}
const TeardownCallback = struct {
    host: *g.Host(App),
    hits: usize = 0,
    fn invoke(raw: *const anyopaque, _: g.SignalRef(i64)) g.Error!void {
        const self: *@This() = @ptrCast(@alignCast(@constCast(raw)));
        try self.host.cancelAll();
        self.host.destroy() catch |e| {
            if (e != error.Reentrant) return e;
            self.hits += 1;
            return;
        };
        return error.Unavailable;
    }
};
test "host teardown during signal snapshot rejects before detaching any owner" {
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    defer signal.destroy() catch unreachable;
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    var callback: TeardownCallback = .{ .host = host };
    _ = try signal.observeOwner(&callback, TeardownCallback.invoke);
    try host.observe(signal);
    try host.rebuild(.{});
    try signal.set(1);
    try std.testing.expectEqual(@as(usize, 1), callback.hits);
    try std.testing.expect(try host.needsFrame());
    try host.cancelAll();
}
test "generation exhaustion fails explicitly without removing published state" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    const ref = app.value.?;
    host.next_generation = std.math.maxInt(u64);
    try host.invalidate();
    try std.testing.expectError(error.GenerationExhausted, host.prepare(.{}));
    try std.testing.expectEqual(@as(i64, 3), (try ref.read()).*);
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    defer signal.destroy() catch unreachable;
    signal.next_id = std.math.maxInt(u64);
    try std.testing.expectError(error.GenerationExhausted, signal.observe(ref, Snapshot.late));
}
const ControlApp = struct {
    value: ?g.StateRef(g.String) = null,
    toggle: ?g.StateRef(bool) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        var field_context = ctx.child(0);
        self.value = try field_context.state(g.String, 1, .{ .bytes = "" });
        const field: g.authoring.TextField = .{ .value = (try self.value.?.read()).bytes, .binding = self.value.?.token };
        var toggle_context = ctx.child(1);
        self.toggle = try toggle_context.state(bool, 1, false);
        const toggle: g.authoring.Toggle = .{ .title = "check", .value = (try self.toggle.?.read()).*, .binding = self.toggle.?.token };
        return .{ .group = try ctx.retainChildren(&.{ try field.render(&field_context), try toggle.render(&toggle_context) }) };
    }
};
test "field generation selection and toggle bindings dispatch grapheme edits space and focus" {
    var app: ControlApp = .{};
    const host = try g.Host(ControlApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try host.handle(.{ .key = .{ .character = "é" } });
    try host.handle(.{ .key = .space });
    try std.testing.expectEqualStrings("é ", (try app.value.?.read()).bytes);
    try host.handle(.{ .key = .backspace });
    try std.testing.expectEqualStrings("é", (try app.value.?.read()).bytes);
    try host.rebuild(.{});
    try host.handle(.{ .key = .backspace });
    try std.testing.expectEqualStrings("", (try app.value.?.read()).bytes);
    try host.handle(.{ .key = .tab });
    try host.handle(.{ .key = .space });
    try std.testing.expect((try app.toggle.?.read()).*);
}
test "accepted edits after prepare remain dirty after commit" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    const p = (try host.prepare(.{})).?;
    try app.value.?.set(7);
    try p.commit();
    try std.testing.expect(try host.needsFrame());
    try std.testing.expectEqual(@as(i64, 7), (try app.value.?.read()).*);
}

test "failed managed clone and completion preserve state generation publication and dirty" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var app: ReplacingApp = .{ .kind = .string };
    const host = try g.Host(ReplacingApp).create(failing.allocator(), &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    const old = app.string.?;
    const published = host.published;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, old.set(.{ .bytes = "new value" }));
    try std.testing.expectEqualStrings("hello", (try old.read()).bytes);
    try std.testing.expect(!try host.needsFrame());
    try std.testing.expectError(error.OutOfMemory, host.complete(.{ .message = "not accepted" }));
    try std.testing.expect((try host.completionStatus()) == null);
    try std.testing.expect(!try host.needsFrame());
    failing.fail_index = std.math.maxInt(usize);
    try old.set(.{ .bytes = "accepted" });
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, host.rebuild(.{}));
    try std.testing.expectEqualStrings("accepted", (try old.read()).bytes);
    try std.testing.expect(host.published == published);
    try std.testing.expect(try host.needsFrame());
}
test "owned teardown accounts every allocated byte and allocation" {
    var accounting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try allocationScenario(accounting.allocator());
    try std.testing.expectEqual(accounting.allocated_bytes, accounting.freed_bytes);
    try std.testing.expectEqual(accounting.allocations, accounting.deallocations);
    try std.testing.expect(accounting.allocations > 10);
}
const ConnectedApp = struct {
    signal: *g.Signal(i64),
    fail: bool = false,
    connections: usize = 0,
    events: usize = 0,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
        return .empty;
    }
    pub fn connect(self: *@This(), host: *g.Host(@This())) g.Error!void {
        self.connections += 1;
        try host.observe(self.signal);
        try host.emit("connected");
        try host.complete(.{ .code = 7, .message = "connected result" });
        if (self.fail) return error.Unavailable;
    }
    pub fn onLifecycle(self: *@This(), _: g.Lifecycle) g.Error!void {
        self.events += 1;
    }
};
test "connect construction failure detaches and addressed lifecycle matches both fields" {
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    defer signal.destroy() catch unreachable;
    var app: ConnectedApp = .{ .signal = signal, .fail = true };
    try std.testing.expectError(error.Unavailable, g.Host(ConnectedApp).create(std.testing.allocator, &app));
    try std.testing.expectEqual(@as(usize, 0), signal.observers.items.len);
    app.fail = false;
    const host = try g.Host(ConnectedApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try host.handle(.{ .lifecycle = .{ .kind = .window_closed, .scene = "other", .instance = host.instance_id } });
    try host.handle(.{ .lifecycle = .{ .kind = .window_closed, .scene = "main", .instance = host.instance_id + 1 } });
    try std.testing.expectEqual(@as(usize, 0), app.events);
    try std.testing.expect(!try host.needsFrame());
    try host.handle(.{ .lifecycle = .{ .kind = .window_closed, .scene = "main", .instance = host.instance_id } });
    try host.handle(.{ .lifecycle = .{ .kind = .did_launch } });
    try std.testing.expectEqual(@as(usize, 2), app.events);
    try std.testing.expect(!try host.wantsQuit());
    try std.testing.expectEqual(@as(i32, 7), (try host.completionStatus()).?.code);
}
test "aborted reuse and repeated removal keep bounded cell indices with fresh generations" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    const original = app.value.?;
    for (0..20) |_| {
        app.show = false;
        try host.invalidate();
        try host.rebuild(.{});
        app.show = true;
        try host.invalidate();
        const candidate = (try host.prepare(.{})).?;
        const aborted = app.value.?;
        try candidate.abort();
        try host.rebuild(.{});
        try std.testing.expectError(error.InvalidHandle, original.read());
        try std.testing.expectError(error.InvalidHandle, aborted.read());
    }
    try std.testing.expectEqual(@as(usize, 1), host.store.entries.items.len);
}

const Counts = struct { clones: usize = 0, releases: usize = 0, hits: usize = 0 };
const ManagedCapture = struct {
    bytes: []const u8,
    counts: *Counts,
    pub fn clone(self: *const @This(), allocator: std.mem.Allocator) g.Error!@This() {
        const bytes = try allocator.dupe(u8, self.bytes);
        self.counts.clones += 1;
        return .{ .bytes = bytes, .counts = self.counts };
    }
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.counts.releases += 1;
        allocator.free(self.bytes);
    }
    fn action(self: *const @This(), _: *anyopaque) g.Error!void {
        if (!std.mem.eql(u8, self.bytes, "owned")) return error.Unavailable;
        self.counts.hits += 1;
    }
    fn signal(self: *const @This(), _: g.SignalRef(i64)) g.Error!void {
        try self.action(undefined);
    }
};
const CapturingApp = struct {
    counts: *Counts,
    fail: bool = false,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        const capture: ManagedCapture = .{ .bytes = "owned", .counts = self.counts };
        const action = try ctx.action(capture, ManagedCapture.action);
        try ctx.register(.{ .action = .{ .id = .root, .action = action, .identity = .{ .id = "owned" } } });
        if (self.fail) return error.Unavailable;
        return .empty;
    }
};
fn captureScenario(a: std.mem.Allocator) !void {
    var counts: Counts = .{};
    defer std.testing.expectEqual(counts.clones, counts.releases) catch unreachable;
    var app: CapturingApp = .{ .counts = &counts };
    const host = try g.Host(CapturingApp).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    _ = try host.perform("owned");
    app.fail = true;
    try host.invalidate();
    host.rebuild(.{}) catch |err| {
        if (err != error.Unavailable) return err;
    };
    _ = try host.perform("owned");
    const signal = try g.Signal(i64).create(a, 0);
    defer signal.destroy() catch unreachable;
    const token = try signal.observe(ManagedCapture{ .bytes = "owned", .counts = &counts }, ManagedCapture.signal);
    try signal.set(1);
    try signal.cancel(token);
}
test "managed action and observer captures clone destroy and abort with allocation sweep" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, captureScenario, .{});
}
const CollectionApp = struct {
    identified: bool = false,
    order: [2]u64 = .{ 7, 8 },
    refs: [2]?g.StateRef(i64) = .{ null, null },
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        for (self.order, 0..) |key, i| {
            var child = if (self.identified) ctx.scoped(.{ .raw = key }) else ctx.child(@intCast(i));
            self.refs[i] = try child.state(i64, 0, @intCast(key));
        }
        return .empty;
    }
};
test "positional state follows positions identified state follows elements" {
    for ([_]bool{ false, true }) |identified| {
        var app: CollectionApp = .{ .identified = identified };
        const host = try g.Host(CollectionApp).create(std.testing.allocator, &app);
        defer host.destroy() catch unreachable;
        try host.rebuild(.{});
        try app.refs[0].?.set(70);
        app.order = .{ 8, 7 };
        try host.rebuild(.{});
        try std.testing.expectEqual(@as(i64, if (identified) 8 else 70), (try app.refs[0].?.read()).*);
        try std.testing.expectEqual(@as(i64, if (identified) 70 else 8), (try app.refs[1].?.read()).*);
        try std.testing.expectEqual(@as(usize, 0), (try host.transientStateIDs()).len);
    }
}

const SameSizeApp = struct {
    signed: bool = true,
    old: ?g.StateRef(i64) = null,
    new: ?g.StateRef(u64) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        if (self.signed) self.old = try ctx.state(i64, 0, -1) else self.new = try ctx.state(u64, 0, 123);
        return .empty;
    }
};
test "same-sized distinct state types validate generation and concrete type before cast" {
    var app: SameSizeApp = .{};
    const host = try g.Host(SameSizeApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    const old = app.old.?;
    const forged_type: g.StateRef(u64) = .{ .owner = old.owner, .token = old.token };
    try std.testing.expectError(error.InvalidHandle, forged_type.read());
    app.signed = false;
    const next_generation = host.store.next_generation;
    host.store.next_generation = std.math.maxInt(u64);
    try host.invalidate();
    try std.testing.expectError(error.GenerationExhausted, host.rebuild(.{}));
    try std.testing.expectEqual(@as(i64, -1), (try old.read()).*);
    host.store.next_generation = next_generation;
    try host.rebuild(.{});
    try std.testing.expectError(error.InvalidHandle, old.read());
    try std.testing.expectError(error.InvalidHandle, old.set(-3));
    try std.testing.expectEqual(@as(u64, 123), (try app.new.?.read()).*);
}
const CancelManaged = struct {
    signal: *g.Signal(i64),
    token: g.SubscriptionToken = undefined,
    counts: *Counts,
    fn cancel(raw: *const anyopaque, _: g.SignalRef(i64)) g.Error!void {
        const self: *@This() = @ptrCast(@alignCast(@constCast(raw)));
        try self.signal.cancel(self.token);
        if (self.counts.releases != 0) return error.Unavailable;
    }
};
test "cancelled managed snapshot capture runs before exactly one destruction" {
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    defer signal.destroy() catch unreachable;
    var counts: Counts = .{};
    var cancellation: CancelManaged = .{ .signal = signal, .counts = &counts };
    _ = try signal.observeOwner(&cancellation, CancelManaged.cancel);
    cancellation.token = try signal.observe(ManagedCapture{ .bytes = "owned", .counts = &counts }, ManagedCapture.signal);
    try signal.set(1);
    try std.testing.expectEqual(@as(usize, 1), counts.hits);
    try std.testing.expectEqual(@as(usize, 1), counts.clones);
    try std.testing.expectEqual(@as(usize, 1), counts.releases);
}
const VirtualApp = struct {
    offset: ?g.StateRef(i64) = null,
    enabled: bool = true,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn identity(i: u64) g.NodeID {
        return .{ .raw = i };
    }
    fn content(_: u64) g.authoring.Text {
        return .{ .content = "row" };
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.offset = try ctx.state(i64, 0, 0);
        ctx.environment.enabled = self.enabled;
        const list: g.authoring.VirtualizedList(u64, g.authoring.Text) = .{ .data = &.{ 1, 2, 3, 4, 5 }, .identity = identity, .content = content };
        return list.render(ctx);
    }
};
test "virtual list captures offset generation and consumes boundary keys while disabled preserves storage" {
    var app: VirtualApp = .{};
    const host = try g.Host(VirtualApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{ .width = 10, .height = 2 });
    const old = app.offset.?;
    try host.handle(.{ .key = .up });
    try std.testing.expect(try host.needsFrame());
    try host.handle(.{ .key = .page_down });
    try std.testing.expectEqual(@as(i64, 2), (try old.read()).*);
    try host.handle(.{ .key = .end });
    try std.testing.expectEqual(@as(i64, 3), (try old.read()).*);
    app.enabled = false;
    try host.rebuild(.{ .width = 10, .height = 2 });
    try host.handle(.{ .key = .home });
    try std.testing.expectEqual(@as(i64, 3), (try old.read()).*);
    try std.testing.expect(!try host.needsFrame());
}
test "text boundary movements and rejected control characters consume and dirty" {
    var app: ControlApp = .{};
    const host = try g.Host(ControlApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try host.handle(.{ .key = .left });
    try std.testing.expect(try host.needsFrame());
    try host.rebuild(.{});
    try host.handle(.{ .key = .{ .character = "\n" } });
    try std.testing.expect(try host.needsFrame());
    try std.testing.expectEqualStrings("", (try app.value.?.read()).bytes);
}
const KeyApp = struct {
    ref: ?g.StateRef(i64) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn key(ref: *const g.StateRef(i64), _: *anyopaque, event: g.Key) g.Error!bool {
        if (event == .enter) return false;
        try ref.set((try ref.read()).* + 10);
        return true;
    }
    fn first(ref: *const g.StateRef(i64), _: *anyopaque, _: g.Key) g.Error!bool {
        try ref.set((try ref.read()).* + 100);
        return true;
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        const ref = try ctx.state(i64, 1, 0);
        self.ref = ref;
        try ctx.register(.{ .key_handler = .{ .id = .root, .handler = try ctx.keyHandler(ref, first) } });
        try ctx.register(.{ .key_handler = .{ .id = .root, .handler = try ctx.keyHandler(ref, key) } });
        try ctx.register(.{ .action = .{ .id = .root, .action = try ctx.action(ref, ActionApp.increment), .identity = .{ .id = "action", .shortcut = .{ .codepoint = 'a' } } } });
        const node: g.Node = .{ .interactive = .{ .id = .root, .focusable = true, .child = try ctx.box(.empty) } };
        return .{ .group = try ctx.retainChildren(&.{ node, node }) };
    }
};
test "key-handler map is independent last-wins first-refusal and reserved tab bypasses it" {
    var app: KeyApp = .{};
    const host = try g.Host(KeyApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try std.testing.expectEqual(@as(usize, 1), (try host.duplicateInteractiveIDs()).len);
    try host.handle(.{ .key = .{ .character = "a" } });
    try std.testing.expectEqual(@as(i64, 10), (try app.ref.?.read()).*);
    try host.handle(.{ .key = .enter });
    try std.testing.expectEqual(@as(i64, 11), (try app.ref.?.read()).*);
    try host.handle(.{ .key = .tab });
    try std.testing.expectEqual(@as(i64, 11), (try app.ref.?.read()).*);
}

test "gamepad presses reuse keyboard actions and releases unmapped buttons stay clean" {
    var app: ActionApp = .{};
    const host = try g.Host(ActionApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try host.handle(.{ .gamepad = .{ .button = .south, .pressed = false } });
    try host.handle(.{ .gamepad = .{ .button = .north, .pressed = true } });
    try std.testing.expect(!try host.needsFrame());
    try host.handle(.{ .gamepad = .{ .button = .south, .pressed = true } });
    try std.testing.expectEqual(@as(i64, 1), (try app.refs[0].?.read()).*);
    try std.testing.expect(g.Completion.failure(0, null).succeeded());
    try std.testing.expectEqual(@as(i32, -3), g.Completion.failure(-3, null).code);
    try std.testing.expectEqual(@as(i32, 1), g.Completion.failureValidated(.general, null).code);
}

test "managed signal equality compares owned string contents instead of borrowed addresses" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try app.value.?.set(0);
    const signal = try g.Signal(g.String).create(std.testing.allocator, .{ .bytes = "same" });
    defer signal.destroy() catch unreachable;
    const Callback = struct {
        fn invoke(ref: *const g.StateRef(i64), _: g.SignalRef(g.String)) g.Error!void {
            try ref.set((try ref.read()).* + 1);
        }
    };
    _ = try signal.observe(app.value.?, Callback.invoke);
    try signal.setIfChanged(.{ .bytes = "same" });
    try std.testing.expectEqual(@as(i64, 0), (try app.value.?.read()).*);
    try signal.setIfChanged(.{ .bytes = "different" });
    try std.testing.expectEqual(@as(i64, 1), (try app.value.?.read()).*);
}

const NestedConstruction = struct {
    signal: *g.Signal(i64),
    count: usize = 0,
    fn invoke(raw: *const anyopaque, _: g.SignalRef(i64)) g.Error!void {
        const self: *@This() = @ptrCast(@alignCast(@constCast(raw)));
        var app: ConnectedApp = .{ .signal = self.signal, .fail = true };
        const failed = g.Host(ConnectedApp).create(std.testing.allocator, &app);
        if (failed) |unexpected| {
            try unexpected.destroy();
            return error.InvalidHandle;
        } else |err| if (err != error.Unavailable) return err;
        app.fail = false;
        const host = try g.Host(ConnectedApp).create(std.testing.allocator, &app);
        try host.destroy(); // Neither new registration belongs to the active snapshot.
        self.count += 1;
    }
};
test "new host subscriptions outside active snapshot can tear down on construction failure" {
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    defer signal.destroy() catch unreachable;
    var construction: NestedConstruction = .{ .signal = signal };
    _ = try signal.observeOwner(&construction, NestedConstruction.invoke);
    try signal.set(1);
    try std.testing.expectEqual(@as(usize, 1), construction.count);
    try std.testing.expectEqual(@as(usize, 1), signal.observers.items.len);
}

const SharedControls = struct {
    text: ?g.StateRef(g.String) = null,
    flag: ?g.StateRef(bool) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        var field = ctx.child(0);
        var toggle = ctx.child(1);
        const a = try (g.authoring.TextField{ .value = (try self.text.?.read()).bytes, .binding = self.text.?.token }).render(&field);
        const b = try (g.authoring.Toggle{ .title = "shared", .value = (try self.flag.?.read()).*, .binding = self.flag.?.token }).render(&toggle);
        return .{ .group = try ctx.retainChildren(&.{ a, b }) };
    }
};
test "explicitly observed signals bind shared controls with subscription lifetime and revocation" {
    const text = try g.Signal(g.String).create(std.testing.allocator, .{ .bytes = "hi" });
    defer text.destroy() catch unreachable;
    const flag = try g.Signal(bool).create(std.testing.allocator, false);
    defer flag.destroy() catch unreachable;
    var a: SharedControls = .{};
    var b: SharedControls = .{};
    const first = try g.Host(SharedControls).create(std.testing.allocator, &a);
    defer first.destroy() catch unreachable;
    const second = try g.Host(SharedControls).create(std.testing.allocator, &b);
    defer second.destroy() catch unreachable;
    try std.testing.expectError(error.Unavailable, first.bind(try text.reference()));
    try first.observe(text);
    try first.observe(flag);
    try second.observe(text);
    try second.observe(flag);
    a.text = try first.bind(try text.reference());
    a.flag = try first.bind(try flag.reference());
    b.text = try second.bind(try text.reference());
    b.flag = try second.bind(try flag.reference());
    const repeated = try first.bind(try text.reference());
    try std.testing.expectEqual(a.text.?.token, repeated.token);
    try first.rebuild(.{});
    try second.rebuild(.{});
    const BusyCancel = struct {
        fn invoke(raw: *const anyopaque, _: g.SignalRef(g.String)) g.Error!void {
            const owner: *g.Host(SharedControls) = @ptrCast(@alignCast(@constCast(raw)));
            if (owner.cancelAll()) return error.Unavailable else |err| if (err != error.Reentrant) return err;
            if (owner.destroy()) return error.Unavailable else |err| if (err != error.Reentrant) return err;
        }
    };
    const busy_token = try text.observeOwner(first, BusyCancel.invoke);
    try first.handle(.{ .key = .end });
    try first.handle(.{ .key = .{ .character = "!" } });
    try text.cancel(busy_token);
    try std.testing.expectEqualStrings("hi!", (try text.read()).bytes);
    try std.testing.expectEqualStrings("hi!", (try b.text.?.read()).bytes);
    try std.testing.expect(try first.needsFrame());
    try std.testing.expect(try second.needsFrame());
    try first.handle(.{ .key = .tab });
    try first.handle(.{ .key = .space });
    try std.testing.expect((try flag.read()).*);
    try first.cancelAll();
    try std.testing.expectError(error.InvalidHandle, a.text.?.read());
    try std.testing.expectError(error.InvalidHandle, a.flag.?.set(false));
    try b.flag.?.set(false);
    try std.testing.expect(!(try flag.read()).*);
    try first.observe(text);
    const fresh = try first.bind(try text.reference());
    try std.testing.expect(fresh.token.generation != a.text.?.token.generation);
    try std.testing.expectError(error.InvalidHandle, a.text.?.read());
    try std.testing.expectEqualStrings("hi!", (try fresh.read()).bytes);
}

fn bridgeAllocationScenario(a: std.mem.Allocator) !void {
    const signal = try g.Signal(g.String).create(a, .{ .bytes = "original" });
    defer signal.destroy() catch unreachable;
    var app: App = .{ .show = false };
    const host = try g.Host(App).create(a, &app);
    defer host.destroy() catch unreachable;
    try host.observe(signal);
    const ref = try host.bind(try signal.reference());
    try host.rebuild(.{}); // No control in the frame: subscription owns the bridge.
    try ref.set(.{ .bytes = "updated" });
    try std.testing.expectEqualStrings("updated", (try ref.read()).bytes);
    try host.rebuild(.{});
    try std.testing.expectEqualStrings("updated", (try ref.read()).bytes);
    try host.cancelAll();
    try std.testing.expectError(error.InvalidHandle, ref.read());
    try host.observe(signal);
    const next = try host.bind(try signal.reference());
    try std.testing.expect(next.token.generation != ref.token.generation);
}
test "subscription bridges sweep allocation failures and release all bytes without owning signals" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, bridgeAllocationScenario, .{});
    var accounting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try bridgeAllocationScenario(accounting.allocator());
    try std.testing.expectEqual(accounting.allocated_bytes, accounting.freed_bytes);
    try std.testing.expectEqual(accounting.allocations, accounting.deallocations);
}
test "bridge managed write failure leaves source borrowed value and subscribed hosts clean" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const signal = try g.Signal(g.String).create(failing.allocator(), .{ .bytes = "old" });
    defer signal.destroy() catch unreachable;
    var app: App = .{ .show = false };
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.observe(signal);
    const ref = try host.bind(try signal.reference());
    try host.rebuild(.{});
    const before = try ref.read();
    const bytes = before.bytes.ptr;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, ref.set(.{ .bytes = "replacement" }));
    try std.testing.expectEqualStrings("old", before.bytes);
    try std.testing.expectEqual(bytes, (try ref.read()).bytes.ptr);
    try std.testing.expect(!try host.needsFrame());
    failing.fail_index = std.math.maxInt(usize);
    var source = [_]u8{ 'n', 'e', 'w' };
    try ref.set(.{ .bytes = &source });
    source[0] = 'X';
    try std.testing.expectEqualStrings("new", (try ref.read()).bytes);
    try std.testing.expect(try host.needsFrame());
}
const CancelBridge = struct {
    host: *g.Host(App),
    ref: g.StateRef(i64),
    fn invoke(raw: *const anyopaque, _: g.SignalRef(i64)) g.Error!void {
        const self: *const @This() = @ptrCast(@alignCast(raw));
        try self.host.cancelAll();
        if (self.ref.read()) |_| return error.Unavailable else |err| if (err != error.InvalidHandle) return err;
    }
};
test "notification cancellation revokes bridges immediately while snapshot retains host and signal detach stays safe" {
    const signal = try g.Signal(i64).create(std.testing.allocator, 0);
    var app: App = .{ .show = false };
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    var cancel: CancelBridge = .{ .host = host, .ref = undefined };
    _ = try signal.observeOwner(&cancel, CancelBridge.invoke);
    try host.observe(signal);
    cancel.ref = try host.bind(try signal.reference());
    try cancel.ref.set(1); // Callback frees the bridge capture before this delegation returns.
    try std.testing.expectError(error.InvalidHandle, cancel.ref.read());
    try host.observe(signal);
    cancel.ref = try host.bind(try signal.reference());
    try signal.set(2);
    try std.testing.expectError(error.InvalidHandle, cancel.ref.read());
    try signal.destroy();
    try std.testing.expectError(error.InvalidHandle, cancel.ref.set(2));
    try host.cancelAll(); // Detached records no longer dereference the destroyed Signal.
    const other = try g.Signal(i64).create(std.testing.allocator, 4);
    try host.observe(other);
    const attached = try host.bind(try other.reference());
    try other.destroy(); // Tracked source detach also revokes an active bridge.
    try std.testing.expectError(error.InvalidHandle, attached.read());
}

const ReobserveSnapshot = struct {
    host: *g.Host(App),
    signal: *g.Signal(i64),
    bridge: ?g.StateRef(i64) = null,
    host_alive: bool = true,
    rejected: usize = 0,
    fn invoke(raw: *const anyopaque, _: g.SignalRef(i64)) g.Error!void {
        const self: *@This() = @ptrCast(@alignCast(@constCast(raw)));
        try self.host.cancelAll();
        try self.host.observe(self.signal);
        try self.host.observe(self.signal); // Deduplicate the live record beyond the old attachment.
        self.bridge = try self.host.bind(try self.signal.reference());
        self.host.destroy() catch |err| {
            if (err != error.Reentrant) return err;
            self.rejected += 1;
            return;
        };
        self.host_alive = false;
        return error.Unavailable;
    }
};
fn reobserveSnapshotScenario(a: std.mem.Allocator) !void {
    const signal = try g.Signal(i64).create(a, 0);
    defer signal.destroy() catch unreachable;
    var app: App = .{ .show = false };
    const host = try g.Host(App).create(a, &app);
    var callback: ReobserveSnapshot = .{ .host = host, .signal = signal };
    defer if (callback.host_alive) host.destroy() catch unreachable;
    const token = try signal.observeOwner(&callback, ReobserveSnapshot.invoke);
    try host.observe(signal);
    const old = try host.bind(try signal.reference());
    try signal.set(1);
    try std.testing.expectEqual(@as(usize, 1), callback.rejected);
    try std.testing.expectError(error.InvalidHandle, old.read());
    // Releasing the canceled snapshot token must not revoke its newer live bridge.
    try std.testing.expectEqual(@as(i64, 1), (try callback.bridge.?.read()).*);
    try std.testing.expectEqual(@as(usize, 2), signal.observers.items.len);
    try signal.cancel(token);
    try callback.bridge.?.set(2);
    try std.testing.expectEqual(@as(i64, 2), (try signal.read()).*);
    try host.destroy();
    callback.host_alive = false;
    try std.testing.expectEqual(@as(usize, 0), signal.observers.items.len);
}
test "cancel reobserve destroy retains old snapshot attachment and newer bridge" {
    try reobserveSnapshotScenario(std.testing.allocator);
}
test "snapshot reobservation allocation failures retain safe teardown and balance allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, reobserveSnapshotScenario, .{});
    var accounting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try reobserveSnapshotScenario(accounting.allocator());
    try std.testing.expectEqual(accounting.allocated_bytes, accounting.freed_bytes);
    try std.testing.expectEqual(accounting.allocations, accounting.deallocations);
}

const NumericVectorApp = struct {
    value: ?g.StateRef(@Vector(2, i32)) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.value = try ctx.state(@Vector(2, i32), 1, .{ 3, 5 });
        return .empty;
    }
};
test "numeric vector state and nested optional vector signals remain owned plain values" {
    var app: NumericVectorApp = .{};
    const host = try g.Host(NumericVectorApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try std.testing.expect(@reduce(.And, (try app.value.?.read()).* == @as(@Vector(2, i32), .{ 3, 5 })));
    try app.value.?.set(.{ 7, 11 });
    try host.rebuild(.{});
    try std.testing.expect(@reduce(.And, (try app.value.?.read()).* == @as(@Vector(2, i32), .{ 7, 11 })));
    const Value = struct { values: [1]?@Vector(2, u32) };
    const signal = try g.Signal(Value).create(std.testing.allocator, .{ .values = .{.{ 1, 2 }} });
    defer signal.destroy() catch unreachable;
    try signal.set(.{ .values = .{.{ 8, 13 }} });
    try std.testing.expect(@reduce(.And, (try signal.read()).values[0].? == @as(@Vector(2, u32), .{ 8, 13 })));
}
