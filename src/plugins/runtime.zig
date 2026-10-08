//! Cooperative static Tier-1 plugins. No loader, process isolation or native windows.
//! Plugin values are copied into runtime storage. Any pointers within them are explicit
//! application borrows and must outlive installation/activation. Deactivate releases
//! plugin-owned resources after successful activation only; failed activate cleans its own.
//! Stable leases/metadata (including failed candidates) remain allocated until runtime destroy;
//! uninstall releases payload and detaches observations; lease records remain for cached rejection.
//! With a Host invalidation target: finish dispatch/rendering, destroy runtime, then destroy
//! Host without further rendering/input. Raw frame storage cleanup does not dereference leases.
//! App storage, service userdata and injected Io backend outlive runtime destruction.
//! Runtime methods reject synchronous recursive entry; Context services/observations are
//! allowed during activate/render/commands but cannot reenter lifecycle or service dispatch.
const std = @import("std");
const s = @import("../core/state.zig");
const c = @import("../core/context.zig");
const h = @import("handles.zig");
const cap = @import("capability.zig");
const Node = @import("../core/node.zig").Node;
const scenes = @import("../core/scenes.zig");
/// Plugin identity, version and requested capabilities; install copies retained metadata.
pub const Manifest = struct {
    /// Borrowed unique plugin ID; installation copies it into retained storage.
    id: []const u8,
    /// Informational semantic version; ABI compatibility is checked separately.
    version: struct {
        /// Major component of the plugin's advertised version.
        major: i32 = 0,
        /// Minor component of the plugin's advertised version.
        minor: i32 = 0,
        /// Patch component of the plugin's advertised version.
        patch: i32 = 0,
    } = .{},
    /// Plugin ABI version; incompatible values are rejected at installation.
    abi: u32 = 1,
    /// Required capabilities; installation fails if any exact grant is absent.
    requires: []const cap.Capability = &.{},
    /// Optional capabilities; missing grants remain unavailable.
    optional: []const cap.Capability = &.{},
};
/// Borrowed command declaration copied and bound to a revocable installation context.
pub const CommandDefinition = struct {
    /// Plugin-local command name, namespaced with the plugin ID during installation.
    id: []const u8,
    /// Borrowed display title copied into the installation arena.
    title: []const u8,
    /// Command callback receiving a checked installation context when performed.
    action: *const fn (h.Context) s.Error!void,
};
/// Auxiliary scene contribution with borrowed name/title and rendering callback.
pub const SceneDefinition = struct {
    /// Plugin-local scene name, namespaced with the plugin ID during installation.
    name: []const u8,

    /// Borrowed display title copied during installation; empty is permitted.
    title: []const u8 = "",

    /// Scene role; host construction requires exactly one primary scene.
    role: scenes.Role = .auxiliary,

    /// Suggested initial scene extent in cells for a supporting host.
    size: @import("../core/geometry.zig").Size = .{ .width = 80, .height = 24 },

    /// Whether a supporting host may resize this contributed scene.
    resizable: bool = true,

    /// Render callback; returned node storage must satisfy the BuildContext retention contract.
    render: *const fn (h.Context, *c.BuildContext) s.Error!Node,
};
/// Revocable installed auxiliary scene with namespaced ID and retained metadata.
pub const Scene = struct {
    /// Revocable installation lease protecting this scene callback.
    context: h.Context,

    /// Namespaced scene ID stored in the installation arena.
    id: []const u8,

    /// Display title borrowed from the retained installation arena.
    title: []const u8,

    /// Suggested initial cell extent copied from the scene definition.
    size: @import("../core/geometry.zig").Size,

    /// Resize policy copied from the scene definition.
    resizable: bool,

    /// Plugin scene callback; Scene.render wraps it with lease/reentry validation.
    render_fn: *const fn (h.Context, *c.BuildContext) s.Error!Node,
    /// Adapt an explicitly stored contribution into the ordinary portable scene graph.
    /// Resolver must return this same contribution from stable App storage.
    pub fn descriptor(self: Scene, comptime App: type, comptime resolve: fn (*App) Scene) scenes.Descriptor(App) {
        return .{ .id = self.id, .role = .auxiliary, .launch = .on_demand, .render = struct {
            fn render(app: *App, ctx: *c.BuildContext) s.Error!Node {
                return resolve(app).render(ctx);
            }
        }.render };
    }
    /// Portable auxiliary scene content. Does not open, close or own a native surface.
    pub fn render(self: Scene, ctx: *c.BuildContext) s.Error!Node {
        const l = self.context.lease;
        try l.check();
        try l.enter(l.runtime);
        defer l.leave(l.runtime);
        var bridge = Bridge{ .context = self.context, .original = ctx.hooks, .ctx = ctx };
        var child = ctx.*;
        child.hooks.host = &bridge;
        child.hooks.register_fn = Bridge.register;
        child.hooks.state_fn = Bridge.state;
        child.hooks.offset_fn = Bridge.offset;
        return ctx.retain(try self.render_fn(self.context, &child));
    }
};
/// Hook bridge lives only for synchronous render; all registered wrappers live in frame storage.
const Bridge = struct {
    /// Installation lease added to forwarded registrations.
    context: h.Context,

    /// Original host hooks forwarded after adding plugin validity checks.
    original: c.Hooks,

    /// Borrowed parent build context used to allocate registration wrappers.
    ctx: *c.BuildContext,
    const Authority = struct {
        /// Borrowed installation lease; every use must validate it before accessing payloads.
        lease: *h.Lease,

        /// Existing registration validity chained after the plugin lease check.
        previous: ?c.Validity,
        fn check(raw: *const anyopaque) s.Error!void {
            const self: *const Authority = @ptrCast(@alignCast(raw));
            try self.lease.check();
            if (self.previous) |previous| try previous.check(previous.owner);
        }
    };
    fn register(raw: *anyopaque, value: c.Registration) s.Error!void {
        const self: *Bridge = @ptrCast(@alignCast(raw));
        var owned = value;
        const authority = try self.ctx.allocator.create(Authority);
        authority.* = .{ .lease = self.context.lease, .previous = switch (owned) {
            inline else => |v| v.validity,
        } };
        switch (owned) {
            inline else => |*v| v.validity = .{ .owner = authority, .check = Authority.check },
        }
        switch (owned) {
            .action => |*v| v.action = try h.wrapAction(self.ctx, self.context, v.action),
            .key_handler => |*v| {
                const Capture = struct {
                    /// Installation lease retained in a frame-owned key-handler wrapper.
                    context: h.Context,
                    /// Original key callback borrowing its originating frame capture.
                    action: c.KeyAction,
                };
                const capture = try self.ctx.allocator.create(Capture);
                capture.* = .{ .context = self.context, .action = v.handler };
                v.handler = .{ .capture = capture, .invoke_fn = struct {
                    fn invoke(p: *const anyopaque, host: *anyopaque, key: @import("../core/input.zig").Key) s.Error!bool {
                        const item: *const Capture = @ptrCast(@alignCast(p));
                        const l = item.context.lease;
                        try l.check();
                        try l.enter(l.runtime);
                        defer l.leave(l.runtime);
                        return item.action.invoke_fn(item.action.capture, host, key);
                    }
                }.invoke };
            },
            else => {},
        }
        if (self.original.register_fn) |f| try f(self.original.host orelse return error.Unavailable, owned);
    }
    fn state(raw: *anyopaque, id: @import("../core/identity.zig").NodeID, slot: u32, ops: *const s.ValueOps, initial: *const anyopaque) s.Error!s.BindingToken {
        const self: *Bridge = @ptrCast(@alignCast(raw));
        return (self.original.state_fn orelse return error.Unavailable)(self.original.host orelse return error.Unavailable, id, slot, ops, initial);
    }
    fn offset(raw: *anyopaque, id: @import("../core/identity.zig").NodeID, slot: u32) s.Error!i64 {
        const self: *Bridge = @ptrCast(@alignCast(raw));
        return if (self.original.offset_fn) |f| f(self.original.host orelse return error.Unavailable, id, slot) else 0;
    }
};
/// Specialize a stable heap plugin runtime with retained revoked leases and a confinement guard.
pub fn Implementation(comptime Guard: type) type {
    return struct {
        const Self = @This();
        const Entry = struct {
            /// Borrowed installation lease; every use must validate it before accessing payloads.
            lease: h.Lease,

            /// Installation metadata arena retained with its lease tombstone until runtime destruction.
            arena: std.heap.ArenaAllocator,

            /// Owned plugin instance allocation, null after failed installation or uninstall.
            payload: ?*anyopaque = null,

            /// Optional payload deactivation callback invoked before releasing an active instance.
            deactivate: ?*const fn (*anyopaque) void = null,

            /// Typed payload allocation release callback, using the runtime allocator.
            release: ?*const fn (*anyopaque, std.mem.Allocator) void = null,

            /// Optional erased region renderer; called only through a valid installed lease.
            render_fn: ?*const fn (*anyopaque, []const u8, h.Context, *c.BuildContext) s.Error!Node = null,

            /// Ordered drawing or plugin commands owned by the documented producing collection.
            commands: []h.Command = &.{},

            /// Owned scene metadata slice backed by this installation arena.
            scenes: []Scene = &.{},

            /// Stable identity slot reused for this plugin ID across reinstallations.
            identity: i64 = 0,
        };
        const Identity = struct {
            /// Copied plugin ID retained across install/uninstall cycles.
            id: []const u8,
            /// State slot within a node identity; keep stable across renders of the same component.
            slot: i64,
        };

        /// Allocator owning runtime entries and payloads; retain until destroy.
        allocator: std.mem.Allocator,

        /// Executor/reentrancy guard; callers must use checked methods instead of changing it.
        guard: Guard,

        /// Owner-managed reentry guard around installation, removal and rendering.
        busy: bool = false,

        /// Runtime arena retaining grant copies and identity names until destroy.
        storage: std.heap.ArenaAllocator,

        /// Owned copy of allowed capabilities indexed by plugin ID.
        grants: cap.Grants,

        /// Borrowed service callbacks; userdata must outlive installed runtime use.
        services: h.Services,

        /// Borrowed invalidation target; configure before installing any entries.
        invalidation: h.Invalidation,

        /// Currently installed entries, in installation order.
        entries: std.ArrayList(*Entry) = .empty,

        /// All allocated entries including revoked tombstones, retained until runtime destruction.
        all: std.ArrayList(*Entry) = .empty,

        /// Persistent plugin-ID to structural-slot mapping for reinstall identity stability.
        identities: std.ArrayList(Identity) = .empty,
        /// Grants are copied; service and invalidation userdata are borrowed until destroy.
        pub fn create(a: std.mem.Allocator, grants: cap.Grants, services: h.Services) s.Error!*Self {
            const self = try a.create(Self);
            errdefer a.destroy(self);
            self.* = .{ .allocator = a, .guard = Guard.init(), .storage = .init(a), .grants = .{}, .services = services, .invalidation = .{} };
            errdefer self.storage.deinit();
            const arena = self.storage.allocator();
            const entries = try arena.alloc(cap.Grant, grants.entries.len);
            for (grants.entries, 0..) |entry, i| entries[i] = .{ .id = try arena.dupe(u8, entry.id), .capabilities = try copyCaps(arena, entry.capabilities) };
            self.grants.entries = entries;
            return self;
        }
        /// Replace the invalidation target only while no installation entry has been retained.
        /// The borrowed callback target must outlive the runtime and all callback use.
        pub fn setInvalidation(self: *Self, target: h.Invalidation) s.Error!void {
            try self.enter();
            defer self.leave();
            if (self.all.items.len != 0) return error.Reentrant;
            self.invalidation = target;
        }
        fn enter(self: *Self) s.Error!void {
            try self.guard.check();
            if (self.busy) return error.Reentrant;
            for (self.all.items) |e| if (e.lease.servicing or e.lease.editing or e.lease.borrowing_payload) return error.Reentrant;
            self.busy = true;
            self.invalidation.preflight() catch |err| {
                self.busy = false;
                return err;
            };
        }
        fn leave(self: *Self) void {
            self.busy = false;
        }
        fn enterRaw(raw: *anyopaque) s.Error!void {
            try @as(*Self, @ptrCast(@alignCast(raw))).enter();
        }
        fn leaveRaw(raw: *anyopaque) void {
            @as(*Self, @ptrCast(@alignCast(raw))).leave();
        }

        /// Install one cooperative static plugin after validating identity and required grants.
        pub fn install(self: *Self, plugin: anytype) s.Error!void {
            try self.enter();
            defer self.leave();
            const P = @TypeOf(plugin);
            var candidate = plugin;
            const manifest = candidate.manifest();
            if (manifest.abi != 1) return error.ABIMismatch;
            for (self.entries.items) |entry| if (std.mem.eql(u8, entry.lease.id, manifest.id)) return error.DuplicatePlugin;
            for (manifest.requires) |required| {
                if (!self.grants.permits(manifest.id, required)) return error.MissingRequiredCapability;
                if (!self.services.available(required)) return error.ServiceUnavailable;
            }
            // Reserve all publication allocations before arbitrary activation side effects.
            try self.entries.ensureUnusedCapacity(self.allocator, 1);
            try self.all.ensureUnusedCapacity(self.allocator, 1);
            try self.identities.ensureUnusedCapacity(self.allocator, 1);
            const e = try self.allocator.create(Entry);
            e.* = .{ .arena = .init(self.allocator), .lease = undefined };
            var published = false;
            errdefer if (!published) {
                e.arena.deinit();
                self.allocator.destroy(e);
            };
            const a = e.arena.allocator();
            const id = try a.dupe(u8, manifest.id);
            var caps: std.ArrayList(cap.Capability) = .empty;
            try caps.appendSlice(a, try copyCaps(a, manifest.requires));
            for (manifest.optional) |optional| if (self.grants.permits(id, optional) and self.services.available(optional)) try caps.append(a, try copyCap(a, optional));
            e.lease = .{ .allocator = self.allocator, .executor = s.executor(&self.guard), .id = id, .services = self.services, .invalidation = self.invalidation, .capabilities = caps.items, .runtime = self, .enter = enterRaw, .leave = leaveRaw };
            const payload = try self.allocator.create(P);
            payload.* = candidate;
            e.payload = payload;
            e.lease.payload = payload;
            e.lease.payload_type = @typeName(P);
            e.release = struct {
                fn release(raw: *anyopaque, alloc: std.mem.Allocator) void {
                    alloc.destroy(@as(*P, @ptrCast(@alignCast(raw))));
                }
            }.release;
            errdefer if (!published) self.allocator.destroy(payload);
            const context = h.Context{ .lease = &e.lease };
            // Publish the inactive-on-error tombstone before any callback can save its context.
            self.all.appendAssumeCapacity(e);
            published = true;
            errdefer {
                e.lease.active = false;
                e.lease.cancelCheck() catch unreachable;
                e.lease.cancelInternal();
                e.release.?(payload, self.allocator);
                e.payload = null;
                e.lease.payload = null;
            }
            const scene_defs: []const SceneDefinition = if (@hasDecl(P, "scenes")) try payload.scenes(context) else &.{};
            for (scene_defs) |scene| if (scene.role == .primary) return error.PrimarySceneContribution;
            e.scenes = try a.alloc(Scene, scene_defs.len);
            for (scene_defs, 0..) |scene, i| e.scenes[i] = .{ .context = context, .id = try std.fmt.allocPrint(a, "plugin/{s}/{s}", .{ id, scene.name }), .title = try a.dupe(u8, scene.title), .size = scene.size, .resizable = scene.resizable, .render_fn = scene.render };
            const command_defs: []const CommandDefinition = if (@hasDecl(P, "commands")) try payload.commands() else &.{};
            e.commands = try a.alloc(h.Command, command_defs.len);
            for (command_defs, 0..) |command, i| e.commands[i] = .{ .context = context, .id = try a.dupe(u8, command.id), .title = try a.dupe(u8, command.title), .action = command.action };
            var identity: ?i64 = null;
            for (self.identities.items) |item| if (std.mem.eql(u8, item.id, id)) {
                identity = item.slot;
                break;
            };
            if (self.identities.items.len >= std.math.maxInt(i64)) return error.GenerationExhausted;
            e.identity = identity orelse @intCast(self.identities.items.len);
            try payload.activate(context);
            if (@hasDecl(P, "deactivate")) e.deactivate = struct {
                fn deactivate(raw: *anyopaque) void {
                    @as(*P, @ptrCast(@alignCast(raw))).deactivate();
                }
            }.deactivate;
            if (@hasDecl(P, "render")) e.render_fn = struct {
                fn render(raw: *anyopaque, slot: []const u8, ctx: h.Context, build: *c.BuildContext) s.Error!Node {
                    return @as(*P, @ptrCast(@alignCast(raw))).render(slot, ctx, build);
                }
            }.render;
            if (identity == null) self.identities.appendAssumeCapacity(.{ .id = id, .slot = e.identity });
            self.entries.appendAssumeCapacity(e);
            self.invalidation.call();
        }

        /// Remove this installation and revoke its saved handles before later use.
        pub fn uninstall(self: *Self, id: []const u8) s.Error!void {
            try self.enter();
            defer self.leave();
            for (self.entries.items, 0..) |e, i| if (std.mem.eql(u8, e.lease.id, id)) {
                try e.lease.cancelCheck();
                _ = self.entries.orderedRemove(i);
                self.remove(e);
                self.invalidation.call();
                return;
            };
        }
        fn remove(self: *Self, e: *Entry) void {
            e.lease.active = false;
            e.lease.cancelInternal();
            if (e.payload) |payload| {
                if (e.deactivate) |f| f(payload);
                e.release.?(payload, self.allocator);
                e.payload = null;
                e.lease.payload = null;
            }
        }

        /// Release the stable owner and its resources; no handle may be used afterward.
        pub fn destroy(self: *Self) s.Error!void {
            try self.enter();
            for (self.all.items) |e| e.lease.detachCheck() catch |err| {
                self.leave();
                return err;
            };
            for (self.entries.items) |e| self.remove(e);
            for (self.all.items) |e| {
                e.lease.observations.deinit(self.allocator);
                e.arena.deinit();
                self.allocator.destroy(e);
            }
            self.entries.deinit(self.allocator);
            self.all.deinit(self.allocator);
            self.identities.deinit(self.allocator);
            self.storage.deinit();
            const a = self.allocator;
            a.destroy(self);
        }
        /// Allocator-owned arrays, metadata/handles borrow runtime. Declaration/install order.
        pub fn commands(self: *Self, a: std.mem.Allocator) s.Error![]h.Command {
            try self.enter();
            defer self.leave();
            var result: std.ArrayList(h.Command) = .empty;
            errdefer result.deinit(a);
            for (self.entries.items) |e| try result.appendSlice(a, e.commands);
            return result.toOwnedSlice(a);
        }

        /// Allocate an ordered list of current scene handles; the caller frees the slice and preserves owner lifetime.
        pub fn contributedScenes(self: *Self, a: std.mem.Allocator) s.Error![]Scene {
            try self.enter();
            defer self.leave();
            var result: std.ArrayList(Scene) = .empty;
            errdefer result.deinit(a);
            for (self.entries.items) |e| try result.appendSlice(a, e.scenes);
            return result.toOwnedSlice(a);
        }

        /// Allocate the outer slice of IDs in installation order; free that slice with a.
        /// ID bytes borrow retained installation storage and must not outlive runtime destruction.
        pub fn installed(self: *Self, a: std.mem.Allocator) s.Error![][]const u8 {
            try self.enter();
            defer self.leave();
            const result = try a.alloc([]const u8, self.entries.items.len);
            for (self.entries.items, 0..) |e, i| result[i] = e.lease.id;
            return result;
        }

        /// Render each installed plugin into the named slot in installation order.
        /// Returned nodes/captures use ctx storage; their live callbacks also borrow installation leases.
        pub fn render(self: *Self, slot: []const u8, ctx: *c.BuildContext) s.Error!Node {
            try self.enter();
            defer self.leave();
            if (self.entries.items.len == 0) return .empty;
            const nodes = try ctx.allocator.alloc(Node, self.entries.items.len);
            for (self.entries.items, 0..) |e, i| {
                var child = ctx.child(e.identity);
                var bridge = Bridge{ .context = .{ .lease = &e.lease }, .original = child.hooks, .ctx = &child };
                child.hooks.host = &bridge;
                child.hooks.register_fn = Bridge.register;
                child.hooks.state_fn = Bridge.state;
                child.hooks.offset_fn = Bridge.offset;
                nodes[i] = if (e.render_fn) |f| try ctx.retain(try f(e.payload.?, slot, bridge.context, &child)) else .empty;
            }
            return .{ .group = nodes };
        }
    };
}
fn copyCap(a: std.mem.Allocator, value: cap.Capability) s.Error!cap.Capability {
    var result = value;
    if (result == .filesystem) result.filesystem.prefix = try a.dupe(u8, result.filesystem.prefix);
    return result;
}
fn copyCaps(a: std.mem.Allocator, values: []const cap.Capability) s.Error![]cap.Capability {
    const result = try a.alloc(cap.Capability, values.len);
    for (values, 0..) |v, i| result[i] = try copyCap(a, v);
    return result;
}
