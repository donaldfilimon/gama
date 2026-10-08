const std = @import("std");
const g = @import("gama");
const App = struct {
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        const state = try ctx.state(i64, 0, 0);
        try state.set(1);
        return .empty;
    }
};
test "render-time accepted state write survives dirty reset" {
    var app: App = .{};
    const host = try g.Host(App).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try std.testing.expect(try host.needsFrame());
}

const OutcomeProbeApp = struct {
    host: ?*g.Host(@This()) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    pub fn connect(self: *@This(), host: *g.Host(@This())) g.Error!void {
        self.host = host;
    }
    fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        try ctx.register(.{ .action = .{ .id = .root, .identity = .{ .id = "finish" }, .action = try ctx.action(@as(u8, 0), finish) } });
        return .empty;
    }
    fn finish(_: *const u8, raw: *anyopaque) g.Error!void {
        const host: *g.Host(@This()) = @ptrCast(@alignCast(raw));
        try host.complete(.success());
    }
    pub fn onLifecycle(self: *@This(), event: g.Lifecycle) g.Error!void {
        if (event.kind == .did_launch) try self.host.?.emit("launched");
    }
};
test "normal action can declare application completion" {
    var app: OutcomeProbeApp = .{};
    const host = try g.Host(OutcomeProbeApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try std.testing.expect(try host.perform("finish"));
    try std.testing.expect((try host.completionStatus()) != null);
}
test "lifecycle can emit an application semantic line" {
    var app: OutcomeProbeApp = .{};
    const host = try g.Host(OutcomeProbeApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.handle(.{ .lifecycle = .{ .kind = .did_launch } });
    try std.testing.expectEqual(@as(usize, 1), (try host.pendingLines()).len);
}

const OutcomeApp = struct {
    host: ?*g.Host(@This()) = null,
    mode: enum { finish, line, complete, signal, bridge, fail } = .finish,
    launched: bool = false,
    finished: bool = false,
    key: bool = false,
    guards: usize = 0,
    signal: ?*g.Signal(i64) = null,
    bridge: ?g.StateRef(i64) = null,
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    pub fn connect(self: *@This(), host: *g.Host(@This())) g.Error!void {
        self.host = host;
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        rejected(self.host.?);
        try ctx.register(.{ .action = .{ .id = .root, .identity = .{ .id = "finish" }, .action = try ctx.action(@as(u8, 0), action) } });
        if (self.key) try ctx.register(.{ .key_handler = .{ .id = .root, .handler = try ctx.keyHandler(@as(u8, 0), onKey) } });
        return .{ .interactive = .{ .id = .root, .focusable = true, .child = try ctx.box(.{ .text = .{ .content = if (self.finished) "done" else "ready" } }) } };
    }
    fn rejected(host: *g.Host(@This())) void {
        std.testing.expectError(error.Reentrant, host.complete(.success())) catch unreachable;
        std.testing.expectError(error.Reentrant, host.emit("forbidden")) catch unreachable;
    }
    fn action(_: *const u8, raw: *anyopaque) g.Error!void {
        const host: *g.Host(@This()) = @ptrCast(@alignCast(raw));
        try host.app.submit();
    }
    fn onKey(_: *const u8, raw: *anyopaque, _: g.Key) g.Error!bool {
        const host: *g.Host(@This()) = @ptrCast(@alignCast(raw));
        try host.app.submit();
        return true;
    }
    fn submit(self: *@This()) g.Error!void {
        const host = self.host.?;
        std.testing.expectError(error.Reentrant, host.destroy()) catch unreachable;
        std.testing.expectError(error.Reentrant, host.prepare(.{})) catch unreachable;
        std.testing.expectError(error.Reentrant, host.handle(.tick)) catch unreachable;
        std.testing.expectError(error.Reentrant, host.invalidate()) catch unreachable;
        std.testing.expectError(error.Reentrant, host.perform("finish")) catch unreachable;
        std.testing.expectError(error.Reentrant, host.consumeLines(0)) catch unreachable;
        std.testing.expectError(error.Reentrant, host.drain()) catch unreachable;
        self.guards += 7;
        defer {
            // Successful, failed and no-op outcomes must retain the enclosing dispatch guard.
            std.testing.expectError(error.Reentrant, host.destroy()) catch unreachable;
            std.testing.expectError(error.Reentrant, host.prepare(.{})) catch unreachable;
        }
        switch (self.mode) {
            .line => try host.emit("action"),
            .complete => try host.complete(.failure(7, "message")),
            .signal => try self.signal.?.set(1),
            .bridge => try self.bridge.?.set(2),
            .fail => return error.Unavailable,
            .finish => {
                var line = [_]u8{ 'l', 'i', 'n', 'e' };
                var message = [_]u8{ 'd', 'o', 'n', 'e' };
                try host.emit(&line);
                try host.complete(.failure(7, &message));
                @memset(&line, 'x');
                @memset(&message, 'x');
                try host.complete(.failure(9, "ignored"));
                self.finished = true;
            },
        }
    }
    pub fn onLifecycle(self: *@This(), event: g.Lifecycle) g.Error!void {
        if (event.kind == .did_launch and !self.launched) {
            try self.host.?.emit("launched");
            self.launched = true;
        }
    }
};
const OutcomeSurface = struct {
    output: std.ArrayList(u8) = .empty,
    event: ?g.Event = .{ .activate = .root },
    interactive: bool = false,
    fail: bool = false,
    ends: usize = 0,
    pub fn begin(_: *@This()) g.Error!void {}
    pub fn end(self: *@This()) g.Error!void {
        self.ends += 1;
    }
    pub fn extent(_: *@This()) g.Error!g.geometry.Size {
        return .{ .width = 8, .height = 1 };
    }
    pub fn waitsForInput(self: *@This()) bool {
        return self.interactive;
    }
    pub fn next(self: *@This(), _: i32) g.Error!?g.Event {
        const event = self.event;
        self.event = null;
        return event;
    }
    pub fn write(self: *@This(), bytes: []const u8) g.Error!void {
        try self.output.appendSlice(std.testing.allocator, if (self.fail) bytes[0..@min(2, bytes.len)] else bytes);
        if (self.fail) return error.IOFailure;
    }
};
test "callback outcomes reach plain and interactive loop with owned message first result and final frame" {
    for ([_]bool{ false, true }) |interactive| {
        var app: OutcomeApp = .{};
        const host = try g.Host(OutcomeApp).create(std.testing.allocator, &app);
        defer host.destroy() catch unreachable;
        var surface: OutcomeSurface = .{ .interactive = interactive };
        defer surface.output.deinit(std.testing.allocator);
        const result = try g.tui.run(host, &surface);
        try std.testing.expect(result.declared);
        try std.testing.expectEqual(@as(i32, 7), result.completion.code);
        try std.testing.expectEqualStrings("done", result.completion.message.?);
        if (interactive) try std.testing.expect(std.mem.indexOf(u8, surface.output.items, "done") != null);
        if (!interactive) try std.testing.expectEqualStrings("launched\nline\n", surface.output.items);
        try std.testing.expectEqualStrings("done", (try host.currentTree()).?.node.interactive.child.text.content);
        try std.testing.expectEqual(@as(usize, 0), (try host.pendingLines()).len);
        try std.testing.expectEqual(@as(usize, 7), app.guards);
        try std.testing.expectEqual(@as(usize, 1), surface.ends);
        // will_terminate is another live lifecycle callback and invalidates afterward.
        try std.testing.expect(try host.needsFrame());
    }
}
test "focused key callbacks submit outcomes and failing callback restores admission" {
    var app: OutcomeApp = .{ .key = true, .mode = .fail };
    const host = try g.Host(OutcomeApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try std.testing.expectError(error.Unavailable, host.handle(.{ .key = .enter }));
    try host.invalidate();
    try host.rebuild(.{}); // render submission still rejects after callback error
    app.mode = .finish;
    try host.handle(.{ .key = .enter });
    try std.testing.expectEqualStrings("done", (try host.completionStatus()).?.message.?);
    try std.testing.expectEqualStrings("line", (try host.pendingLines())[0]);
    try std.testing.expect(try host.needsFrame());
}
test "callback lines retain failed transport prefix and later lines until explicit delivery acknowledgement" {
    var app: OutcomeApp = .{ .mode = .line };
    const host = try g.Host(OutcomeApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    var surface: OutcomeSurface = .{ .fail = true, .event = null };
    defer surface.output.deinit(std.testing.allocator);
    var draw = try g.DrawingPump(OutcomeApp).init(std.testing.allocator, host, .plain);
    defer draw.deinit();
    try host.rebuild(.{ .width = 8, .height = 1 });
    const old = (try host.currentTree()).?;
    try std.testing.expect(try host.perform("finish"));
    try std.testing.expectError(error.IOFailure, draw.advanceDelivered(&surface, OutcomeSurface.write, try host.pendingLines()));
    try std.testing.expect((try host.currentTree()).? == old);
    try std.testing.expect(try host.needsFrame());
    try std.testing.expectEqualStrings("action", (try host.pendingLines())[0]);
    const count = (try host.pendingLines()).len;
    surface.fail = false;
    _ = try draw.advanceDelivered(&surface, OutcomeSurface.write, try host.pendingLines());
    // Appending after delivery must not be swallowed by acknowledgement of the sent prefix.
    try std.testing.expect(try host.perform("finish"));
    try host.consumeLines(count);
    try std.testing.expectEqual(@as(usize, 1), (try host.pendingLines()).len);
    _ = try draw.advanceDelivered(&surface, OutcomeSurface.write, try host.pendingLines());
    try host.consumeLines(1);
    try std.testing.expectEqualStrings("acaction\naction\n", surface.output.items);
}
test "callback outcome OOM accepts no result or line at clone and queue allocation failures" {
    for (0..3) |failure| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var app: OutcomeApp = .{ .mode = if (failure == 0) .complete else .line };
        const host = try g.Host(OutcomeApp).create(failing.allocator(), &app);
        defer host.destroy() catch unreachable;
        try host.rebuild(.{});
        failing.fail_index = failing.alloc_index + @intFromBool(failure == 2);
        try std.testing.expectError(error.OutOfMemory, host.perform("finish"));
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expect((try host.completionStatus()) == null);
        try std.testing.expectEqual(@as(usize, 0), (try host.pendingLines()).len);
        try std.testing.expect(!try host.needsFrame());
        failing.fail_index = std.math.maxInt(usize);
        try std.testing.expect(try host.perform("finish"));
        try std.testing.expect(try host.needsFrame());
    }
}
const OutcomeObserver = struct {
    host: *g.Host(OutcomeApp),
    reject: bool = false,
    calls: usize = 0,
    fn notify(raw: *const anyopaque, _: g.SignalRef(i64)) g.Error!void {
        const self: *@This() = @ptrCast(@alignCast(@constCast(raw)));
        self.calls += 1;
        if (self.reject) {
            OutcomeApp.rejected(self.host);
        } else {
            try self.host.emit("observed");
            try self.host.complete(.failure(3, "observer"));
        }
        std.testing.expectError(error.Reentrant, self.host.destroy()) catch unreachable;
    }
};
test "signal observer outcomes admitted idle and live callback but rejected during bridged store write" {
    for (0..3) |mode| {
        const signal = try g.Signal(i64).create(std.testing.allocator, 0);
        defer signal.destroy() catch unreachable;
        var app: OutcomeApp = .{ .signal = signal, .mode = if (mode == 2) .bridge else .signal };
        const host = try g.Host(OutcomeApp).create(std.testing.allocator, &app);
        defer host.destroy() catch unreachable;
        try host.observe(signal);
        app.bridge = try host.bind(try signal.reference());
        var observer: OutcomeObserver = .{ .host = host, .reject = mode == 2 };
        const token = try signal.observeOwner(&observer, OutcomeObserver.notify);
        defer signal.cancel(token) catch unreachable;
        try host.rebuild(.{});
        if (mode == 0) try signal.set(1) else try std.testing.expect(try host.perform("finish"));
        try std.testing.expectEqual(@as(usize, 1), observer.calls);
        try std.testing.expectEqual(mode == 2, (try host.completionStatus()) == null);
        try std.testing.expectEqual(@as(usize, if (mode == 2) 0 else 1), (try host.pendingLines()).len);
        if (mode == 2) {
            // Direct bridge writes have the same exclusion even without a surrounding callback.
            try app.bridge.?.set(3);
            try host.complete(.success()); // deferral until the store mutation returns is admitted
        }
    }
}
test "native foreign-thread outcomes fail during an otherwise admitted live callback" {
    const ForeignApp = struct {
        pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
        fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
            try ctx.register(.{ .action = .{ .id = .root, .identity = .{ .id = "foreign" }, .action = try ctx.action(@as(u8, 0), action) } });
            return .empty;
        }
        fn other(host: *g.Host(@This())) void {
            std.testing.expectError(error.WrongThread, host.complete(.success())) catch unreachable;
            std.testing.expectError(error.WrongThread, host.emit("foreign")) catch unreachable;
        }
        fn action(_: *const u8, raw: *anyopaque) g.Error!void {
            const host: *g.Host(@This()) = @ptrCast(@alignCast(raw));
            const thread = std.Thread.spawn(.{}, other, .{host}) catch unreachable;
            thread.join();
            try host.complete(.success());
        }
    };
    var app: ForeignApp = .{};
    const host = try g.Host(ForeignApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try std.testing.expect(try host.perform("foreign"));
    try std.testing.expect((try host.completionStatus()) != null);
    try std.testing.expectEqual(@as(usize, 0), (try host.pendingLines()).len);
}

const ReenterAllocator = struct {
    host: ?*g.Host(OutcomeApp) = null,
    hits: usize = 0,
    fn probe(self: *@This()) void {
        if (self.host) |host| {
            OutcomeApp.rejected(host);
            self.hits += 1;
        }
    }
    fn allocator(self: *@This()) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.probe();
        return std.testing.allocator.rawAlloc(len, alignment, ret);
    }
    fn resize(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.probe();
        return std.testing.allocator.rawResize(memory, alignment, len, ret);
    }
    fn remap(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.probe();
        return std.testing.allocator.rawRemap(memory, alignment, len, ret);
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.probe();
        std.testing.allocator.rawFree(memory, alignment, ret);
    }
};
test "outcome allocator and owner teardown cannot reenter callback admission" {
    var allocator: ReenterAllocator = .{};
    var app: OutcomeApp = .{};
    const host = try g.Host(OutcomeApp).create(allocator.allocator(), &app);
    try host.rebuild(.{});
    allocator.host = host;
    try std.testing.expect(try host.perform("finish"));
    try std.testing.expect(allocator.hits >= 3); // line copy, line array, message copy
    try std.testing.expectEqualStrings("line", (try host.pendingLines())[0]);
    const before_destroy = allocator.hits;
    try host.destroy();
    allocator.host = null;
    try std.testing.expect(allocator.hits > before_destroy);
}
const ManagedApp = struct {
    host: ?*g.Host(@This()) = null,
    value: ?g.StateRef(Managed) = null,
    clones: usize = 0,
    frees: usize = 0,
    const Managed = struct {
        host: *g.Host(ManagedApp),
        pub fn clone(self: *const @This(), _: std.mem.Allocator) g.Error!@This() {
            reject(self.host);
            self.host.app.clones += 1;
            return self.*;
        }
        pub fn deinit(self: *@This(), _: std.mem.Allocator) void {
            reject(self.host);
            self.host.app.frees += 1;
        }
        fn reject(host: *g.Host(ManagedApp)) void {
            std.testing.expectError(error.Reentrant, host.complete(.success())) catch unreachable;
            std.testing.expectError(error.Reentrant, host.emit("internal")) catch unreachable;
        }
    };
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    pub fn connect(self: *@This(), host: *g.Host(@This())) g.Error!void {
        self.host = host;
    }
    fn render(self: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        self.value = try ctx.state(Managed, 0, .{ .host = self.host.? });
        try ctx.register(.{ .action = .{ .id = .root, .identity = .{ .id = "mutate" }, .action = try ctx.action(Managed{ .host = self.host.? }, action) } });
        return .empty;
    }
    fn action(capture: *const Managed, _: *anyopaque) g.Error!void {
        try capture.host.app.value.?.set(capture.*);
        try capture.host.complete(.success()); // admission resumes after clone/deinit
    }
};
test "managed state and capture clone deinit callbacks reject outcomes through mutation publication and destruction" {
    var app: ManagedApp = .{};
    const host = try g.Host(ManagedApp).create(std.testing.allocator, &app);
    try host.rebuild(.{});
    try std.testing.expect(try host.perform("mutate"));
    try host.rebuild(.{});
    try std.testing.expect(app.clones >= 4 and app.frees >= 2);
    const frees = app.frees;
    try host.destroy();
    try std.testing.expect(app.frees > frees);
}
test "lifecycle callback completion reaches adaptive explicit plain caller with message" {
    const LaunchApp = struct {
        host: ?*g.Host(@This()) = null,
        pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
        pub fn connect(self: *@This(), host: *g.Host(@This())) g.Error!void {
            self.host = host;
        }
        fn render(_: *@This(), _: *g.BuildContext) g.Error!g.Node {
            return .empty;
        }
        pub fn onLifecycle(self: *@This(), event: g.Lifecycle) g.Error!void {
            if (event.kind == .did_launch) {
                try self.host.?.emit("adaptive callback line");
                try self.host.?.complete(.failure(4, "adaptive callback message"));
            }
        }
    };
    var app: LaunchApp = .{};
    const host = try g.Host(LaunchApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    const result = try g.tui.runAdaptive(host, std.testing.io, &.{"--gama-plain"});
    try std.testing.expect(result.declared);
    try std.testing.expectEqual(@as(i32, 4), result.completion.code);
    try std.testing.expectEqualStrings("adaptive callback message", result.completion.message.?);
    try std.testing.expectEqual(@as(usize, 0), (try host.pendingLines()).len);
}

test "plain runtime failed lifecycle line delivery retains queue and succeeds on retry" {
    var app: OutcomeApp = .{};
    const host = try g.Host(OutcomeApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    var surface: OutcomeSurface = .{ .fail = true };
    defer surface.output.deinit(std.testing.allocator);
    try std.testing.expectError(error.IOFailure, g.tui.run(host, &surface));
    try std.testing.expect((try host.currentTree()) == null);
    try std.testing.expectEqualStrings("launched", (try host.pendingLines())[0]);
    try std.testing.expect(try host.needsFrame());
    surface.fail = false;
    const result = try g.tui.run(host, &surface);
    try std.testing.expect(result.declared);
    try std.testing.expectEqualStrings("done", result.completion.message.?);
    try std.testing.expectEqualStrings("lalaunched\nline\n", surface.output.items);
    try std.testing.expectEqual(@as(usize, 0), (try host.pendingLines()).len);
    try std.testing.expectEqual(@as(usize, 2), surface.ends);
}
test "outcome OOM preserves existing prefix and accepted completion without allocating again" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var app: OutcomeApp = .{ .mode = .line };
    const host = try g.Host(OutcomeApp).create(failing.allocator(), &app);
    defer host.destroy() catch unreachable;
    try host.rebuild(.{});
    try std.testing.expect(try host.perform("finish"));
    const first = (try host.pendingLines())[0];
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, host.perform("finish"));
    try std.testing.expectEqual(@as(usize, 1), (try host.pendingLines()).len);
    try std.testing.expect(first.ptr == (try host.pendingLines())[0].ptr);
    failing.fail_index = std.math.maxInt(usize);
    app.mode = .complete;
    try std.testing.expect(try host.perform("finish"));
    const message = (try host.completionStatus()).?.message.?;
    failing.fail_index = failing.alloc_index;
    try std.testing.expect(try host.perform("finish"));
    try std.testing.expect(message.ptr == (try host.completionStatus()).?.message.?.ptr);
    try std.testing.expectEqualStrings("message", message);
}
test "downstream staging and transport callbacks cannot submit outcomes" {
    var app: OutcomeApp = .{};
    const host = try g.Host(OutcomeApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    const Downstream = struct {
        fn stage(owner: *g.Host(OutcomeApp), _: g.Host(OutcomeApp).Preparation) g.Error![]const u8 {
            OutcomeApp.rejected(owner);
            return "frame";
        }
        fn write(owner: *g.Host(OutcomeApp), _: []const u8) g.Error!void {
            OutcomeApp.rejected(owner);
        }
    };
    const prepared = (try host.prepare(.{})).?;
    try prepared.stage(host, Downstream.stage);
    try prepared.deliver(host, Downstream.write);
    try std.testing.expect((try host.completionStatus()) == null);
    try std.testing.expectEqual(@as(usize, 0), (try host.pendingLines()).len);
}

const SignalManagedApp = struct {
    signal: ?*g.Signal(Value) = null,
    rejected: usize = 0,
    accepted: usize = 0,
    const Value = struct {
        host: ?*g.Host(SignalManagedApp) = null,
        pub fn clone(self: *const @This(), _: std.mem.Allocator) g.Error!@This() {
            try self.probe();
            return self.*;
        }
        pub fn deinit(self: *@This(), _: std.mem.Allocator) void {
            self.probe() catch unreachable;
        }
        fn probe(self: *const @This()) g.Error!void {
            const host = self.host orelse return;
            host.emit("internal signal") catch |err| {
                if (err != error.Reentrant) return err;
                host.app.rejected += 1;
                host.complete(.success()) catch |completion_err| {
                    if (completion_err != error.Reentrant) return completion_err;
                    host.app.rejected += 1;
                    return;
                };
            };
            host.app.accepted += 1;
        }
    };
    pub const scenes = [_]g.scenes.Descriptor(@This()){.{ .id = "main", .role = .primary, .render = render }};
    fn render(_: *@This(), ctx: *g.BuildContext) g.Error!g.Node {
        try ctx.register(.{ .action = .{ .id = .root, .identity = .{ .id = "signal" }, .action = try ctx.action(@as(u8, 0), action) } });
        return .empty;
    }
    fn action(_: *const u8, raw: *anyopaque) g.Error!void {
        const host: *g.Host(@This()) = @ptrCast(@alignCast(raw));
        try host.app.signal.?.set(.{ .host = host });
        try host.app.signal.?.set(.{ .host = host });
        try host.app.signal.?.set(.{}); // release the last borrowed host before its destruction
        try host.emit("after signal mutation");
    }
};
test "observed signal clone and deinit cannot use enclosing application outcome admission" {
    const signal = try g.Signal(SignalManagedApp.Value).create(std.testing.allocator, .{});
    defer signal.destroy() catch unreachable;
    var app: SignalManagedApp = .{ .signal = signal };
    const host = try g.Host(SignalManagedApp).create(std.testing.allocator, &app);
    defer host.destroy() catch unreachable;
    try host.observe(signal);
    try host.rebuild(.{});
    try std.testing.expect(try host.perform("signal"));
    try std.testing.expectEqual(@as(usize, 8), app.rejected);
    try std.testing.expectEqual(@as(usize, 0), app.accepted);
    try std.testing.expect((try host.completionStatus()) == null);
    try std.testing.expectEqual(@as(usize, 1), (try host.pendingLines()).len);
    try std.testing.expectEqualStrings("after signal mutation", (try host.pendingLines())[0]);
}
