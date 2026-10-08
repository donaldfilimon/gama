//! Native C export root. The shared implementation has no export side effects.
const c = @import("abi/c.zig");
comptime {
    for (.{ "abi_version", "context_create", "context_destroy", "resize", "key", "pointer", "needs_frame", "frame" }) |suffix| {
        const name = "gama_embed_v1_" ++ suffix;
        @export(&@field(c, name), .{ .name = name });
    }
}
