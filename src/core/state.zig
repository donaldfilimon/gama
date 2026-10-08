//! Managed values provide clone(*const T, Allocator) Error!T and deinit(*T, Allocator) void.
//! Clone must produce independently owned storage; caller retains ownership of every initial/set value.
//! Hooks must not reenter the value's owner. Enclosing aggregates need their own hooks for managed fields.
//! Single-executor state ownership. Handles and borrows must not outlive their owner.
const std = @import("std");
const NodeID = @import("identity.zig").NodeID;
/// Shared recoverable errors across portable state, rendering and hosted adapters.
pub const Error = error{
    /// Supplied signal metadata is duplicate, unsupported or differs from observable installed action state.
    InvalidDisposition,
    /// A custom Darwin action lacks the exact caller-owned record needed for safe restoration.
    UnverifiableDisposition,
    /// Another terminal owner holds the process-wide acquisition guard.
    TerminalBusy,
    /// The terminal rescue epoch is no longer active after signal restoration.
    TerminalInterrupted,
    /// Nonblocking output made no progress within the bounded stall interval.
    OutputStalled,
    /// Input descriptor reached EOF or a terminal hangup was observed.
    EndOfInput,
    /// An active installation already has the requested plugin ID.
    DuplicatePlugin,
    /// Plugin manifest ABI does not equal the supported ABI version 1.
    ABIMismatch,
    /// A required plugin capability is not covered by its host grant.
    MissingRequiredCapability,
    /// A required host service has no usable callback or clock.
    ServiceUnavailable,
    /// Plugin-defined activation failure propagated to the installer.
    ActivationFailed,
    /// A plugin attempted to contribute a primary scene; only auxiliary contributions are admitted.
    PrimarySceneContribution,
    /// The installed capability scope does not authorize the requested operation/path.
    AccessDenied,
    /// Underlying host I/O failed without a more specific portable error mapping.
    IOFailure,
    /// Input or service payload exceeds the configured bounded capacity.
    LimitExceeded,
    /// Underlying I/O was canceled before successful completion.
    Canceled,
    /// A hosted service byte limit exceeds the supported maximum.
    InvalidLimit,
    /// Clock value is negative or cannot be represented in u64 milliseconds.
    InvalidClock,
    /// Frame dimensions or serialized output length exceed the admitted boundary limits.
    FrameTooLarge,
    /// Wire input ends before the required field or text payload is complete.
    Truncated,
    /// Wire header does not contain the GAMA magic value.
    BadMagic,
    /// Wire header version is not the supported version 1.
    UnsupportedVersion,
    /// Wire header width or height is negative.
    NegativeDimensions,
    /// Declared command count cannot fit in the remaining wire bytes.
    CommandCountOverflow,
    /// Wire command tag is neither fill nor text.
    UnknownCommandKind,
    /// Decoded fill rectangle width or height is negative.
    NegativeRect,
    /// Bytes remain after the declared wire commands have been decoded.
    TrailingBytes,
    /// Allocator could not reserve storage required by the operation.
    OutOfMemory,
    /// Input bytes are not a valid UTF-8 sequence.
    InvalidUtf8,
    /// Owner, type, generation or active-installation validation rejected the handle.
    InvalidHandle,
    /// Required host hook, installed context or platform operation is absent.
    Unavailable,
    /// Collection length or positional index cannot fit its supported integer representation.
    CollectionTooLarge,
    /// A native owner was accessed from a thread other than its creating thread.
    WrongThread,
    /// An operation would reenter protected mutation, callback delivery or payload access.
    Reentrant,
    /// The monotonic handle/epoch generation space cannot issue another value safely.
    GenerationExhausted,
    /// Frame/state transaction token or phase does not match the active operation.
    InvalidTransaction,
    /// Character input is not an admitted scalar or exactly one extended grapheme.
    InvalidCharacter,
    /// Edited/encoded text length exceeds the destination integer or wire representation.
    TextTooLarge,
    /// Two scene descriptors have equal identifiers.
    DuplicateSceneID,
    /// A required launch/primary scene payload is explicitly absent.
    MissingInitialPayload,
    /// No descriptor is marked primary.
    MissingPrimaryScene,
    /// More than one descriptor is marked primary.
    MultiplePrimaryScenes,
};
/// Borrowed executor guard; its context must outlive every check.
pub const Executor = struct {
    /// Borrowed guard userdata passed to check_fn; retain for the guard's use lifetime.
    context: *const anyopaque,

    /// Reject execution outside the owner's permitted executor/thread.
    check_fn: *const fn (*const anyopaque) Error!void,

    /// Invoke the borrowed executor guard; the caller must already guarantee its lifetime.
    pub fn check(self: Executor) Error!void {
        try self.check_fn(self.context);
    }
};
/// No-op guard for callers that guarantee single-executor access themselves.
pub const SingleExecutor = struct {
    /// Create the allocation-free guard; caller remains responsible for confinement.
    pub fn init() SingleExecutor {
        return .{};
    }

    /// Perform no runtime check; callers guarantee single-executor access by contract.
    pub fn check(_: *const SingleExecutor) Error!void {}
};
/// Wrap guard.check in a type-erased callback borrowing guard; keep its address stable and alive.
pub fn executor(guard: anytype) Executor {
    return .{ .context = guard, .check_fn = struct {
        fn check(raw: *const anyopaque) Error!void {
            try @as(*const @typeInfo(@TypeOf(guard)).pointer.child, @ptrCast(@alignCast(raw))).check();
        }
    }.check };
}
/// Store-issued owner/index/generation tuple; only valid while the store is alive.
pub const BindingToken = struct {
    /// Borrowed owner pointer; this value must never outlive that owner.
    owner: u64,
    /// Entry slot index checked against the issuing store before access.
    index: u64,
    /// Entry generation checked together with owner and index before reading state.
    generation: u64,
};
/// A value with borrowed bytes may seed storage; clone gives each cell its own bytes.
pub const String = struct {
    /// UTF-8 input borrowed until clone; cloned instances own this allocation and release it in deinit.
    bytes: []const u8,

    /// Compare the semantic contents without transferring ownership.
    pub fn eql(self: *const String, other: *const String) bool {
        return std.mem.eql(u8, self.bytes, other.bytes);
    }

    /// Allocate an independently owned copy with the supplied allocator.
    pub fn clone(self: *const String, a: std.mem.Allocator) Error!String {
        _ = try @import("unicode.zig").count(self.bytes);
        return .{ .bytes = try a.dupe(u8, self.bytes) };
    }

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *String, a: std.mem.Allocator) void {
        a.free(self.bytes);
    }
};
/// Compile-time reject unmanaged ownership forms that cannot be safely cloned.
pub fn validateValue(comptime T: type) void {
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "clone") and @hasDecl(T, "deinit")) {
        if (@TypeOf(T.clone) != fn (*const T, std.mem.Allocator) Error!T or @TypeOf(T.deinit) != fn (*T, std.mem.Allocator) void) @compileError("state.invalid-managed-hooks");
        return;
    }
    switch (@typeInfo(T)) {
        .pointer, .@"fn", .@"opaque" => @compileError("state.value-requires-clone-and-deinit"),
        .@"struct" => |s| inline for (s.field_types) |F| validateValue(F),
        .@"union" => @compileError("state.union-requires-clone-and-deinit"),
        .array => |a| validateValue(a.child),
        .vector => |v| validateValue(v.child),
        .optional => |o| validateValue(o.child),
        .error_union => |e| validateValue(e.payload),
        else => {},
    }
}
/// Call managed T.clone with a, or copy a validated plain value without allocation.
/// Release any managed result with the matching deinit and allocator.
pub fn clone(comptime T: type, value: *const T, a: std.mem.Allocator) Error!T {
    comptime validateValue(T);
    if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "clone")) return value.clone(a);
    // Nested managed fields must provide hooks on their enclosing value as well.
    comptime validatePlain(T);
    return value.*;
}
fn validatePlain(comptime T: type) void {
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (@hasDecl(T, "clone")) @compileError("state.nested-managed-value-requires-hooks");
            inline for (s.field_types) |F| validatePlain(F);
        },
        .array => |a| validatePlain(a.child),
        .vector => |v| validatePlain(v.child),
        .optional => |o| validatePlain(o.child),
        .error_union => |e| validatePlain(e.payload),
        else => {},
    }
}
/// Call T.deinit for managed structs using the allocation owner; do nothing for plain values.
pub fn deinit(comptime T: type, value: *T, a: std.mem.Allocator) void {
    if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "deinit")) value.deinit(a);
}
/// Static type-erased operations for one validated state value type.
pub const ValueOps = struct {
    /// Static Zig type name used for diagnostics.
    name: []const u8,

    /// Allocate and clone a value; input is borrowed only for this call.
    create: *const fn (*const anyopaque, std.mem.Allocator) Error!*anyopaque,

    /// Clone input before replacing the old value, preserving it if cloning fails.
    replace: *const fn (*anyopaque, *const anyopaque, std.mem.Allocator) Error!void,

    /// Deinitialize and free the heap value using its original allocator.
    release: *const fn (*anyopaque, std.mem.Allocator) void,
};
/// Return the static type-erased create, clone-before-replace and release table for T.
pub fn ops(comptime T: type) *const ValueOps {
    return &struct {
        const table: ValueOps = .{ .name = @typeName(T), .create = create, .replace = replace, .release = release };
        fn create(raw: *const anyopaque, a: std.mem.Allocator) Error!*anyopaque {
            const p = try a.create(T);
            errdefer a.destroy(p);
            p.* = try clone(T, @ptrCast(@alignCast(raw)), a);
            return p;
        }
        fn replace(raw: *anyopaque, input: *const anyopaque, a: std.mem.Allocator) Error!void {
            const p: *T = @ptrCast(@alignCast(raw));
            const next = try clone(T, @ptrCast(@alignCast(input)), a);
            deinit(T, p, a);
            p.* = next;
        }
        fn release(raw: *anyopaque, a: std.mem.Allocator) void {
            const p: *T = @ptrCast(@alignCast(raw));
            deinit(T, p, a);
            a.destroy(p);
        }
    }.table;
}
/// Stable-address owner of identity-keyed state and external signal bindings.
pub const Store = struct {
    const Entry = struct {
        /// Structural node key for a local state slot; external signal adapters use root.
        id: NodeID,
        /// State slot within a node identity; keep stable across renders of the same component.
        slot: u32,
        /// Unique generation assigned when the entry receives a new value.
        generation: u64,
        /// Owned local value or owned signal-reference capture; null marks a vacant/revoked slot.
        value: ?*anyopaque,
        /// Static operation table identifying the stored value type.
        operations: *const ValueOps,
        /// Whether this value belongs to an accepted frame, so abort must retain it.
        committed: bool = false,
        /// Whether the current construction pass referenced this entry.
        seen: bool = true,
        /// Signal adapter when value stores a reference capture rather than local state.
        external: ?External = null,
    };
    const External = struct {
        /// Borrowed signal owner identity used for deduplication and revocation.
        source: *anyopaque,
        /// Read through the captured signal reference and validate its executor.
        read: *const fn (*anyopaque) Error!*anyopaque,
        /// Write through the captured signal reference, notifying its observers.
        write: *const fn (*anyopaque, *const anyopaque) Error!void,
        /// Free the reference capture without destroying the external signal owner.
        release: *const fn (*anyopaque, std.mem.Allocator) void,
    };

    /// Allocator owning entries and cloned values; retain until Store.deinit.
    allocator: std.mem.Allocator,

    /// Borrowed confinement guard checked before state access.
    executor: Executor,

    /// Borrowed host dirty flag set after a successful value change.
    dirty: *bool,

    /// Owner-managed state slots; vacant entries retain their old generation until reuse.
    entries: std.ArrayList(Entry) = .empty,

    /// Next issued binding generation; failed/aborted generations are never reused.
    next_generation: u64 = 1,

    /// Whether a frame-state transaction is open.
    staging: bool = false,

    /// Reentry guard while cloning, replacing or releasing state values.
    editing: bool = false,

    /// True during a signal write initiated by this store, preventing duplicate invalidation.
    external_writing: bool = false,
    /// Internal subscription-owned bridge. Values remain exclusively owned by the Signal.
    pub fn bindSignal(self: *Store, ref: anytype) Error!StateRef(@TypeOf(ref).Value) {
        try self.executor.check();
        if (self.editing) return error.Reentrant;
        const T = @TypeOf(ref).Value;
        const Ref = @import("signal.zig").SignalRef(T);
        if (@TypeOf(ref) != Ref) @compileError("binding.requires-canonical-signal-reference");
        _ = try ref.read();
        for (self.entries.items, 0..) |e, i| if (e.value != null and e.operations == ops(T)) {
            if (e.external) |external| if (external.source == ref.owner) return .{ .owner = self, .token = self.token(i) };
        };
        if (self.next_generation == std.math.maxInt(u64)) return error.GenerationExhausted;
        const generation = self.next_generation;
        self.next_generation += 1;
        const capture = try self.allocator.create(Ref);
        errdefer self.allocator.destroy(capture);
        capture.* = ref;
        const Adapter = struct {
            fn read(raw: *anyopaque) Error!*anyopaque {
                return @constCast(try @as(*Ref, @ptrCast(@alignCast(raw))).read());
            }
            fn write(raw: *anyopaque, value: *const anyopaque) Error!void {
                const reference = @as(*Ref, @ptrCast(@alignCast(raw))).*;
                try reference.set(@as(*const T, @ptrCast(@alignCast(value))).*);
            }
            fn release(raw: *anyopaque, allocator: std.mem.Allocator) void {
                allocator.destroy(@as(*Ref, @ptrCast(@alignCast(raw))));
            }
        };
        const entry: Entry = .{ .id = .root, .slot = 0, .generation = generation, .value = capture, .operations = ops(T), .committed = true, .external = .{ .source = ref.owner, .read = Adapter.read, .write = Adapter.write, .release = Adapter.release } };
        for (self.entries.items, 0..) |*e, i| if (e.value == null) {
            e.* = entry;
            return .{ .owner = self, .token = self.token(i) };
        };
        try self.entries.append(self.allocator, entry);
        return .{ .owner = self, .token = self.token(self.entries.items.len - 1) };
    }
    /// Revocation never touches the Signal and cannot invalidate another source's bridges.
    pub fn revokeSignal(self: *Store, source: *anyopaque) void {
        for (self.entries.items) |*e| if (e.external) |external| {
            if (external.source == source) if (e.value) |value| {
                external.release(value, self.allocator);
                e.value = null;
            };
        };
    }

    /// Begin state discovery after executor validation, rejecting an already active transaction.
    /// Clear seen flags and pair this transaction with finish(accept).
    pub fn begin(self: *Store) Error!void {
        try self.executor.check();
        if (self.staging) return error.InvalidTransaction;
        self.staging = true;
        for (self.entries.items) |*e| e.seen = false;
    }
    /// Restart discovery without publishing or discarding state from the first focus pass.
    pub fn nextPass(self: *Store) Error!void {
        try self.executor.check();
        if (!self.staging or self.editing) return error.InvalidTransaction;
        for (self.entries.items) |*e| e.seen = false;
    }

    /// Resolve identity/slot state, creating a candidate entry only when needed.
    pub fn resolve(self: *Store, id: NodeID, slot: u32, operations: *const ValueOps, initial: *const anyopaque) Error!BindingToken {
        try self.executor.check();
        if (!self.staging or self.editing) return error.Reentrant;
        self.editing = true;
        defer self.editing = false;
        var latest: ?usize = null;
        for (self.entries.items, 0..) |e, i| {
            if (e.external == null and e.value != null and e.id.raw == id.raw and e.slot == slot and (latest == null or e.generation > self.entries.items[latest.?].generation)) latest = i;
        }
        if (latest) |i| {
            const e = &self.entries.items[i];
            if (e.operations == operations) {
                e.seen = true;
                return self.token(i);
            }
        }
        if (self.next_generation == std.math.maxInt(u64)) return error.GenerationExhausted;
        const generation = self.next_generation;
        self.next_generation += 1; // Aborted/failed generations are never issued again.
        const value = try operations.create(initial, self.allocator);
        errdefer operations.release(value, self.allocator);
        var vacant: ?usize = null;
        for (self.entries.items, 0..) |e, i| if (e.value == null) {
            vacant = i;
            break;
        };
        const index = vacant orelse self.entries.items.len;
        const entry: Entry = .{ .id = id, .slot = slot, .generation = generation, .value = value, .operations = operations };
        if (vacant) |i| self.entries.items[i] = entry else try self.entries.append(self.allocator, entry);
        // Only the last type at a key is retained in this candidate.
        for (self.entries.items, 0..) |*e, i| if (e.external == null and i != index and e.id.raw == id.raw and e.slot == slot) {
            e.seen = false;
        };
        return self.token(index);
    }
    fn token(self: *Store, index: usize) BindingToken {
        return .{ .owner = @intFromPtr(self), .index = index, .generation = self.entries.items[index].generation };
    }

    /// Validate a binding token and borrow its current typed payload.
    pub fn get(self: *Store, token_value: BindingToken, operations: *const ValueOps) Error!*anyopaque {
        try self.executor.check();
        if (token_value.owner != @intFromPtr(self) or token_value.index >= self.entries.items.len) return error.InvalidHandle;
        const e = &self.entries.items[@intCast(token_value.index)];
        if (e.generation != token_value.generation or e.operations != operations) return error.InvalidHandle;
        const value = e.value orelse return error.InvalidHandle;
        if (self.editing) return error.Reentrant;
        if (e.external) |external| return external.read(value);
        return value;
    }

    /// Validate the binding and replace its value; cloning/allocation failure before replacement preserves the old value.
    /// Signal-backed bindings also deliver observers, whose errors (including OutOfMemory) may follow accepted replacement.
    /// An observer error does not restore the old value or extend borrows of its replaced storage.
    pub fn set(self: *Store, t: BindingToken, operations: *const ValueOps, value: *const anyopaque) Error!void {
        const p = try self.get(t, operations);
        self.editing = true;
        defer self.editing = false;
        const entry = self.entries.items[@intCast(t.index)];
        if (entry.external) |external| {
            self.external_writing = true;
            defer self.external_writing = false;
            // Adapter copies its reference before callbacks. Cancellation may revoke/free the
            // bridge capture during notification; this write never consults that entry again.
            try external.write(entry.value.?, value);
        } else try operations.replace(p, value, self.allocator);
        self.dirty.* = true;
    }

    /// Finalize staging according to the accept flag and release abandoned storage.
    pub fn finish(self: *Store, accept: bool) void {
        self.editing = true;
        defer self.editing = false;
        for (self.entries.items) |*e| {
            if (e.external != null) continue;
            if (e.value) |p| {
                if ((accept and !e.seen) or (!accept and !e.committed)) {
                    e.operations.release(p, self.allocator);
                    e.value = null;
                } else if (accept) e.committed = true;
            }
        }
        self.staging = false;
    }

    /// Release owned storage exactly once; all borrows into this value become invalid.
    pub fn deinit(self: *Store) void {
        self.editing = true;
        for (self.entries.items) |e| if (e.value) |p| {
            if (e.external) |external| external.release(p, self.allocator) else e.operations.release(p, self.allocator);
        };
        self.entries.deinit(self.allocator);
    }
};
/// Borrowed owner handle. A read borrows the cell/payload only until its next successful write,
/// type replacement, removal, or owner destruction. Cached raw pointers are never generation checked.
/// Each later read/set validates this handle again; no handle or borrow may outlive its owner.
pub fn StateRef(comptime T: type) type {
    return struct {
        /// Payload type carried by this generic reference.
        pub const Value = T;

        /// Borrowed owner pointer; this value must never outlive that owner.
        owner: *Store,

        /// Owner-issued binding token; use the issuing owner and preserve its generation.
        token: BindingToken,

        /// Validate the handle and borrow the current value; the borrow expires at replacement or owner teardown.
        pub fn read(self: @This()) Error!*const T {
            return @ptrCast(@alignCast(try self.owner.get(self.token, ops(T))));
        }

        /// Forward checked replacement to the store; cloning/allocation failure before replacement preserves the old value.
        /// A signal-backed binding may return an observer error (including OutOfMemory) after accepting the new value;
        /// that error does not roll back replacement or preserve borrows of the old storage.
        pub fn set(self: @This(), value: T) Error!void {
            try self.owner.set(self.token, ops(T), &value);
        }

        /// Copy this reference as a typed binding without validation; read/set validate its token.
        pub fn binding(self: @This()) @This() {
            return self;
        }
    };
}
