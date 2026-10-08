//! Freestanding link probe, not board startup or firmware. The caller supplies
//! an exclusive 64 KiB arena; every host, state, raster and output allocation
//! comes from it. No vectors, MMIO, OS or allocator imports.
const std = @import("std");
const builtin = @import("builtin");
comptime {
    if (builtin.target.os.tag != .freestanding or builtin.target.cpu.arch != .thumb or
        builtin.target.abi != .eabi or !std.mem.eql(u8, builtin.target.cpu.model.name, "cortex_m4"))
        @compileError("embedded probe requires Cortex-M4 thumb-freestanding-eabi");
}
/// Callable Thumb entry. Caller supplies the arena; board startup is external.
export fn gama_embedded_entry(memory: *[65536]u8) callconv(.c) i32 {
    return @import("embedded_app.zig").run(memory);
}
