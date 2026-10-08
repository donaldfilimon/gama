//! C signatures mirror include/GamaEmbed.h. Null context precedes validation.
const std = @import("std");
const shared = @import("context.zig");
const Context = shared.Context;
/// Return the supported C embedding ABI version, currently 1.
pub fn gama_embed_v1_abi_version() callconv(.c) i32 {
    return 1;
}
/// Allocate an owned context with the page allocator and dimensions clamped to at least one cell. Return null on failure; release with context_destroy.
pub fn gama_embed_v1_context_create(columns: i32, rows: i32) callconv(.c) ?*Context {
    return create(std.heap.page_allocator, columns, rows);
}
/// Destroy a non-null context and its output; null is a no-op. Executor/reentry failures leave the context alive and are not returned.
pub fn gama_embed_v1_context_destroy(context: ?*Context) callconv(.c) void {
    const ctx = context orelse return;
    ctx.destroy() catch {};
}
/// Forward dimensions to the context; return 0 on success or a negative status (-1 for null). Output borrows survive resize; frame admits drawing storage.
pub fn gama_embed_v1_resize(context: ?*Context, columns: i32, rows: i32) callconv(.c) i32 {
    const ctx = context orelse return -1;
    ctx.resize(columns, rows) catch |e| return shared.status(e);
    return 0;
}
/// Dispatch integer key/scalar/modifier input; return 0 on success, -1 for null, or a mapped decoding/dispatch error.
pub fn gama_embed_v1_key(context: ?*Context, code: i32, scalar: i32, shift: i32, control: i32) callconv(.c) i32 {
    const ctx = context orelse return -1;
    ctx.key(code, scalar, shift, control) catch |e| return shared.status(e);
    return 0;
}
/// Dispatch a press at signed cell coordinates when pressed is nonzero, otherwise release; return 0 or a negative status (-1 for null).
pub fn gama_embed_v1_pointer(context: ?*Context, column: i32, row: i32, pressed: i32) callconv(.c) i32 {
    const ctx = context orelse return -1;
    ctx.pointer(column, row, pressed) catch |e| return shared.status(e);
    return 0;
}
/// Return 1 for dirty, 0 for clean, or a negative error status (-1 for null).
pub fn gama_embed_v1_needs_frame(context: ?*Context) callconv(.c) i32 {
    const ctx = context orelse return -1;
    return @intFromBool(ctx.needsFrame() catch |e| return shared.status(e));
}
/// Return borrowed normalized GAMA bytes on publication, null when clean or failed.
/// If output_length is supplied, write byte length, 0 for clean, or a negative status.
/// The borrow expires on the next frame call or destruction; callers do not free it.
pub fn gama_embed_v1_frame(context: ?*Context, output_length: ?*i32) callconv(.c) ?[*]const u8 {
    const ctx = context orelse {
        if (output_length) |n| n.* = -1;
        return null;
    };
    const frame = ctx.frame(true) catch |e| {
        if (output_length) |n| n.* = shared.status(e);
        return null;
    };
    if (output_length) |n| n.* = if (frame) |bytes| @intCast(bytes.len) else 0;
    return if (frame) |bytes| bytes.ptr else null;
}

/// Allocator-injected implementation of null-on-create-failure; no extra C symbol.
pub fn create(a: std.mem.Allocator, columns: i32, rows: i32) ?*Context {
    return Context.create(a, columns, rows) catch null;
}
