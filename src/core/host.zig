//! Stable heap-owned host. App, owner thread and all app Signals outlive the host.
//! PreparedFrame is a borrowed transaction token; commit/abort invalidate all copies.
const std = @import("std");
const s = @import("state.zig");
const c = @import("context.zig");
const scenes = @import("scenes.zig");
const Node = @import("node.zig").Node;
const NodeID = @import("identity.zig").NodeID;
const geo = @import("geometry.zig");
const text = @import("text.zig");
const layout = @import("layout.zig");
/// Application completion state and exit metadata; transport/process termination stays adapter-owned.
pub const Completion = struct {
    /// Raw completion status; zero means success.
    code: i32 = 0,

    /// Optional borrowed completion text; the caller controls process exit policy.
    message: ?[]const u8 = null,

    /// Construct completion with raw status zero and no message.
    pub fn success() Completion {
        return .{};
    }
    /// Raw status preserves legacy zero/negative/out-of-byte-range codes.
    pub fn failure(code: i32, message: ?[]const u8) Completion {
        return .{ .code = code, .message = message };
    }

    /// Construct failure using a previously validated nonzero byte exit code.
    pub fn failureValidated(code: FailureExitCode, message: ?[]const u8) Completion {
        return failure(code.value, message);
    }

    /// Return whether the raw completion code is zero.
    pub fn succeeded(self: Completion) bool {
        return self.code == 0;
    }
};
/// Validated nonzero process exit code, represented as an unsigned byte.
pub const FailureExitCode = struct {
    /// Nonzero exit byte produced by init; direct construction must preserve the 1...255 invariant.
    value: u8,

    /// Conventional general-failure code 1.
    pub const general: FailureExitCode = .{ .value = 1 };

    /// Return a code for values 1...255; return null for zero, negatives or larger integers.
    pub fn init(value: i32) ?FailureExitCode {
        return if (value >= 1 and value <= 255) .{ .value = @intCast(value) } else null;
    }
};
/// Scene/application lifecycle notification delivered through host dispatch.
pub const Lifecycle = struct {
    /// Discriminant selecting the semantic operation represented by this value.
    kind: enum {
        /// Application launch completed.
        did_launch,
        /// Application termination is imminent.
        will_terminate,
        /// A scene instance opened.
        window_opened,
        /// A scene instance received a close request.
        window_close_requested,
        /// A scene instance closed.
        window_closed,
    },

    /// Scene identifier associated with this lifecycle or contribution.
    scene: ?[]const u8 = null,

    /// Optional application-defined scene instance identity.
    instance: ?u64 = null,
};
/// Semantic keyboard event; character slices borrow adapter storage through dispatch.
pub const Key = @import("input.zig").Key;
/// Raw coordinate presses resolve against the last published layout; resolved presses remain supported.
pub const Event = union(enum) {
    /// Semantic keyboard input translated by the adapter.
    key: Key,
    /// Gamepad button transition translated to semantic keys on press.
    gamepad: struct {
        /// Physical button position, independent of vendor-specific labels.
        button: @import("input.zig").GamepadButton,
        /// True for press, false for release; unmapped releases are ignored.
        pressed: bool,
    },
    /// Activate a control by its published NodeID.
    activate: NodeID,
    /// Resolved pointer press carrying the selected identity and focus policy.
    pointer_press: struct {
        /// Published node selected by the adapter's resolved hit test.
        id: NodeID,
        /// Whether the interaction may participate in focus traversal.
        focusable: bool,
    },
    /// Pointer cell coordinate used for hit testing against the published layout.
    pointer: geo.Point,
    /// Pointer release event; retained semantics do not activate a control.
    pointer_release,
    /// Host tick notification; permits application work without a key event.
    tick,
    /// New surface extent in cells; triggers rendering with the new size.
    resize: geo.Size,
    /// Application or scene lifecycle transition.
    lifecycle: Lifecycle,
};
/// Specialize a stable heap host for App and its confinement guard; create/destroy own its lifetime.
pub fn Implementation(comptime App: type, comptime Guard: type) type {
    return struct {
        const Self = @This();
        const Staged = struct {
            /// Interaction registration collected while constructing the candidate frame.
            registration: c.Registration,
            /// Resolved cursor/offset state token for registrations needing host-managed state.
            state: ?s.BindingToken = null,
        };
        const Candidate = struct {
            /// Owned candidate arena and capture cleanups, destroyed on abort or publication replacement.
            frame: c.FrameStorage,

            /// Unique candidate generation used to validate every transaction token.
            generation: u64,

            /// Candidate's retained portable node tree, owned by frame.
            node: Node = .empty,

            /// Candidate layout tree with frames, allocated in the candidate arena.
            tree: layout.LaidNode = .{ .node = .empty, .frame = .{} },

            /// Final staged bytes copied into the candidate arena before delivery.
            output: []const u8 = &.{},

            /// Whether output staging completed and delivery/commit is now permitted.
            staged: bool = false,

            /// Candidate hit-test regions in paint traversal order.
            regions: std.ArrayList(Region) = .empty,

            /// Candidate native-region names and resolved rectangles.
            native_regions: std.ArrayList(NativeRegion) = .empty,

            /// Duplicate native-region names detected during candidate construction.
            duplicate_native_regions: std.ArrayList([]const u8) = .empty,

            /// Candidate interaction callbacks and resolved state tokens.
            registrations: std.ArrayList(Staged) = .empty,

            /// Whether the interaction may participate in focus traversal.
            focusable: std.ArrayList(NodeID) = .empty,

            /// Candidate identities with interaction registrations.
            interactive: std.ArrayList(NodeID) = .empty,

            /// Duplicate structural identities detected for this candidate.
            duplicates: std.ArrayList(NodeID) = .empty,

            /// Identities whose state type changed during this candidate's build.
            replaced: std.ArrayList(NodeID) = .empty,

            /// Current focused identity, or null when no control is selected.
            focus: ?NodeID,
        };

        /// Published hit-test rectangle and its focus eligibility.
        pub const Region = struct {
            /// Published interactive node identity for hit testing.
            id: NodeID,
            /// Published hit rectangle in cell coordinates.
            frame: geo.Rect,
            /// Whether the interaction may participate in focus traversal.
            focusable: bool,
        };

        /// Published native-region name/rectangle; name borrows the published frame.
        pub const NativeRegion = struct {
            /// Node identity associated with the published native region.
            id: NodeID,
            /// Name copied into frame storage; expires when that publication is replaced.
            region_id: []const u8,
            /// Published native-region rectangle in cell coordinates.
            frame: geo.Rect,
        };
        /// All values borrow the live candidate; output returned by downstream is copied before publication.
        pub const Preparation = struct {
            /// Borrowed candidate layout tree, valid only during the preparation callback.
            tree: *const layout.LaidNode,
            /// Candidate arena allocator; allocations expire with the candidate frame.
            allocator: std.mem.Allocator,
        };
        const Subscription = struct {
            /// Owner-maintained liveness flag; callers must use validation methods.
            active: bool = true,

            /// Whether the signal observer remains attached; host cleanup updates this flag.
            attached: bool = true,

            /// Check that the source signal can accept observer cancellation now.
            can_cancel: *const fn (*anyopaque) s.Error!void,

            /// Borrowed observed signal; detached callback clears this subscription before source destruction.
            signal: *anyopaque,

            /// Owner-issued binding token; use the issuing owner and preserve its generation.
            token: @import("signal.zig").Token,

            /// Validate this signal/token pair before cancellation or use.
            check: *const fn (*anyopaque, @import("signal.zig").Token) s.Error!void,

            /// Cancel the source observer corresponding to the stored token.
            cancel: *const fn (*anyopaque, @import("signal.zig").Token) s.Error!void,
        };

        /// Generation-checked candidate transaction; consume once by commit, abort or finish.
        pub const PreparedFrame = struct {
            /// Borrowed owner pointer; this value must never outlive that owner.
            owner: *Self,

            /// Candidate generation checked against the owner's active transaction.
            generation: u64,

            /// Borrow the candidate node after validating the prepared-frame token.
            pub fn node(self: PreparedFrame) s.Error!Node {
                return (try self.owner.candidateFor(self)).node;
            }

            /// Borrow the candidate laid-out tree until the transaction is consumed.
            pub fn tree(self: PreparedFrame) s.Error!*const layout.LaidNode {
                return &(try self.owner.candidateFor(self)).tree;
            }
            /// Paint/encode and copy the final bytes before any transport. Failure aborts.
            /// A staged candidate can be delivered exactly once or explicitly aborted.
            pub fn stage(self: PreparedFrame, context: anytype, comptime callback: fn (@TypeOf(context), Preparation) s.Error![]const u8) s.Error!void {
                const p = try self.owner.candidateFor(self);
                if (p.staged) return error.InvalidTransaction;
                try self.owner.enter();
                self.owner.finishInternal(p, context, callback) catch |err| {
                    self.owner.leave();
                    try self.owner.abort(self);
                    return err;
                };
                p.staged = true;
                self.owner.leave();
            }
            /// Guard transport against reentry and publish only after successful delivery.
            /// No framework allocation follows transport. Partial external writes cannot be rolled back.
            pub fn deliver(self: PreparedFrame, context: anytype, comptime transport: fn (@TypeOf(context), []const u8) s.Error!void) s.Error!void {
                const p = try self.owner.candidateFor(self);
                if (!p.staged) return error.InvalidTransaction;
                try self.owner.enter();
                transport(context, p.output) catch |err| {
                    self.owner.leave();
                    try self.owner.abort(self);
                    return err;
                };
                self.owner.publishInternal(p);
                self.owner.leave();
            }
            fn memoryOnly(_: void, _: []const u8) s.Error!void {}
            /// Convenience uses the same staging and nonallocating publication seam.
            pub fn finish(self: PreparedFrame, context: anytype, comptime callback: fn (@TypeOf(context), Preparation) s.Error![]const u8) s.Error!void {
                try self.stage(context, callback);
                try self.deliver({}, memoryOnly);
            }

            /// Borrow the candidate frame arena allocator; allocations expire with that frame.
            pub fn allocator(self: PreparedFrame) s.Error!std.mem.Allocator {
                return (try self.owner.candidateFor(self)).frame.arena.allocator();
            }

            /// Publish the prepared transaction once; all copies of its token become invalid.
            pub fn commit(self: PreparedFrame) s.Error!void {
                try self.owner.commit(self);
            }

            /// Discard the prepared transaction and retain the previous publication for retry.
            pub fn abort(self: PreparedFrame) s.Error!void {
                try self.owner.abort(self);
            }
        };

        /// Published-frame action token; invalid after publication changes or owner destruction.
        pub const ActionHandle = struct {
            /// Borrowed owner pointer; this value must never outlive that owner.
            owner: *Self,

            /// Publication generation captured when issuing this action handle.
            generation: u64,

            /// Action identity resolved within the captured publication.
            id: NodeID,

            /// Execute the registered action only after validating its live owner/generation.
            pub fn invoke(self: ActionHandle) s.Error!bool {
                try self.owner.enter();
                defer self.owner.leave();
                const current = self.owner.published orelse return error.InvalidHandle;
                if (current.generation != self.generation) return error.InvalidHandle;
                return self.owner.activate(self.id);
            }
        };

        /// Executor/reentrancy guard; callers must use checked methods instead of changing it.
        guard: Guard,

        /// Allocator owning the host and durable state; must survive destroy.
        allocator: std.mem.Allocator,

        /// Borrowed application storage; must outlive the host.
        app: *App,

        /// Owned validated scene descriptors; destroyed with the host.
        graph: scenes.Graph(App),

        /// Owned per-host state store; address must remain stable for bindings.
        store: s.Store,

        /// Host reentry guard set only during checked operations.
        busy: bool = false,

        /// True only while dispatching live application action, key or lifecycle code.
        application_callback: bool = false,

        /// True while App.connect runs; prevents destruction during construction.
        constructing: bool = false,

        /// Pending render invalidation; host methods clear it only after publication.
        dirty: bool = true,

        /// Application-requested quit flag consumed by the pump.
        wants_quit: bool = false,

        /// Requested surface size used for the next layout.
        size: geo.Size = .{},

        /// Current focused identity, or null when no control is selected.
        focus: ?NodeID = null,

        /// Stable host-instance identity assigned from the allocated owner address.
        instance_id: u64 = 0,

        /// Next transaction generation; issued monotonically by the host.
        next_generation: u64 = 1,

        /// Owned in-progress candidate, or null outside a frame transaction.
        candidate: ?*Candidate = null,

        /// Owned last successfully published candidate, retained across failed renders.
        published: ?*Candidate = null,

        /// Owned subscription records detached during host destruction.
        subscriptions: std.ArrayList(Subscription) = .empty,

        /// Application status or quiescent fallback; process exit remains caller-owned.
        completion: ?Completion = null,

        /// Owned appended output lines queued for the stream pump.
        lines: std.ArrayList([]const u8) = .empty,

        /// Allocate a stable owner; the application and borrowed dependencies must outlive it. Destroy it exactly once.
        pub fn create(a: std.mem.Allocator, app: *App) s.Error!*Self {
            const self = try allocate(a, app);
            errdefer self.destroy() catch unreachable;
            if (@hasDecl(App, "connect")) {
                self.constructing = true;
                app.connect(self) catch |err| {
                    self.constructing = false;
                    return err;
                };
                self.constructing = false;
            }
            return self;
        }
        fn allocate(a: std.mem.Allocator, app: *App) s.Error!*Self {
            const guard = Guard.init();
            var graph = try scenes.Graph(App).init(a, &App.scenes);
            errdefer graph.deinit();
            const self = try a.create(Self);
            self.* = .{ .guard = guard, .allocator = a, .app = app, .graph = graph, .store = undefined };
            self.instance_id = @intFromPtr(self);
            self.store = .{ .allocator = a, .executor = s.executor(&self.guard), .dirty = &self.dirty };
            return self;
        }
        fn enter(self: *Self) s.Error!void {
            try self.guard.check();
            if (self.busy or self.store.editing) return error.Reentrant;
            self.busy = true;
        }
        fn leave(self: *Self) void {
            self.busy = false;
        }

        /// Release the stable owner and its resources; no handle may be used afterward.
        pub fn destroy(self: *Self) s.Error!void {
            try self.guard.check();
            if (self.constructing) return error.Reentrant;
            try self.enter();
            self.detachChecks() catch |e| {
                self.leave();
                return e;
            };
            self.cancelAllInternal();
            if (self.candidate) |p| {
                self.store.finish(false);
                self.release(p);
            }
            if (self.published) |p| self.release(p);
            self.store.deinit();
            self.subscriptions.deinit(self.allocator);
            if (self.completion) |result| if (result.message) |message| self.allocator.free(message);
            for (self.lines.items) |line| self.allocator.free(line);
            self.lines.deinit(self.allocator);
            self.graph.deinit();
            const a = self.allocator;
            a.destroy(self);
        }
        fn release(self: *Self, candidate: *Candidate) void {
            candidate.frame.deinit();
            self.allocator.destroy(candidate);
        }
        /// Signal/plugin notifications may mark dirty during guarded rendering or actions.
        /// This hook permits no recursive preparation, destruction or state mutation.
        pub fn checkExecutor(self: *Self) s.Error!void {
            try self.guard.check();
        }

        /// Owner callback that marks the associated host dirty.
        pub fn notifyInvalidation(self: *Self) s.Error!void {
            try self.guard.check();
            self.dirty = true;
        }

        /// Mark the associated live host dirty for a subsequent frame.
        pub fn invalidate(self: *Self) s.Error!void {
            try self.enter();
            defer self.leave();
            self.dirty = true;
        }

        /// Report whether pending state/input requires another publication.
        pub fn needsFrame(self: *Self) s.Error!bool {
            try self.guard.check();
            return self.dirty;
        }

        /// Report the host's reserved quit-request state.
        pub fn wantsQuit(self: *Self) s.Error!bool {
            try self.guard.check();
            return self.wants_quit;
        }

        /// Borrow the first application-declared completion; its message lasts until host destruction.
        pub fn completionStatus(self: *Self) s.Error!?Completion {
            try self.guard.check();
            return self.completion;
        }
        fn finishInternal(self: *Self, p: *Candidate, context: anytype, comptime callback: fn (@TypeOf(context), Preparation) s.Error![]const u8) s.Error!void {
            _ = self;
            const a = p.frame.arena.allocator();
            const bytes = try callback(context, .{ .tree = &p.tree, .allocator = a });
            p.output = try a.dupe(u8, bytes);
        }
        /// Build/layout is staged; painters and serializers must finish before commit.
        pub fn prepare(self: *Self, size: geo.Size) s.Error!?PreparedFrame {
            try self.enter();
            defer self.leave();
            if (self.candidate != null) return error.InvalidTransaction;
            if (!std.meta.eql(self.size, size)) self.dirty = true;
            if (!self.dirty) return null;
            if (self.next_generation == std.math.maxInt(u64)) return error.GenerationExhausted;
            const generation = self.next_generation;
            self.next_generation += 1;
            const p = try self.allocator.create(Candidate);
            p.* = .{ .frame = .init(self.allocator), .generation = generation, .focus = self.focus };
            self.candidate = p;
            errdefer {
                self.candidate = null;
                self.release(p);
                self.dirty = true;
            }
            try self.store.begin();
            errdefer self.store.finish(false);
            self.size = size;
            self.dirty = false; // Reset before build so synchronous model writes request follow-up.
            try self.buildCandidate(p, size);
            const initial_focus = p.focus;
            if (p.focus) |old| {
                var found = false;
                for (p.focusable.items) |id| if (id.raw == old.raw) {
                    found = true;
                    break;
                };
                if (!found) p.focus = null;
            }
            if (p.focus == null and p.focusable.items.len > 0) p.focus = p.focusable.items[0];
            if (!std.meta.eql(initial_focus, p.focus)) {
                // Keep staged state allocations and accepted writes across passes, sweep only final membership.
                try self.store.nextPass();
                p.frame.deinit();
                p.frame = .init(self.allocator);
                p.registrations = .empty;
                p.focusable = .empty;
                p.interactive = .empty;
                p.duplicates = .empty;
                p.regions = .empty;
                p.native_regions = .empty;
                p.duplicate_native_regions = .empty;
                try self.buildCandidate(p, size);
            }
            // Replacements only report committed cells, not new/removal/positional reuse.
            for (self.store.entries.items) |entry| if (entry.value != null and entry.seen and !entry.committed) {
                for (self.store.entries.items) |old| if (old.value != null and old.committed and old.id.raw == entry.id.raw and old.slot == entry.slot) {
                    try p.replaced.append(p.frame.arena.allocator(), entry.id);
                    break;
                };
            };
            return .{ .owner = self, .generation = generation };
        }
        fn candidateFor(self: *Self, token: PreparedFrame) s.Error!*Candidate {
            try self.guard.check();
            if (self.busy or self.store.editing) return error.Reentrant;
            if (token.owner != self) return error.InvalidTransaction;
            const p = self.candidate orelse return error.InvalidTransaction;
            if (p.generation != token.generation) return error.InvalidTransaction;
            return p;
        }

        /// Publish the prepared transaction once; all copies of its token become invalid.
        pub fn commit(self: *Self, token: PreparedFrame) s.Error!void {
            const p = try self.candidateFor(token);
            try self.enter();
            defer self.leave();
            self.publishInternal(p);
        }
        fn publishInternal(self: *Self, p: *Candidate) void {
            self.store.finish(true);
            if (self.published) |old| self.release(old);
            self.published = p;
            self.candidate = null;
            self.focus = p.focus;
        }

        /// Discard the prepared transaction and retain the previous publication for retry.
        pub fn abort(self: *Self, token: PreparedFrame) s.Error!void {
            const p = try self.candidateFor(token);
            try self.enter();
            defer self.leave();
            self.store.finish(false);
            self.candidate = null;
            self.release(p);
            self.dirty = true;
        }
        /// Headless layout transaction; adapters use PreparedFrame.finish for paint/encode publication.
        pub fn rebuild(self: *Self, size: geo.Size) s.Error!void {
            if (try self.prepare(size)) |p| try p.commit();
        }

        /// Borrow the last successfully published node, or null before first publication.
        pub fn currentNode(self: *Self) s.Error!?Node {
            try self.guard.check();
            return if (self.published) |p| p.node else null;
        }

        /// Borrow duplicate control identities diagnosed in the published frame.
        pub fn duplicateInteractiveIDs(self: *Self) s.Error![]const NodeID {
            try self.guard.check();
            return if (self.published) |p| p.duplicates.items else &.{};
        }

        /// Borrow state identities replaced at an existing slot; new/removed slots are not replacements.
        pub fn transientStateIDs(self: *Self) s.Error![]const NodeID {
            try self.guard.check();
            return if (self.published) |p| p.replaced.items else &.{};
        }
        fn authorizedBuild(raw: *anyopaque) s.Error!*Self {
            const self: *Self = @ptrCast(@alignCast(raw));
            try self.guard.check();
            if (!self.busy or self.candidate == null) return error.InvalidTransaction;
            return self;
        }
        fn stateHook(raw: *anyopaque, id: NodeID, slot: u32, operations: *const s.ValueOps, initial: *const anyopaque) s.Error!s.BindingToken {
            const self = try authorizedBuild(raw);
            return self.store.resolve(id, slot, operations, initial);
        }
        fn offsetHook(raw: *anyopaque, id: NodeID, slot: u32) s.Error!i64 {
            const self = try authorizedBuild(raw);
            const initial: i64 = 0;
            const token = try self.store.resolve(id, slot, s.ops(i64), &initial);
            return (try (s.StateRef(i64){ .owner = &self.store, .token = token }).read()).*;
        }
        fn registerHook(raw: *anyopaque, registration: c.Registration) s.Error!void {
            const self = try authorizedBuild(raw);
            var staged: Staged = .{ .registration = registration };
            switch (registration) {
                .text_field => |v| {
                    _ = try self.store.get(v.binding, s.ops(s.String));
                    const initial: text.Selection = .{};
                    staged.state = try self.store.resolve(v.id, v.cursor_slot, s.ops(text.Selection), &initial);
                },
                .toggle => |v| {
                    _ = try self.store.get(v.binding, s.ops(bool));
                },
                .virtual_list => |v| {
                    const initial: i64 = 0;
                    staged.state = try self.store.resolve(v.id, v.slot, s.ops(i64), &initial);
                },
                else => {},
            }
            const p = self.candidate.?;
            try p.registrations.append(p.frame.arena.allocator(), staged);
        }
        fn buildCandidate(self: *Self, p: *Candidate, size: geo.Size) s.Error!void {
            var ctx = p.frame.context();
            ctx.surface_size = size;
            ctx.focus = p.focus;
            ctx.environment.window_context.instance_id = self.instance_id;
            ctx.hooks = .{ .host = self, .store = &self.store, .state_fn = stateHook, .register_fn = registerHook, .offset_fn = offsetHook };
            p.node = try self.graph.renderPrimary(self.app, &ctx);
            p.tree = try layout.place(p.frame.arena.allocator(), p.node, .{ .size = size }, .{});
            try self.collectFocus(p, p.tree);
            try deduplicateNativeRegions(p);
            // Diagnostics retain first visual occurrence order, even when second occurrences interleave.
            for (p.interactive.items, 0..) |id, i| {
                var first = true;
                for (p.interactive.items[0..i]) |seen| if (seen.raw == id.raw) {
                    first = false;
                    break;
                };
                if (!first) continue;
                for (p.interactive.items[i + 1 ..]) |later| if (later.raw == id.raw) {
                    try p.duplicates.append(p.frame.arena.allocator(), id);
                    break;
                };
            }
        }
        fn collectFocus(self: *Self, p: *Candidate, tree: layout.LaidNode) s.Error!void {
            const a = p.frame.arena.allocator();
            if (tree.node == .interactive) {
                const v = tree.node.interactive;
                try p.interactive.append(a, v.id);
                try p.regions.append(a, .{ .id = v.id, .frame = tree.frame, .focusable = v.focusable });
                if (v.focusable) try p.focusable.append(a, v.id);
                var index = p.registrations.items.len;
                while (index > 0) {
                    index -= 1;
                    const entry = p.registrations.items[index];
                    if (entry.registration == .native_region) {
                        const native = entry.registration.native_region;
                        if (native.id.raw == v.id.raw) {
                            try p.native_regions.append(a, .{ .id = native.id, .region_id = native.region_id, .frame = tree.frame });
                            break;
                        }
                    }
                }
            }
            for (tree.children) |child| try self.collectFocus(p, child);
        }
        // Latest NodeID registration, then last visual region identity wins.
        // Diagnostics preserve first visual occurrence order, as in the baseline.
        fn deduplicateNativeRegions(p: *Candidate) s.Error!void {
            var kept: std.ArrayList(NativeRegion) = .empty;
            const a = p.frame.arena.allocator();
            for (p.native_regions.items, 0..) |entry, i| {
                var later = false;
                for (p.native_regions.items[i + 1 ..]) |other| if (std.mem.eql(u8, entry.region_id, other.region_id)) {
                    later = true;
                    break;
                };
                if (!later) {
                    try kept.append(a, entry);
                    continue;
                }
                var reported = false;
                for (p.duplicate_native_regions.items) |id| if (std.mem.eql(u8, entry.region_id, id)) {
                    reported = true;
                    break;
                };
                if (!reported) try p.duplicate_native_regions.append(a, entry.region_id);
            }
            p.native_regions = kept;
        }

        /// Borrow duplicate semantic region labels from the published frame.
        pub fn duplicateNativeRegionIDs(self: *Self) s.Error![]const []const u8 {
            try self.guard.check();
            return if (self.published) |p| p.duplicate_native_regions.items else &.{};
        }
        /// Published borrows expire only on successful replacement or host destruction.
        pub fn currentTree(self: *Self) s.Error!?*const layout.LaidNode {
            try self.guard.check();
            return if (self.published) |p| &p.tree else null;
        }

        /// Borrow the last published bytes until the next successful publication or destruction.
        pub fn currentOutput(self: *Self) s.Error![]const u8 {
            try self.guard.check();
            return if (self.published) |p| p.output else &.{};
        }

        /// Borrow semantic region records from the last published layout.
        pub fn nativeRegions(self: *Self) s.Error![]const NativeRegion {
            try self.guard.check();
            return if (self.published) |p| p.native_regions.items else &.{};
        }

        /// Return the current focused node identity, if any.
        pub fn focusedID(self: *Self) s.Error!?NodeID {
            try self.guard.check();
            return self.focus;
        }

        /// Return the current surface extent in cells.
        pub fn currentSize(self: *Self) s.Error!geo.Size {
            try self.guard.check();
            return self.size;
        }
        fn navigate(self: *Self, key: Key) void {
            const p = self.published orelse return;
            var current: ?geo.Rect = null;
            var current_index: ?usize = null;
            if (self.focus) |id| for (p.regions.items, 0..) |r, i| if (r.focusable and r.id.raw == id.raw) {
                current = r.frame;
                current_index = i;
                break;
            };
            var best: ?NodeID = null;
            var best_score: i128 = std.math.maxInt(i128);
            if (current) |origin| for (p.regions.items, 0..) |r, i| {
                if (!r.focusable or i == current_index.?) continue;
                const x = center(r.frame.origin.x, r.frame.maxX()) - center(origin.origin.x, origin.maxX());
                const y = center(r.frame.origin.y, r.frame.maxY()) - center(origin.origin.y, origin.maxY());
                const along = switch (key) {
                    .left => -x,
                    .right => x,
                    .up => -y,
                    else => y,
                };
                if (along <= 0) continue;
                const orthogonal = if (key == .left or key == .right) y else x;
                const score = along + 2 * @as(i128, @intCast(@abs(orthogonal)));
                if (score < best_score) {
                    best_score = score;
                    best = r.id;
                }
            };
            if (best) |id| {
                self.focus = id;
                self.dirty = true;
            } else self.cycle(key == .left or key == .up);
        }
        fn center(low: i64, high: i64) i128 {
            return @divTrunc(@as(i128, low) + high, 2);
        }

        /// Return a generation-bound handle for a currently published action.
        pub fn actionHandle(self: *Self, id: NodeID) s.Error!?ActionHandle {
            try self.guard.check();
            const p = self.published orelse return null;
            if (self.nodeAction(id) == null) return null;
            return .{ .owner = self, .generation = p.generation, .id = id };
        }
        fn nodeAction(self: *Self, id: NodeID) ?Staged {
            const p = self.published orelse return null;
            var i = p.registrations.items.len;
            while (i > 0) {
                i -= 1;
                const v = p.registrations.items[i];
                switch (v.registration) {
                    .action => |a| if (a.id.raw == id.raw) {
                        return v;
                    },
                    .toggle => |a| if (a.id.raw == id.raw) {
                        return v;
                    },
                    else => {},
                }
            }
            return null;
        }
        fn identity(v: Staged) ?c.ActionIdentity {
            return switch (v.registration) {
                .action => |a| a.identity,
                .toggle => |a| a.identity,
                else => null,
            };
        }
        fn invoke(self: *Self, v: Staged) s.Error!void {
            try v.registration.validate();
            switch (v.registration) {
                .action => |a| {
                    self.application_callback = true;
                    defer self.application_callback = false;
                    try a.action.invoke(self);
                },
                .toggle => |a| {
                    const ref: s.StateRef(bool) = .{ .owner = &self.store, .token = a.binding };
                    try ref.set(!(try ref.read()).*);
                },
                else => return,
            }
            self.dirty = true;
        }
        fn activate(self: *Self, id: NodeID) s.Error!bool {
            const action = self.nodeAction(id) orelse return false;
            try self.invoke(action);
            return true;
        }
        fn performInternal(self: *Self, name: []const u8) s.Error!bool {
            const p = self.published orelse return false;
            var i = p.registrations.items.len;
            while (i > 0) {
                i -= 1;
                const a = p.registrations.items[i];
                if (identity(a)) |id| if (std.mem.eql(u8, id.id, name)) {
                    try self.invoke(a);
                    return true;
                };
            }
            return false;
        }

        /// Under the host executor/reentry guard, invoke the last published registration matching name.
        /// Return false when no published command matches; propagate action/validity errors.
        pub fn perform(self: *Self, name: []const u8) s.Error!bool {
            try self.enter();
            defer self.leave();
            return self.performInternal(name);
        }
        fn shortcut(self: *Self, key: c.Shortcut) s.Error!bool {
            const p = self.published orelse return false;
            var i = p.registrations.items.len;
            while (i > 0) {
                i -= 1;
                if (identity(p.registrations.items[i])) |id| if (id.shortcut) |shortcut_key| if (std.meta.eql(key, shortcut_key)) return self.performInternal(id.id);
            }
            return false;
        }
        fn cycle(self: *Self, backward: bool) void {
            const p = self.published orelse return;
            if (p.focusable.items.len == 0) return;
            var index: usize = if (backward) 0 else p.focusable.items.len - 1;
            if (self.focus) |current| for (p.focusable.items, 0..) |id, i| if (id.raw == current.raw) {
                index = i;
                break;
            };
            index = if (backward) (if (index == 0) p.focusable.items.len - 1 else index - 1) else (index + 1) % p.focusable.items.len;
            self.focus = p.focusable.items[index];
            self.dirty = true;
        }
        fn control(self: *Self, id: NodeID, key: Key) s.Error!bool {
            const p = self.published orelse return false;
            var i = p.registrations.items.len;
            while (i > 0) {
                i -= 1;
                const staged = p.registrations.items[i];
                switch (staged.registration) {
                    .key_handler => |v| if (v.id.raw == id.raw) {
                        try staged.registration.validate();
                        self.application_callback = true;
                        defer self.application_callback = false;
                        return v.handler.invoke_fn(v.handler.capture, self, key);
                    },
                    .text_field => |v| if (v.id.raw == id.raw) {
                        try staged.registration.validate();
                        const value: s.StateRef(s.String) = .{ .owner = &self.store, .token = v.binding };
                        const cursor: s.StateRef(text.Selection) = .{ .owner = &self.store, .token = staged.state.? };
                        const bytes = (try value.read()).bytes;
                        const selection = (try cursor.read()).*;
                        var edit: ?text.Edit = null;
                        switch (key) {
                            .left, .right, .home, .end => {
                                const movement: text.Movement = switch (key) {
                                    .left => .left,
                                    .right => .right,
                                    .home => .home,
                                    else => .end,
                                };
                                const next = try text.move(bytes, selection, movement);
                                try cursor.set(next);
                                return true;
                            },
                            .character, .space => {
                                const character = if (key == .space) " " else key.character;
                                if (!try text.acceptsCharacter(character)) return true;
                                edit = try text.insert(self.allocator, bytes, selection, character);
                            },
                            .backspace, .delete => edit = try text.delete(self.allocator, bytes, selection, if (key == .backspace) .backward else .forward),
                            else => return false,
                        }
                        if (edit) |*e| {
                            defer e.deinit(self.allocator);
                            try value.set(.{ .bytes = e.value });
                            try cursor.set(e.selection);
                            return true;
                        }
                        return false;
                    },
                    .virtual_list => |v| if (v.id.raw == id.raw) {
                        try staged.registration.validate();
                        const offset: s.StateRef(i64) = .{ .owner = &self.store, .token = staged.state.? };
                        const raw_offset = (try offset.read()).*;
                        const max: i64 = @intCast(@min(v.max_offset, std.math.maxInt(i64)));
                        const old = @max(0, @min(max, raw_offset));
                        const page: i64 = @intCast(@min(v.capacity, std.math.maxInt(i64)));
                        const next = switch (key) {
                            .up => old -| 1,
                            .down => old +| 1,
                            .page_up => old -| page,
                            .page_down => old +| page,
                            .home => 0,
                            .end => max,
                            else => return false,
                        };
                        const bounded = @max(0, @min(max, next));
                        try offset.set(bounded);
                        return true;
                    },
                    else => {},
                }
            }
            return false;
        }

        /// Dispatch a semantic event through the current published registrations.
        pub fn handle(self: *Self, event: Event) s.Error!void {
            try self.enter();
            defer self.leave();
            switch (event) {
                .key => |key| try self.handleKey(key),
                .gamepad => |event_value| if (event_value.pressed) {
                    if (event_value.button.semanticKey()) |key| try self.handleKey(key);
                },
                .activate => |id| {
                    _ = try self.activate(id);
                },
                .pointer => |point| {
                    if (self.published) |p| {
                        var i = p.regions.items.len;
                        while (i > 0) {
                            i -= 1;
                            const hit = p.regions.items[i];
                            if (hit.frame.contains(point)) {
                                if (hit.focusable) self.focus = hit.id;
                                _ = try self.activate(hit.id);
                                self.dirty = true;
                                break;
                            }
                        }
                    }
                },
                .pointer_press => |hit| {
                    if (hit.focusable) self.focus = hit.id;
                    _ = try self.activate(hit.id);
                    self.dirty = true;
                },
                .resize => |size| {
                    self.size = size;
                    self.dirty = true;
                },
                .lifecycle => |life| try self.lifecycle(life),
                .tick, .pointer_release => {},
            }
        }
        fn handleKey(self: *Self, k: Key) s.Error!void {
            if (k == .character and std.mem.eql(u8, k.character, " ")) return self.handleKey(.space);
            switch (k) {
                .quit => {
                    try self.lifecycle(.{ .kind = .window_close_requested, .scene = self.graph.descriptors[self.graph.primary].id, .instance = self.instance_id });
                    self.wants_quit = true;
                    return;
                },
                .shortcut => |v| if (v.control and (v.codepoint == 'c' or v.codepoint == 'q')) {
                    try self.handleKey(.quit);
                    return;
                },
                .tab, .back_tab => {
                    self.cycle(k == .back_tab);
                    return;
                },
                else => {},
            }
            if (self.focus) |focused| {
                if (try self.control(focused, k)) {
                    self.dirty = true;
                    return;
                }
                switch (k) {
                    .enter, .space => {
                        _ = try self.activate(focused);
                        self.dirty = true;
                        return;
                    },
                    .left, .right, .up, .down => {
                        self.navigate(k);
                        return;
                    },
                    else => {},
                }
            }
            switch (k) {
                .shortcut => |v| {
                    _ = try self.shortcut(v);
                },
                .character => |bytes| {
                    var it = (std.unicode.Utf8View.init(bytes) catch return error.InvalidUtf8).iterator();
                    const cp = it.nextCodepoint() orelse return;
                    if (it.nextCodepoint() == null) _ = try self.shortcut(.{ .codepoint = cp });
                },
                else => {},
            }
        }
        fn lifecycle(self: *Self, life: Lifecycle) s.Error!void {
            if (life.scene) |scene| if (!std.mem.eql(u8, scene, self.graph.descriptors[self.graph.primary].id)) return;
            if (life.instance) |instance| if (instance != self.instance_id) return;
            if (@hasDecl(App, "onLifecycle")) {
                self.application_callback = true;
                defer self.application_callback = false;
                try self.app.onLifecycle(life);
            }
            self.dirty = true;
        }
        /// Bridge an explicitly observed app-owned SignalRef into control-compatible host tokens.
        /// Requires active observe(source) first; never subscribes implicitly. The bridge survives
        /// frame replacement/removal until cancelAll, source detach/destruction, or host destruction.
        /// Re-observation creates fresh generations; revoked handles never revive. Signal/app must
        /// outlive active use. Read borrows expire on Signal mutation; handles cannot outlive host.
        pub fn bind(self: *Self, reference: anytype) s.Error!s.StateRef(@TypeOf(reference).Value) {
            try self.enter();
            defer self.leave();
            const Ref = @import("signal.zig").SignalRef(@TypeOf(reference).Value);
            if (@TypeOf(reference) != Ref) @compileError("binding.requires-canonical-signal-reference");
            for (self.subscriptions.items) |sub| if (sub.active and sub.signal == reference.owner) {
                return self.store.bindSignal(reference);
            };
            return error.Unavailable;
        }

        /// Attach an explicit observer subscription; cancel it before either owner expires.
        pub fn observe(self: *Self, signal: anytype) s.Error!void {
            try self.enter();
            defer self.leave();
            var previous: ?usize = null;
            for (self.subscriptions.items, 0..) |sub, i| if (sub.signal == @as(*anyopaque, signal)) {
                if (sub.active) return;
                // A canceled snapshot may still borrow this owner. Keep its token until
                // tracked release, and continue searching for an already-live subscription.
                if (!sub.attached and previous == null) previous = i;
            };
            const Signal = @typeInfo(@TypeOf(signal)).pointer.child;
            const T = @TypeOf(signal.value);
            const Adapter = struct {
                fn notify(raw: *const anyopaque, _: @import("signal.zig").SignalRef(T)) s.Error!void {
                    const owner: *Self = @ptrCast(@alignCast(@constCast(raw)));
                    try owner.guard.check();
                    owner.dirty = true;
                }
                fn detached(raw: *const anyopaque, source: *Signal, token: @import("signal.zig").Token) void {
                    const owner: *Self = @ptrCast(@alignCast(@constCast(raw)));
                    for (owner.subscriptions.items) |*sub| if (sub.signal == @as(*anyopaque, source) and sub.token.generation == token.generation) {
                        // Canceled old tokens already revoked their bridges. Their delayed
                        // release must not revoke a newer live subscription's bridges.
                        if (sub.active) owner.store.revokeSignal(source);
                        sub.attached = false;
                        sub.active = false;
                    };
                }
                fn check(raw: *anyopaque, token: @import("signal.zig").Token) s.Error!void {
                    try @as(*Signal, @ptrCast(@alignCast(raw))).canDetachOwner(token);
                }
                fn canCancel(raw: *anyopaque) s.Error!void {
                    try @as(*Signal, @ptrCast(@alignCast(raw))).canObserveOwner();
                }
                fn cancel(raw: *anyopaque, token: @import("signal.zig").Token) s.Error!void {
                    try @as(*Signal, @ptrCast(@alignCast(raw))).cancel(token);
                }
            };
            try signal.canObserveOwner();
            if (previous == null) try self.subscriptions.ensureUnusedCapacity(self.allocator, 1);
            const token = try signal.observeOwnerTracked(self, Adapter.notify, Adapter.detached);
            const subscription: Subscription = .{ .signal = signal, .token = token, .check = Adapter.check, .cancel = Adapter.cancel, .can_cancel = Adapter.canCancel };
            if (previous) |i| self.subscriptions.items[i] = subscription else self.subscriptions.appendAssumeCapacity(subscription);
        }
        fn detachChecks(self: *Self) s.Error!void {
            for (self.subscriptions.items) |sub| if (sub.attached) {
                try sub.check(sub.signal, sub.token);
            };
        }
        fn cancelAllInternal(self: *Self) void {
            for (self.subscriptions.items) |*sub| {
                self.store.revokeSignal(sub.signal);
                if (sub.active) sub.cancel(sub.signal, sub.token) catch unreachable;
                sub.active = false;
            }
            // Retain signal identities: an in-flight snapshot may still borrow this host.
            // Actual destroy preflights even canceled subscriptions before releasing owner memory.
        }

        /// Cancel every subscription owned by this live owner.
        pub fn cancelAll(self: *Self) s.Error!void {
            try self.guard.check();
            // Direct bridge writes may synchronously cancel subscriptions. Host.handle still
            // holds busy and rejects reentry; destruction remains prohibited during either write.
            if (self.busy or (self.store.editing and !self.store.external_writing)) return error.Reentrant;
            self.busy = true;
            defer self.leave();
            for (self.subscriptions.items) |sub| if (sub.attached) {
                try sub.can_cancel(sub.signal);
            };
            self.cancelAllInternal();
        }

        // Outcome submission may nest only directly inside live application dispatch.
        // Suspend that admission during allocation/free, including allocator callbacks.
        fn enterOutcome(self: *Self) s.Error!bool {
            try self.guard.check();
            if (self.store.editing or (self.busy and !self.application_callback)) return error.Reentrant;
            // Observers may submit, but their sources' clone/deinit phases may not.
            // This preflight permits notification snapshots and rejects only editing.
            for (self.subscriptions.items) |sub| if (sub.attached) try sub.can_cancel(sub.signal);
            const callback = self.application_callback;
            self.application_callback = false;
            self.busy = true;
            return callback;
        }
        fn leaveOutcome(self: *Self, callback: bool) void {
            self.application_callback = callback;
            self.busy = callback;
        }

        /// Accept the first completion, cloning its message before acceptance and marking dirty.
        /// Allowed while idle or in a live action/key/lifecycle callback, including signal observers;
        /// active store mutation, internal operations and teardown reject with Reentrant.
        /// Executor/lifetime rules still apply. Later completions leave the first result unchanged.
        pub fn complete(self: *Self, result: Completion) s.Error!void {
            const callback = try self.enterOutcome();
            defer self.leaveOutcome(callback);
            if (self.completion != null) return;
            const message = if (result.message) |bytes| try self.allocator.dupe(u8, bytes) else null;
            self.completion = .{ .code = result.code, .message = message };
            self.dirty = true;
        }

        /// Clone and queue a semantic line; allocation failure accepts nothing and preserves the queue.
        /// Uses complete's callback admission; acknowledgement follows successful delivery only.
        pub fn emit(self: *Self, line: []const u8) s.Error!void {
            const callback = try self.enterOutcome();
            defer self.leaveOutcome(callback);
            const copy = try self.allocator.dupe(u8, line);
            errdefer self.allocator.free(copy);
            try self.lines.append(self.allocator, copy);
            self.dirty = true;
        }
        /// Borrow queued semantic lines until mutation; failed transport leaves them queued.
        pub fn pendingLines(self: *Self) s.Error![]const []const u8 {
            try self.guard.check();
            return self.lines.items;
        }
        /// Acknowledge only the prefix actually delivered. No allocation occurs.
        pub fn consumeLines(self: *Self, count: usize) s.Error!void {
            try self.enter();
            defer self.leave();
            if (count > self.lines.items.len) return error.InvalidTransaction;
            for (self.lines.items[0..count]) |line| self.allocator.free(line);
            std.mem.copyForwards([]const u8, self.lines.items, self.lines.items[count..]);
            self.lines.items.len -= count;
        }
        /// Transfers owned lines to caller; free each line and outer slice with host allocator.
        pub fn drain(self: *Self) s.Error![][]const u8 {
            try self.enter();
            defer self.leave();
            return self.lines.toOwnedSlice(self.allocator);
        }
    };
}
