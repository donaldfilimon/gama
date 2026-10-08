//! Import-free, single-executor pull ABI. std.heap.wasm_allocator owns all storage.
const std = @import("std");
const Pull = @import("pull.zig").Pull;
var installed: Pull = .{};
/// Versioned WASM pull init entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_init(columns: i32, rows: i32) i32 {
    return installed.init(std.heap.wasm_allocator, columns, rows);
}
/// Versioned WASM pull shutdown entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_shutdown() void {
    installed.shutdown();
}
/// Versioned WASM pull key entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_key(code: i32, scalar: i32, shift: i32, control: i32) i32 {
    return installed.key(code, scalar, shift, control);
}
/// Versioned WASM pull pointer entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_pointer(column: i32, row: i32, pressed: i32) i32 {
    return installed.pointer(column, row, pressed);
}
/// Versioned WASM pull resize entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_resize(columns: i32, rows: i32) i32 {
    return installed.resize(columns, rows);
}
/// Versioned WASM pull needs frame entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_needs_frame() i32 {
    return installed.needsFrame();
}
/// Versioned WASM pull frame entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_frame() i32 {
    return installed.frame();
}
/// Versioned WASM pull frame ptr entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_frame_ptr() u32 {
    return if (installed.bytes.len == 0) 0 else @intCast(@intFromPtr(installed.bytes.ptr));
}
/// Versioned WASM pull frame len entrypoint; status and borrowed-buffer lifetime follow the maintained backend/header contract.
pub export fn gama_wasm_v1_frame_len() u32 {
    return @intCast(installed.bytes.len);
}
