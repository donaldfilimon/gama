/// Heap-owned embedding app/signal/host/drawing context; destroy invalidates all borrowed output.
pub const Context = @import("context.zig").Context;
/// Caller-owned installed-context wrapper with expiring borrowed frame bytes.
pub const Pull = @import("pull.zig").Pull;
/// Pull-ABI key classification and scalar/modifier validation.
pub const input = @import("input.zig");
/// Reject an ABI byte length above the supported signed 32-bit maximum.
pub const admitLength = @import("context.zig").admitLength;
/// Map shared errors to the documented negative ABI status codes.
pub const status = @import("context.zig").status;
/// Native C-callable implementation helpers using the shared embedding Context.
pub const c = @import("c.zig");
