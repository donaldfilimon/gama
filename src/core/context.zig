//! Candidate-frame allocation and host hooks. Destroy the frame on commit replacement or abort.
const std = @import("std");
const Node = @import("node.zig").Node;
const NodeID = @import("identity.zig").NodeID;
const geo = @import("geometry.zig");
const style = @import("style.zig");
const state_module = @import("state.zig");
/// State, capture, rendering and allocation errors propagated through build operations.
pub const Error = state_module.Error;
/// Numeric identity resolved and generation-checked by the owning host (Task 5).
/// Never a pointer to a component, temporary context, or borrowed value.
pub const BindingToken = state_module.BindingToken;
/// Unicode scalar plus control/alt/shift flags for action lookup.
pub const Shortcut = @import("input.zig").Shortcut;
/// Borrowed command name and optional shortcut attached to action/toggle registrations.
pub const ActionIdentity = struct {
    /// Borrowed command name copied into the frame when registered.
    id: []const u8,
    /// Optional scalar/modifier shortcut checked by host dispatch.
    shortcut: ?Shortcut = null,
};
/// Single-surface adapters expose fixed identity and unavailable native window operations.
pub const WindowContext = struct {
    /// Current scene instance identity, or null when no host supplied one.
    instance_id: ?u64 = null,

    /// Request opening a scene; retained single-surface adapters report unavailable.
    pub fn open(_: WindowContext, _: []const u8) bool {
        return false;
    }

    /// Request scene dismissal; retained single-surface adapters report unavailable.
    pub fn dismiss(_: WindowContext) bool {
        return false;
    }
};
/// Copyable render environment inherited by child build contexts.
pub const Environment = struct {
    /// Whether input registration and activation are enabled.
    enabled: bool = true,
    /// Optional action identity inherited by registering child controls.
    action_identity: ?ActionIdentity = null,
    /// Scene-instance metadata; portable open/dismiss operations remain unsupported.
    window_context: WindowContext = .{},
};
/// Captures borrow their originating FrameStorage until its destruction.
/// Copying/registering an Action never transfers capture ownership to another frame.
pub const Action = struct {
    /// Frame-owned cloned capture; valid until the owning frame is released.
    capture: *const anyopaque,

    /// Type-erased callback receiving the capture and dispatching host.
    invoke_fn: *const fn (*const anyopaque, *anyopaque) Error!void,

    /// Invoke the callback directly with its frame-borrowed capture; callers guarantee capture lifetime.
    /// Use a Host-issued action handle when invocation must validate a cached frame generation.
    pub fn invoke(self: Action, host: *anyopaque) Error!void {
        return self.invoke_fn(self.capture, host);
    }
};
/// Like Action, this borrows capture storage from its originating FrameStorage.
pub const KeyAction = struct {
    /// Frame-owned cloned key-handler capture; valid for the registration lifetime.
    capture: *const anyopaque,

    /// Return true when the key was consumed; failures propagate to host dispatch.
    invoke_fn: *const fn (*const anyopaque, *anyopaque, @import("input.zig").Key) Error!bool,
};
/// Borrowed owner plus callback used to reject revoked registrations.
pub const Validity = struct {
    /// Borrowed owner pointer; this value must never outlive that owner.
    owner: *const anyopaque,
    /// Validate the borrowed owner before invoking a registered action or handler.
    check: *const fn (*const anyopaque) Error!void,
};
/// Frame registrations consumed by the host for actions, editing, scrolling and regions.
pub const Registration = union(enum) {
    /// Run the registration payload's optional validity callback; absent validity performs no check.
    pub fn validate(self: Registration) Error!void {
        switch (self) {
            inline else => |v| if (v.validity) |token| try token.check(token.owner),
        }
    }

    /// Focused-control handler invoked before built-in key handling.
    key_handler: struct {
        /// Optional revocation check performed before invoking the handler.
        validity: ?Validity = null,
        /// Node identity associated with the focused key callback.
        id: NodeID,
        /// Frame-owned key callback and capture.
        handler: KeyAction,
    },

    /// Activatable callback, with an optional command name/shortcut.
    action: struct {
        /// Optional owner/installation validity check before action use.
        validity: ?Validity = null,
        /// Node identity used to find this action during dispatch.
        id: NodeID,
        /// Callback capture borrowing its originating frame storage.
        action: Action,
        /// Optional command name and shortcut, copied by BuildContext.register.
        identity: ?ActionIdentity,
    },

    /// Editable text binding with a host-maintained grapheme cursor slot.
    text_field: struct {
        /// Optional revocation check before editing the binding.
        validity: ?Validity = null,
        /// Node identity for the editable field and its cursor state.
        id: NodeID,
        /// Owner-issued typed binding token; never synthesize one from raw pointers.
        binding: BindingToken,
        /// State slot holding this control's grapheme selection; defaults to zero.
        cursor_slot: u32 = 0,
    },

    /// Boolean binding toggled by activation.
    toggle: struct {
        /// Optional revocation check before toggling the binding.
        validity: ?Validity = null,
        /// Node identity for the boolean control.
        id: NodeID,
        /// Owner-issued typed binding token; never synthesize one from raw pointers.
        binding: BindingToken,
        /// Optional command identity and shortcut for toggle activation.
        identity: ?ActionIdentity,
    },

    /// Scrollable visible-window metadata with a host-maintained offset slot.
    virtual_list: struct {
        /// Optional revocation check before changing the scroll offset.
        validity: ?Validity = null,
        /// Node identity owning this list's offset state.
        id: NodeID,
        /// State slot within a node identity; keep stable across renders of the same component.
        slot: u32 = 0,
        /// Bounded storage or visible-row capacity; callers must respect the declared limit.
        capacity: usize,
        /// Largest legal item offset for the current data/window size.
        max_offset: usize,
    },

    /// Native-region name associated with a portable fallback node.
    native_region: struct {
        /// Optional revocation check before exposing the region registration.
        validity: ?Validity = null,
        /// Node identity whose laid-out frame locates the native region.
        id: NodeID,
        /// Borrowed region name; register copies it into frame storage.
        region_id: []const u8,
    },
};
/// Hooks borrow stable host storage. register may retain only frame-owned registration data.
/// An abort must discard all registrations. The default context is deliberately host-less.
pub const Hooks = struct {
    /// Borrowed host pointer; keep the host alive until this value is released.
    host: ?*anyopaque = null,

    /// Optional callback accepting a frame registration; null omits registration.
    register_fn: ?*const fn (*anyopaque, Registration) Error!void = null,

    /// Optional callback binding a typed value at the node/slot key.
    state_fn: ?*const fn (*anyopaque, NodeID, u32, *const state_module.ValueOps, *const anyopaque) Error!BindingToken = null,

    /// Borrowed host state store used by StateRef handles returned during building.
    store: ?*state_module.Store = null,

    /// Optional virtual-list offset lookup; null yields offset zero.
    offset_fn: ?*const fn (*anyopaque, NodeID, u32) Error!i64 = null,
};
/// Owns a frame arena and managed-capture cleanup chain; move only before borrowing it.
pub const FrameStorage = struct {
    const Cleanup = struct {
        /// Next managed capture cleanup record, owned by the same frame arena.
        next: ?*Cleanup,
        /// Owned managed capture whose destructor runs before arena teardown.
        value: *anyopaque,
        /// Release the captured value before the frame arena is destroyed.
        release: *const fn (*anyopaque, std.mem.Allocator) void,
    };

    /// Owner-managed cleanup chain; populated only by captureValue.
    cleanups: ?*Cleanup = null,

    /// Arena owning nodes, copied text and captures; FrameStorage.deinit runs cleanups before releasing it.
    arena: std.heap.ArenaAllocator,

    /// Create an empty frame arena using allocator; release captures and arena with deinit.
    pub fn init(allocator: std.mem.Allocator) FrameStorage {
        return .{ .arena = .init(allocator) };
    }

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *FrameStorage) void {
        var cleanup = self.cleanups;
        while (cleanup) |item| {
            item.release(item.value, self.arena.allocator());
            cleanup = item.next;
        }
        self.arena.deinit();
        self.* = undefined;
    }
    /// FrameStorage must stay at a stable address while contexts exist.
    pub fn context(self: *FrameStorage) BuildContext {
        return .{ .allocator = self.arena.allocator(), .storage = self };
    }
};
/// Copyable rendering context borrowing frame storage and optional host hooks.
pub const BuildContext = struct {
    /// Frame owner required for managed capture cleanup; null supports unmanaged captures only.
    storage: ?*FrameStorage = null,

    /// Frame allocation source; allocations survive until its backing storage is released.
    allocator: std.mem.Allocator,

    /// Identity assigned to state slots and registrations produced by this context.
    id: NodeID = .root,

    /// Text style inherited by primitive rendering and child contexts.
    inherited_style: style.TextStyle = .plain,

    /// Inherited interaction, action and window environment for this subtree.
    environment: Environment = .{},

    /// Current focused identity, or null when no control is selected.
    focus: ?NodeID = null,

    /// Optional surface extent used to bound virtualized lists.
    surface_size: ?geo.Size = null,

    /// Borrowed callbacks and state store supplied by the current host.
    hooks: Hooks = .{},

    /// Derive a deterministic child identity/context from its positional index.
    pub fn child(self: BuildContext, index: i64) BuildContext {
        var result = self;
        result.id = self.id.child(index);
        return result;
    }

    /// Derive a child context from a stable caller identity.
    pub fn scoped(self: BuildContext, id: NodeID) BuildContext {
        var result = self;
        result.id = id;
        return result;
    }

    /// Validate and copy UTF-8 into the current frame arena.
    pub fn copyText(self: *BuildContext, value: []const u8) Error![]const u8 {
        _ = try @import("unicode.zig").count(value);
        return self.allocator.dupe(u8, value);
    }
    /// Shallow Node copy: referenced bytes/children must outlive the frame or first pass through retain.
    pub fn box(self: *BuildContext, value: Node) Error!*const Node {
        const p = try self.allocator.create(Node);
        p.* = value;
        return p;
    }
    /// Deep-copy externally authored IR so no temporary text/children escape the build.
    pub fn retain(self: *BuildContext, node: Node) Error!Node {
        var result = node;
        switch (result) {
            .text => |*v| v.content = try self.copyText(v.content),
            .group => |*v| v.* = try self.retainChildren(v.*),
            .stack => |*v| v.children = try self.retainChildren(v.children),
            .overlay => |*v| v.children = try self.retainChildren(v.children),
            .border => |*v| {
                v.child = try self.box(try self.retain(v.child.*));
                if (v.title) |t| v.title = try self.copyText(t);
            },
            .padding => |*v| v.child = try self.box(try self.retain(v.child.*)),
            .background => |*v| v.child = try self.box(try self.retain(v.child.*)),
            .frame => |*v| v.child = try self.box(try self.retain(v.child.*)),
            .flex_frame => |*v| v.child = try self.box(try self.retain(v.child.*)),
            .styled => |*v| v.child = try self.box(try self.retain(v.child.*)),
            .interactive => |*v| v.child = try self.box(try self.retain(v.child.*)),
            else => {},
        }
        return result;
    }

    /// Copy the child sequence and all required nested node data into the frame arena.
    pub fn retainChildren(self: *BuildContext, nodes: []const Node) Error![]const Node {
        const result = try self.allocator.alloc(Node, nodes.len);
        for (nodes, 0..) |n, i| result[i] = try self.retain(n);
        return result;
    }
    /// Capture storage expires with this context's FrameStorage, including copied/registered actions.
    /// Plain values/canonical handles copy; explicitly managed values clone and deinit with the frame.
    /// Raw Actions are frame borrows; use Host.actionHandle for cached, generation-checked invocation.
    pub fn action(self: *BuildContext, capture: anytype, comptime callback: fn (*const @TypeOf(capture), *anyopaque) Error!void) Error!Action {
        const storage = try self.captureValue(capture);
        return .{ .capture = storage, .invoke_fn = struct {
            fn invoke(raw: *const anyopaque, host: *anyopaque) Error!void {
                return callback(@ptrCast(@alignCast(raw)), host);
            }
        }.invoke };
    }
    fn captureValue(self: *BuildContext, capture: anytype) Error!*@TypeOf(capture) {
        const T = @TypeOf(capture);
        comptime validateCapture(T);
        const storage = try self.allocator.create(T);
        storage.* = try cloneCapture(T, &capture, self.allocator);
        errdefer deinitCapture(T, storage, self.allocator);
        if (comptime managedCapture(T)) {
            const frame = self.storage orelse return error.Unavailable;
            const cleanup = try self.allocator.create(FrameStorage.Cleanup);
            cleanup.* = .{ .next = frame.cleanups, .value = storage, .release = struct {
                fn release(raw: *anyopaque, a: std.mem.Allocator) void {
                    deinitCapture(T, @ptrCast(@alignCast(raw)), a);
                }
            }.release };
            frame.cleanups = cleanup;
        }
        return storage;
    }
    /// Typed key capture uses the same ownership rules as action; true consumes the event.
    pub fn keyHandler(self: *BuildContext, capture: anytype, comptime callback: fn (*const @TypeOf(capture), *anyopaque, @import("input.zig").Key) Error!bool) Error!KeyAction {
        const storage = try self.captureValue(capture);
        return .{ .capture = storage, .invoke_fn = struct {
            fn invoke(raw: *const anyopaque, host: *anyopaque, key: @import("input.zig").Key) Error!bool {
                return callback(@ptrCast(@alignCast(raw)), host, key);
            }
        }.invoke };
    }

    /// Stage interaction metadata for publication with the candidate frame.
    pub fn register(self: *BuildContext, registration: Registration) Error!void {
        const callback = self.hooks.register_fn orelse return;
        const host = self.hooks.host orelse return error.Unavailable;
        var owned = registration;
        switch (owned) {
            .action => |*v| v.identity = try self.ownIdentity(v.identity),
            .toggle => |*v| v.identity = try self.ownIdentity(v.identity),
            .native_region => |*v| v.region_id = try self.copyText(v.region_id),
            else => {},
        }
        try callback(host, owned);
    }
    fn ownIdentity(self: *BuildContext, identity: ?ActionIdentity) Error!?ActionIdentity {
        var result = identity orelse return null;
        result.id = try self.copyText(result.id);
        return result;
    }

    /// Resolve a typed state cell under the current node identity and explicit slot.
    pub fn state(self: *BuildContext, comptime T: type, slot: u32, initial: T) Error!state_module.StateRef(T) {
        const callback = self.hooks.state_fn orelse return error.Unavailable;
        const token = try callback(self.hooks.host orelse return error.Unavailable, self.id, slot, state_module.ops(T), &initial);
        return .{ .owner = self.hooks.store orelse return error.Unavailable, .token = token };
    }

    /// Resolve the host-owned virtual-list scroll offset for this node.
    pub fn offset(self: *BuildContext) Error!i64 {
        const callback = self.hooks.offset_fn orelse return 0;
        return callback(self.hooks.host orelse return error.Unavailable, self.id, 0);
    }
};
/// Compile-time reject captures whose storage cannot safely outlive rendering.
pub fn validateCapture(comptime T: type) void {
    if (@import("../plugins/handles.zig").canonical(T)) return;
    if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "Value")) {
        if (T == state_module.StateRef(T.Value) or T == @import("signal.zig").SignalRef(T.Value)) return;
    }
    if (comptime managedCapture(T)) {
        state_module.validateValue(T);
        return;
    }
    switch (@typeInfo(T)) {
        .pointer, .@"fn", .@"opaque" => @compileError("action.capture-must-be-owned-value"),
        .@"struct" => |s| inline for (s.field_types) |f| validateCapture(f),
        .@"union" => |u| inline for (u.field_types) |f| validateCapture(f),
        .array => |a| validateCapture(a.child),
        .optional => |o| validateCapture(o.child),
        .error_union => |e| validateCapture(e.payload),
        .vector => |v| validateCapture(v.child),
        else => {},
    }
}

