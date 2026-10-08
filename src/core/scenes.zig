//! Typed application callbacks avoid erased payload/capture lifetimes. Only primary is presented.
const std = @import("std");
const c = @import("context.zig");
const Node = @import("node.zig").Node;
/// Select the single portable primary scene or an auxiliary scene descriptor.
pub const Role = enum {
    /// Required scene rendered by portable hosts; exactly one must exist.
    primary,
    /// Additional descriptor retained for host-specific scene use.
    auxiliary,
};
/// Policy controlling whether initial payload is required at launch.
pub const Launch = enum {
    /// Request opening at launch; an absent required payload is invalid.
    open_at_launch,
    /// Delay opening until requested by a supporting host.
    on_demand,
};
/// A present optional-none payload is still present; callback obtains its typed payload from App.
pub const InitialPayload = enum {
    /// Scene does not require an initial payload.
    not_required,
    /// Required initial payload has not been supplied.
    absent,
    /// Required initial payload is available.
    present,
};
/// Descriptor-graph validation failures, reported before graph allocation.
pub const ValidationError = error{
    /// Two scene descriptors have equal identifiers.
    DuplicateSceneID,
    /// A required launch/primary scene payload is explicitly absent.
    MissingInitialPayload,
    /// No descriptor is marked primary.
    MissingPrimaryScene,
    /// More than one descriptor is marked primary.
    MultiplePrimaryScenes,
};
/// Return the application-specialized scene descriptor type.
pub fn Descriptor(comptime App: type) type {
    return struct {
        /// Borrowed scene name; Graph.init copies it and rejects duplicate names.
        id: []const u8,

        /// Scene role; host construction requires exactly one primary scene.
        role: Role = .auxiliary,

        /// Explicit launch policy; null defaults primary to launch and auxiliary to demand.
        launch: ?Launch = null,

        /// Availability of an initial payload for launch validation.
        initial_payload: InitialPayload = .not_required,

        /// Render callback; returned node storage must satisfy the BuildContext retention contract.
        render: *const fn (*App, *c.BuildContext) c.Error!Node,

        /// Resolve launch metadata using the scene defaults and supplied override.
        pub fn resolvedLaunch(self: @This()) Launch {
            return self.launch orelse if (self.role == .primary) .open_at_launch else .on_demand;
        }
    };
}
/// Declaration-order errors precede the final primary count check.
pub fn validate(comptime App: type, descriptors: []const Descriptor(App)) ValidationError!usize {
    var primary: ?usize = null;
    var count: usize = 0;
    for (descriptors, 0..) |scene, i| {
        for (descriptors[0..i]) |previous| if (std.mem.eql(u8, scene.id, previous.id)) return error.DuplicateSceneID;
        if (scene.role == .primary) {
            primary = i;
            count += 1;
        }
        if (scene.initial_payload == .absent and (scene.role == .primary or scene.resolvedLaunch() == .open_at_launch)) return error.MissingInitialPayload;
    }
    if (count == 0) return error.MissingPrimaryScene;
    if (count > 1) return error.MultiplePrimaryScenes;
    return primary.?;
}
/// Graph owns descriptor/ID copies. App storage must be stable and outlive this graph and hosts.
pub fn Graph(comptime App: type) type {
    return struct {
        /// Allocator owning the descriptor array and copied IDs; retain until deinit.
        allocator: std.mem.Allocator,

        /// Owned descriptor array with separately copied identifiers; release through deinit.
        descriptors: []Descriptor(App),

        /// Index of the unique primary descriptor in descriptors.
        primary: usize,

        /// Validate the graph and copy descriptors/IDs; allocator must survive deinit, callbacks are borrowed.
        pub fn init(allocator: std.mem.Allocator, input: []const Descriptor(App)) (ValidationError || std.mem.Allocator.Error)!@This() {
            const primary = try validate(App, input);
            const owned = try allocator.alloc(Descriptor(App), input.len);
            errdefer allocator.free(owned);
            var initialized: usize = 0;
            errdefer for (owned[0..initialized]) |d| allocator.free(d.id);
            for (input, 0..) |d, i| {
                owned[i] = d;
                owned[i].id = try allocator.dupe(u8, d.id);
                initialized += 1;
            }
            return .{ .allocator = allocator, .descriptors = owned, .primary = primary };
        }

        /// Release owned storage exactly once; all borrows into this value become invalid.
        pub fn deinit(self: *@This()) void {
            for (self.descriptors) |d| self.allocator.free(d.id);
            self.allocator.free(self.descriptors);
            self.* = undefined;
        }

        /// Render the uniquely selected primary scene through the supplied context.
        pub fn renderPrimary(self: *const @This(), app: *App, ctx: *c.BuildContext) c.Error!Node {
            return self.descriptors[self.primary].render(app, ctx);
        }
    };
}
/// Explicit selected branches replace the scene builder; this helper preserves tuple order.
pub fn collect(comptime App: type, allocator: std.mem.Allocator, items: anytype) std.mem.Allocator.Error![]Descriptor(App) {
    var result: std.ArrayList(Descriptor(App)) = .empty;
    errdefer result.deinit(allocator);
    inline for (items) |item| {
        if (@TypeOf(item) == ?Descriptor(App)) {
            if (item) |value| try result.append(allocator, value);
        } else {
            try result.append(allocator, item);
        }
    }
    return result.toOwnedSlice(allocator);
}
