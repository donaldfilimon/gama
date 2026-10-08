//! App-owned synchronous signals. Cancellation takes effect after the current snapshot.
const std = @import("std");
const s = @import("state.zig");
/// Owner-lifetime token: cancellation is idempotent while its source Signal lives.
/// It must not be reused after Signal destruction, including allocator address reuse.
pub const Token = struct {
    /// Borrowed owner pointer; this value must never outlive that owner.
    owner: usize,
    /// Observer generation issued monotonically by the signal; never synthesize a token.
    generation: u64,
};
/// Borrowed signal handle. Read pointers/payload slices expire on the next successful set or
/// signal destruction. Neither a reference nor a cached raw borrow may outlive the signal.
pub fn SignalRef(comptime T: type) type {
    return struct {
        /// Payload type carried by this generic reference.
        pub const Value = T;

        /// Borrowed owner pointer; this value must never outlive that owner.
        owner: *anyopaque,

        /// Type-erased checked read; returned pointer borrows the live signal value.
        read_fn: *const fn (*anyopaque) s.Error!*const T,

        /// Type-erased checked replacement; clones managed values before notifying observers.
        set_fn: *const fn (*anyopaque, T) s.Error!void,

        /// Forward to the signal read callback; the returned value borrows the live signal until replacement.
        /// The caller must already guarantee signal lifetime.
        pub fn read(self: @This()) s.Error!*const T {
            return self.read_fn(self.owner);
        }

        /// Forward replacement and observer delivery to the live signal; a notification error may follow mutation.
        /// Clone failure preserves the previous value; the caller must guarantee signal lifetime.
        pub fn set(self: @This(), value: T) s.Error!void {
            try self.set_fn(self.owner, value);
        }
    };
}
/// Specialize a stable heap signal for a validated value type and confinement guard.
pub fn Implementation(comptime T: type, comptime Guard: type) type {
    return struct {
        const Self = @This();
        const Observer = struct {
            /// Observer generation used for snapshot cutoff and cancellation matching.
            id: u64,

            /// False after cancellation; pending snapshot delivery may still complete before collection.
            alive: bool = true,

            /// Owned cloned capture or borrowed owner capture according to the registration method.
            capture: *const anyopaque,

            /// Synchronous observer callback receiving a live signal reference.
            invoke: *const fn (*const anyopaque, SignalRef(T)) s.Error!void,

            /// Destructor for an owned capture; null marks a borrowed owner capture.
            release: ?*const fn (*const anyopaque, std.mem.Allocator) void = null,

            /// Optional owner-detachment callback invoked when the observer is released.
            owner_release: ?*const fn (*const anyopaque, *Self, Token) void = null,
        };

        /// Executor/reentrancy guard; callers must use checked methods instead of changing it.
        guard: Guard,

        /// Allocator owning the signal, cloned value and captures; retain until destroy.
        allocator: std.mem.Allocator,

        /// Owned current value; read borrows it and set replaces it through clone/deinit hooks.
        value: T,

        /// Owner-managed observer records; mutation must go through observe/cancel.
        observers: std.ArrayList(Observer) = .empty,

        /// Next observer generation; monotonically issued and never reused.
        next_id: u64 = 1,

        /// Whether snapshot observer delivery is in progress.
        notifying: bool = false,

        /// Exclusive generation cutoff of the active notification snapshot.
        snapshot_cutoff: u64 = 0,

        /// Reentry guard during value/capture clone and destruction.
        editing: bool = false,

        /// Allocate a stable signal and clone initial; retain allocator until destroy and never copy the owner.
        pub fn create(a: std.mem.Allocator, initial: T) s.Error!*Self {
            const guard = Guard.init();
            const self = try a.create(Self);
            errdefer a.destroy(self);
            self.* = .{ .guard = guard, .allocator = a, .value = try s.clone(T, &initial, a) };
            return self;
        }

        /// Release the stable owner and its resources; no handle may be used afterward.
        pub fn destroy(self: *Self) s.Error!void {
            try self.guard.check();
            if (self.notifying or self.editing) return error.Reentrant;
            self.editing = true;
            for (self.observers.items) |o| self.releaseObserver(o);
            self.observers.deinit(self.allocator);
            s.deinit(T, &self.value, self.allocator);
            const a = self.allocator;
            a.destroy(self);
        }

        /// Return a checked borrowed signal handle; it must not outlive the signal.
        pub fn reference(self: *Self) s.Error!SignalRef(T) {
            try self.guard.check();
            return .{ .owner = self, .read_fn = readRaw, .set_fn = setRaw };
        }
        fn readRaw(raw: *anyopaque) s.Error!*const T {
            return @as(*Self, @ptrCast(@alignCast(raw))).read();
        }
        fn setRaw(raw: *anyopaque, value: T) s.Error!void {
            return @as(*Self, @ptrCast(@alignCast(raw))).set(value);
        }

        /// Check executor/editing guards and borrow value until its next replacement or signal destruction.
        pub fn read(self: *Self) s.Error!*const T {
            try self.guard.check();
            if (self.editing) return error.Reentrant;
            return &self.value;
        }

        /// Clone before replacement, preserving the old value if cloning fails, then notify the observer snapshot.
        /// Observer errors are returned after replacement; nested writes do not recursively notify.
        pub fn set(self: *Self, value: T) s.Error!void {
            try self.guard.check();
            if (self.editing) return error.Reentrant;
            self.editing = true;
            const next = s.clone(T, &value, self.allocator) catch |e| {
                self.editing = false;
                return e;
            };
            s.deinit(T, &self.value, self.allocator);
            self.value = next;
            self.editing = false;
            if (self.notifying) return;
            self.notifying = true;
            defer {
                self.notifying = false;
                self.collect();
            }
            // Length + monotonic registration IDs freeze order/membership without snapshot allocation.
            const length = self.observers.items.len;
            const cutoff = self.next_id;
            self.snapshot_cutoff = cutoff;
            var first_error: ?s.Error = null;
            for (0..length) |i| {
                const observer = self.observers.items[i];
                if (observer.id < cutoff) observer.invoke(observer.capture, try self.reference()) catch |e| {
                    if (first_error == null) first_error = e;
                };
            }
            if (first_error) |e| return e;
        }

        /// Compare before cloning/replacing the value and notifying observers.
        pub fn setIfChanged(self: *Self, value: T) s.Error!void {
            const current = try self.read();
            const equal = if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "clone")) blk: {
                if (!@hasDecl(T, "eql")) @compileError("signal.managed-value-requires-eql");
                break :blk T.eql(current, &value);
            } else std.meta.eql(current.*, value);
            if (!equal) try self.set(value);
        }

        /// Clone capture into signal-owned subscription storage and return its cancellation token.
        /// The signal releases that copy after cancellation is safe or during destruction.
        pub fn observe(self: *Self, capture: anytype, comptime callback: fn (*const @TypeOf(capture), SignalRef(T)) s.Error!void) s.Error!Token {
            try self.guard.check();
            if (self.editing) return error.Reentrant;
            self.editing = true;
            defer self.editing = false;
            const C = @TypeOf(capture);
            comptime @import("context.zig").validateCapture(C);
            const copy = try self.allocator.create(C);
            errdefer self.allocator.destroy(copy);
            copy.* = try @import("context.zig").cloneCapture(C, &capture, self.allocator);
            errdefer @import("context.zig").deinitCapture(C, copy, self.allocator);
            const Adapter = struct {
                fn invoke(raw: *const anyopaque, ref: SignalRef(T)) s.Error!void {
                    return callback(@ptrCast(@alignCast(raw)), ref);
                }
                fn release(raw: *const anyopaque, a: std.mem.Allocator) void {
                    const capture_value: *C = @ptrCast(@alignCast(@constCast(raw)));
                    @import("context.zig").deinitCapture(C, capture_value, a);
                    a.destroy(capture_value);
                }
            };
            return self.add(copy, Adapter.invoke, Adapter.release);
        }
        /// Internal stable-owner subscription hook. The owner must cancel before releasing capture.
        pub fn observeOwner(self: *Self, capture: *const anyopaque, callback: *const fn (*const anyopaque, SignalRef(T)) s.Error!void) s.Error!Token {
            try self.guard.check();
            if (self.editing) return error.Reentrant;
            return self.add(capture, callback, null);
        }
        /// Internal host hook receives notice once no snapshot can use its owner capture.
        pub fn observeOwnerTracked(self: *Self, capture: *const anyopaque, callback: *const fn (*const anyopaque, SignalRef(T)) s.Error!void, released: *const fn (*const anyopaque, *Self, Token) void) s.Error!Token {
            const token = try self.observeOwner(capture, callback);
            self.observers.items[self.observers.items.len - 1].owner_release = released;
            return token;
        }
        fn releaseObserver(self: *Self, observer: Observer) void {
            if (observer.release) |release| release(observer.capture, self.allocator);
            if (observer.owner_release) |release| release(observer.capture, self, .{ .owner = @intFromPtr(self), .generation = observer.id });
        }
        fn add(self: *Self, capture: *const anyopaque, callback: *const fn (*const anyopaque, SignalRef(T)) s.Error!void, release: ?*const fn (*const anyopaque, std.mem.Allocator) void) s.Error!Token {
            if (self.next_id == std.math.maxInt(u64)) return error.GenerationExhausted;
            const id = self.next_id;
            try self.observers.append(self.allocator, .{ .id = id, .capture = capture, .invoke = callback, .release = release });
            self.next_id += 1;
            return .{ .owner = @intFromPtr(self), .generation = id };
        }

        /// Check the signal executor and reject capture editing before adding an owner subscription.
        pub fn canObserveOwner(self: *Self) s.Error!void {
            try self.guard.check();
            if (self.editing) return error.Reentrant;
        }
        /// Owner detach cannot occur inside a snapshot: its raw owner storage must stay alive.
        pub fn canDetachOwner(self: *Self, token: Token) s.Error!void {
            try self.guard.check();
            if (self.editing) return error.Reentrant;
            if (self.notifying and token.generation < self.snapshot_cutoff) {
                for (self.observers.items) |observer| if (observer.id == token.generation) return error.Reentrant;
            }
        }

        /// Invalidate the subscription token; repeated cancellation is harmless while its owner lives.
        pub fn cancel(self: *Self, token: Token) s.Error!void {
            try self.guard.check();
            if (self.editing) return error.Reentrant;
            if (token.owner != @intFromPtr(self)) return;
            for (self.observers.items, 0..) |*o, i| if (o.id == token.generation) {
                o.alive = false;
                if (self.notifying and o.id >= self.snapshot_cutoff) {
                    // Added after snapshot: removing its suffix entry cannot change snapshot indices.
                    const removed = self.observers.orderedRemove(i);
                    self.editing = true;
                    defer self.editing = false;
                    self.releaseObserver(removed);
                    return;
                }
                break;
            };
            if (!self.notifying) self.collect();
        }
        fn collect(self: *Self) void {
            self.editing = true;
            defer self.editing = false;
            var dest: usize = 0;
            for (self.observers.items) |o| {
                if (!o.alive) {
                    self.releaseObserver(o);
                } else {
                    self.observers.items[dest] = o;
                    dest += 1;
                }
            }
            self.observers.items.len = dest;
        }
    };
}