fn managedCapture(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "clone") and @hasDecl(T, "deinit");
}
/// Clone the supported typed capture into candidate-frame storage.
pub fn cloneCapture(comptime T: type, value: *const T, a: std.mem.Allocator) Error!T {
    comptime validateCapture(T);
    if (comptime managedCapture(T)) return value.clone(a);
    comptime rejectNestedManaged(T);
    return value.*;
}
fn rejectNestedManaged(comptime T: type) void {
    if (@import("../plugins/handles.zig").canonical(T)) return;
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "Value")) {
        if (T == state_module.StateRef(T.Value) or T == @import("signal.zig").SignalRef(T.Value)) return;
    }
    if (comptime managedCapture(T)) @compileError("action.nested-managed-capture-requires-hooks");
    switch (@typeInfo(T)) {
        .@"struct" => |info| inline for (info.field_types) |F| rejectNestedManaged(F),
        .@"union" => |info| inline for (info.field_types) |F| rejectNestedManaged(F),
        .array => |info| rejectNestedManaged(info.child),
        .optional => |info| rejectNestedManaged(info.child),
        .error_union => |info| rejectNestedManaged(info.payload),
        else => {},
    }
}
/// Release a managed frame capture using its matching allocator/hooks.
pub fn deinitCapture(comptime T: type, value: *T, a: std.mem.Allocator) void {
    if (comptime managedCapture(T)) value.deinit(a);
}
