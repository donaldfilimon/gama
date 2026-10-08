//! Exclusive POSIX terminal ownership using only installed std OS APIs.
//! Each acquisition consumes an immutable rescue slot with a distinct handler.
//! Slots are never recycled: delayed callbacks cannot alias a later lease. After
//! 256 acquisitions per process acquire fails before touching terminal state.
//! Descriptor references are gated; normal teardown alone waits for readers.
//! SIGKILL, external exit and callers changing managed dispositions while leased
//! are outside this ownership contract. No signal callback performs output.
const std = @import("std");
const builtin = @import("builtin");
const p = std.posix;
const sys = p.system;
const Error = @import("../core/state.zig").Error;
const Guard = @import("../services/native_guard.zig").NativeGuard;
const geo = @import("../core/geometry.zig");
const Decoder = @import("decoder.zig").Decoder;
const Event = @import("../core/host.zig").Event;
const Atomic = std.atomic.Value;
/// Process-lifetime maximum rescue epochs; slots are never reused after acquisition attempts.
pub const acquisition_limit = 256;
const disabled: u32 = 1 << 31;
const signals = [_]p.SIG{ .TERM, .HUP, .INT, .QUIT, .WINCH };
const Phase = enum(u8) {
    /// Signal actions are being installed for this rescue epoch.
    installing,
    /// Owner-maintained liveness flag; callers must use validation methods.
    active,
    /// A signal handler owns emergency restoration for this epoch.
    rescuing,
    /// Normal close owns terminal/disposition restoration for this epoch.
    closing,
    /// Restoration completed; this epoch remains a permanent tombstone.
    restored,
};
const Slot = struct {
    /// Atomic reader count with disabled sentinel, preventing rescue-slot reuse races.
    readers: Atomic(u32) = .init(disabled),

    /// Atomic state coordinating acquisition, rescue and close.
    phase: Atomic(Phase) = .init(.installing),

    /// Pending rescue signal recorded for checked terminal operations.
    pending: Atomic(u32) = .init(0),

    /// Resize notification pending consumption by the terminal reader.
    resized: Atomic(bool) = .init(false),

    /// Borrowed input descriptor whose termios is restored by this epoch.
    fd: p.fd_t = -1,

    /// Saved input termios captured before raw-mode mutation.
    saved: p.termios = undefined,

    /// Exact prior actions restored in reverse installation order.
    old: [signals.len]p.Sigaction = undefined,

    /// Number of signal actions successfully installed in this epoch.
    installed: usize = 0,
};
var slots: [acquisition_limit]Slot = @splat(.{});
var used: usize = 0; // Protected by exclusive lease gate.
var owned: Atomic(bool) = .init(false);
fn callback(comptime index: usize) p.Sigaction.handler_fn {
    return struct {
        fn handle(sig: p.SIG) callconv(.c) void {
            const saved_errno = if (builtin.link_libc) std.c._errno().* else 0;
            rescue(&slots[index], sig);
            if (builtin.link_libc) std.c._errno().* = saved_errno;
        }
    }.handle;
}
const callbacks = blk: {
    var items: [acquisition_limit]p.Sigaction.handler_fn = undefined;
    for (&items, 0..) |*item, i| item.* = callback(i);
    break :blk items;
};
fn mask() p.sigset_t {
    var result = p.sigemptyset();
    for (signals) |sig| p.sigaddset(&result, sig);
    return result;
}
fn bits(sig: p.SIG) u32 {
    for (signals, 0..) |value, i| if (value == sig) return @as(u32, 1) << @intCast(i);
    return 0;
}
fn fatal() noreturn {
    if (builtin.link_libc) std.c._exit(127) else std.os.linux.exit_group(127);
}
/// Raw std calls avoid the diagnostic paths of higher-level wrappers.
fn restoreChecked(slot: *Slot) Error!void {
    var failed = p.errno(sys.tcsetattr(slot.fd, .NOW, &slot.saved)) != .SUCCESS;
    for (signals[0..slot.installed], slot.old[0..slot.installed]) |sig, old| if (p.errno(sys.sigaction(sig, &old, null)) != .SUCCESS) {
        failed = true;
    };
    if (failed) return error.IOFailure;
}
fn restore(slot: *Slot) void {
    restoreChecked(slot) catch fatal();
}
fn redeliver(pending: u32) void {
    for (signals, 0..) |sig, i| if (pending & (@as(u32, 1) << @intCast(i)) != 0) {
        // Keep the interrupted thread's mask intact. For a real signal callback
        // this queues delivery until sigreturn, avoiding nested libc trampolines
        // and preserving displaced SA_RESETHAND/SA_NODEFER semantics.
        const rc = if (builtin.link_libc) sys.raise(sig) else std.os.linux.tkill(std.os.linux.gettid(), sig);
        if (p.errno(rc) != .SUCCESS) fatal();
    };
}
fn rescue(slot: *Slot, sig: p.SIG) void {
    const readers = slot.readers.fetchAdd(1, .seq_cst);
    if (readers & disabled != 0) {
        _ = slot.readers.fetchSub(1, .seq_cst);
        // The old action has already been displaced. Forward through the CURRENT
        // action, which may belong to a newer lease. Never reinstall stale actions.
        redeliver(bits(sig));
        return;
    }
    if (sig == .WINCH and slot.phase.load(.seq_cst) != .restored) {
        slot.resized.store(true, .seq_cst);
        _ = slot.readers.fetchSub(1, .seq_cst);
        return;
    }
    _ = slot.pending.fetchOr(bits(sig), .seq_cst);
    if (slot.phase.cmpxchgStrong(.active, .rescuing, .seq_cst, .seq_cst) == null) {
        restore(slot);
        slot.phase.store(.restored, .seq_cst);
    }
    const pending = if (slot.phase.load(.seq_cst) == .restored) slot.pending.swap(0, .seq_cst) else 0;
    // Drop all record/descriptor access before displaced user handlers can run.
    // A returning user handler can never make teardown wait for this reader.
    _ = slot.readers.fetchSub(1, .seq_cst);
    redeliver(pending);
}
fn closeFd(fd: p.fd_t) void {
    _ = sys.close(fd);
}
fn dup(fd: p.fd_t) Error!p.fd_t {
    const value = sys.fcntl(fd, p.F.DUPFD_CLOEXEC, @as(usize, 0));
    if (p.errno(value) != .SUCCESS) return error.IOFailure;
    return @intCast(value);
}
fn getFlags(fd: p.fd_t) Error!usize {
    const value = sys.fcntl(fd, p.F.GETFL, @as(usize, 0));
    if (p.errno(value) != .SUCCESS) return error.IOFailure;
    return @intCast(value);
}
fn setFlags(fd: p.fd_t, value: usize) Error!void {
    if (p.errno(sys.fcntl(fd, p.F.SETFL, value)) != .SUCCESS) return error.IOFailure;
}
const nonblock: usize = @intCast(@as(u32, @bitCast(p.O{ .NONBLOCK = true })));
const hidden_action_flags: u32 = if (builtin.os.tag == .macos) p.SA.RESETHAND else 0;
fn sameObservableAction(a: p.Sigaction, b: p.Sigaction) bool {
    return a.handler.handler == b.handler.handler and std.meta.eql(a.mask, b.mask) and
        a.flags & ~hidden_action_flags == b.flags & ~hidden_action_flags;
}
/// Query stdout terminal capability through std; no descriptor ownership is acquired.
pub fn stdoutIsTerminal() bool {
    var term: p.termios = undefined;
    return p.errno(sys.tcgetattr(1, &term)) == .SUCCESS;
}
/// Exclusive terminal owner with process-lifetime rescue metadata; close exactly once.
pub const Terminal = struct {
    /// Deterministic acquisition interleavings; absent from non-test builds.
    pub const TestHooks = if (builtin.is_test) struct {
        /// Test hook before replacing action index; false injects installation failure.
        pub var before_replace: ?*const fn (usize) bool = null;

        /// Test hook after replacing action index, used to exercise acquisition races.
        pub var after_replace: ?*const fn (usize) void = null;
    } else struct {};

    /// Maximum acquisitions admitted over the process lifetime, including consumed failed epochs.
    pub const max_acquisitions = acquisition_limit;

    /// Static bytes reserved for never-reused rescue slots; excludes dynamic stack usage.
    pub const rescue_storage_bytes = @sizeOf(@TypeOf(slots));
    /// Exact action originally installed by the caller. On Darwin sigaction hides
    /// SA_RESETHAND; custom actions need this record, with all observable fields
    /// checked against the live disposition. The hidden bit is the caller's truth.
    /// Records are copied during acquire; no caller record storage is retained.
    pub const Disposition = struct {
        /// Handled signal whose exact installed action is supplied by the caller.
        signal: p.SIG,
        /// Caller-owned exact action record, including flags omitted by Darwin readback.
        action: p.Sigaction,
    };

    /// Executor/reentrancy guard; callers must use checked methods instead of changing it.
    guard: Guard,

    /// State slot within a node identity; keep stable across renders of the same component.
    slot: *Slot,

    /// Borrowed output descriptor retained by the caller until close completes.
    output: p.fd_t,

    /// Saved OS or format flags; restoration/decoding owns their validation.
    flags: usize,

    /// Borrowed standard-library I/O backend; it must outlive all operations.
    io: std.Io,

    /// Owner-maintained closed state; repeated close is idempotent where documented.
    closed: bool = false,

    /// Owner-local decoder retaining partial UTF-8 and escape input between reads.
    decoder: Decoder = .{},
    /// Caller exclusively owns the underlying terminal and open-file flags until close.
    /// Move returned value into stable storage; use borrowed pointers, never owning copies.
    pub fn acquire(io: std.Io, input: p.fd_t, output: p.fd_t) Error!Terminal {
        return acquireWithActions(io, input, output, &.{});
    }

    /// Acquire an exclusive terminal lease using exact caller-installed custom-action records; reject unverifiable Darwin handlers before mutation.
    pub fn acquireWithActions(io: std.Io, input: p.fd_t, output: p.fd_t, dispositions: []const Disposition) Error!Terminal {
        if (owned.cmpxchgStrong(false, true, .seq_cst, .seq_cst) != null) return error.TerminalBusy;
        errdefer owned.store(false, .seq_cst);
        if (used == acquisition_limit) return error.GenerationExhausted;
        const fd = try dup(input);
        errdefer closeFd(fd);
        const out = try dup(output);
        errdefer closeFd(out);
        var saved: p.termios = undefined;
        if (p.errno(sys.tcgetattr(fd, &saved)) != .SUCCESS) return error.IOFailure;
        const flags = try getFlags(out);
        const index = used;
        const slot = &slots[index];
        slot.fd = fd;
        slot.saved = saved;
        for (signals, 0..) |sig, i| if (p.errno(sys.sigaction(sig, null, &slot.old[i])) != .SUCCESS) return error.IOFailure;
        // Preflight every record before altering termios, flags, or dispositions.
        var seen: u32 = 0;
        for (dispositions) |record| {
            const bit = bits(record.signal);
            if (bit == 0 or seen & bit != 0) return error.InvalidDisposition;
            seen |= bit;
            for (signals, 0..) |sig, i| if (sig == record.signal) {
                const current = slot.old[i];
                if (!sameObservableAction(current, record.action)) return error.InvalidDisposition;
                slot.old[i] = record.action;
            };
        }
        if (builtin.os.tag == .macos) for (signals, slot.old) |sig, old| {
            if (old.handler.handler != p.SIG.DFL and old.handler.handler != p.SIG.IGN and seen & bits(sig) == 0) return error.UnverifiableDisposition;
        };
        used += 1;
        // While installing, callbacks only enqueue/latch events. They cannot read
        // restore actions until the active phase publishes the resolved records.
        slot.readers.store(0, .seq_cst);
        var previous_mask: p.sigset_t = undefined;
        const managed = mask();
        p.sigprocmask(p.SIG.BLOCK, &managed, &previous_mask);
        var installed: usize = 0;
        var installation_error: Error = error.IOFailure;
        const preflight = slot.old;
        var raw = saved;
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;
        raw.oflag.OPOST = false;
        raw.cflag.CSIZE = .CS8;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;
        raw.cc[@backingInt(p.V.MIN)] = 0;
        raw.cc[@backingInt(p.V.TIME)] = 0;
        const action: p.Sigaction = .{ .handler = .{ .handler = callbacks[index] }, .mask = managed, .flags = 0 };
        for (signals) |sig| {
            if (builtin.is_test) if (TestHooks.before_replace) |hook| {
                if (!hook(installed)) break;
            };
            var displaced: p.Sigaction = undefined;
            if (p.errno(sys.sigaction(sig, &action, &displaced)) != .SUCCESS) break;
            if (builtin.is_test) if (TestHooks.after_replace) |hook| hook(installed);
            // Atomic replacement is authoritative: a one-shot may have been
            // consumed on another thread since preflight. Never resurrect it.
            slot.old[installed] = displaced;
            installed += 1;
            slot.installed = installed;
            if (displaced.handler.handler != p.SIG.DFL and displaced.handler.handler != p.SIG.IGN) {
                if (!sameObservableAction(displaced, preflight[installed - 1])) {
                    // Independent disposition mutation violates exclusive ownership.
                    // Roll back only actual replacements, using their returned state.
                    installation_error = error.InvalidDisposition;
                    break;
                }
                slot.old[installed - 1].flags |= preflight[installed - 1].flags & hidden_action_flags;
            }
        }
        const ok = installation_error != error.InvalidDisposition and installed == signals.len and p.errno(sys.tcsetattr(fd, .NOW, &raw)) == .SUCCESS;
        setFlags(out, flags | nonblock) catch {};
        if (!ok or (getFlags(out) catch 0) & nonblock == 0) {
            restoreChecked(slot) catch {};
            slot.phase.store(.restored, .seq_cst);
            _ = slot.readers.fetchOr(disabled, .seq_cst);
            while (slot.readers.load(.seq_cst) != disabled) std.atomic.spinLoopHint();
            setFlags(out, flags) catch {};
            p.sigprocmask(p.SIG.SETMASK, &previous_mask, null);
            redeliver(slot.pending.swap(0, .seq_cst));
            return installation_error;
        }
        slot.phase.store(.active, .seq_cst);
        p.sigprocmask(p.SIG.SETMASK, &previous_mask, null);
        const pending = slot.pending.swap(0, .seq_cst);
        redeliver(pending);
        return .{ .guard = .init(), .slot = slot, .output = out, .flags = flags, .io = io };
    }

    /// Restore terminal state and saved flags, then close the owned duplicate descriptors.
    /// Structured callers must invoke close; the caller's original descriptors are not closed.
    pub fn close(self: *Terminal) Error!void {
        try self.guard.check();
        if (self.closed) return;
        if (self.slot.readers.load(.seq_cst) & disabled != 0) return error.InvalidHandle;
        // A handler owns rescue OR normal teardown does; no overwritten one-shot
        // dispositions after a displaced handler returns (SA_RESETHAND stays reset).
        var restore_result: Error!void = {};
        if (self.slot.phase.cmpxchgStrong(.active, .closing, .seq_cst, .seq_cst) == null) {
            restore_result = restoreChecked(self.slot);
            self.slot.phase.store(.restored, .seq_cst);
        }
        while (self.slot.phase.load(.seq_cst) == .rescuing) std.atomic.spinLoopHint();
        _ = self.slot.readers.fetchOr(disabled, .seq_cst);
        while (self.slot.readers.load(.seq_cst) != disabled) std.atomic.spinLoopHint();
        // Settings are restored BEFORE optional nonblocking presentation cleanup.
        const cleanup = "\x1b[0m\x1b[?25h\n";
        _ = sys.write(self.output, cleanup.ptr, cleanup.len);
        const flag_result = setFlags(self.output, self.flags);
        closeFd(self.output);
        closeFd(self.slot.fd);
        self.closed = true;
        owned.store(false, .seq_cst);
        redeliver(self.slot.pending.swap(0, .seq_cst));
        try restore_result;
        try flag_result;
    }

    /// Query terminal cell dimensions after executor/liveness checks; failed or zero ioctl dimensions yield 80x24.
    pub fn size(self: *Terminal) Error!geo.Size {
        try self.guard.check();
        if (self.closed or self.slot.readers.load(.seq_cst) & disabled != 0) return error.InvalidHandle;
        var value: p.winsize = undefined;
        const rc = if (builtin.os.tag == .linux) sys.ioctl(self.output, p.T.IOCGWINSZ, @intFromPtr(&value)) else sys.ioctl(self.output, p.T.IOCGWINSZ, &value);
        if (p.errno(rc) != .SUCCESS or value.col == 0 or value.row == 0) return .{ .width = 80, .height = 24 };
        return .{ .width = value.col, .height = value.row };
    }
    fn now(self: *Terminal) u64 {
        return @intCast(@max(0, std.Io.Clock.awake.now(self.io).toMilliseconds()));
    }

    /// Write all bytes, polling boundedly on would-block; interruption/stall may follow partial output.
    pub fn write(self: *Terminal, bytes: []const u8) Error!void {
        try self.guard.check();
        if (self.closed) return error.InvalidHandle;
        const start = self.now();
        var offset: usize = 0;
        while (offset < bytes.len) {
            if (self.slot.phase.load(.seq_cst) != .active) return error.TerminalInterrupted;
            const rc = sys.write(self.output, bytes.ptr + offset, bytes.len - offset);
            switch (p.errno(rc)) {
                .SUCCESS => {
                    if (rc == 0) return error.IOFailure;
                    offset += @intCast(rc);
                },
                .INTR => {},
                .AGAIN => {
                    if (self.now() -| start >= 1000) return error.OutputStalled;
                    var fds = [_]p.pollfd{.{ .fd = self.output, .events = p.POLL.OUT, .revents = 0 }};
                    _ = sys.poll(&fds, 1, 25);
                },
                else => return error.IOFailure,
            }
        }
    }

    /// Poll input for timeout_ms and return one decoded event; slices borrow decoder storage.
    pub fn next(self: *Terminal, timeout_ms: i32) Error!?Event {
        try self.guard.check();
        if (self.closed) return error.InvalidHandle;
        if (self.slot.phase.load(.seq_cst) != .active) return error.TerminalInterrupted;
        if (self.slot.resized.swap(false, .seq_cst)) return .{ .resize = try self.size() };
        if (self.decoder.next(self.now())) |event| return event;
        var fds = [_]p.pollfd{.{ .fd = self.slot.fd, .events = p.POLL.IN, .revents = 0 }};
        const rc = sys.poll(&fds, 1, @min(@max(0, timeout_ms), if (self.decoder.len == 0) @as(i32, 250) else 25));
        if (p.errno(rc) == .INTR) return null;
        if (p.errno(rc) != .SUCCESS) return error.IOFailure;
        if (self.slot.resized.swap(false, .seq_cst)) return .{ .resize = try self.size() };
        if (rc == 0) return self.decoder.next(self.now());
        if (fds[0].revents & p.POLL.IN != 0) {
            var bytes: [64]u8 = undefined;
            const n = sys.read(self.slot.fd, &bytes, @min(bytes.len, Decoder.capacity - self.decoder.len));
            if (p.errno(n) == .INTR or p.errno(n) == .AGAIN) return null;
            if (p.errno(n) != .SUCCESS) return error.IOFailure;
            if (n == 0) return error.EndOfInput;
            self.decoder.feed(bytes[0..@intCast(n)]) catch return error.LimitExceeded;
            return self.decoder.next(self.now());
        }
        if (fds[0].revents & p.POLL.HUP != 0) return error.EndOfInput;
        return error.IOFailure;
    }
};
