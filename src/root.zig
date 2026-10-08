//! Target-selecting Gama facade. Core stays freestanding; native ownership uses std.
const std = @import("std");

/// Signed cell geometry, saturating arithmetic and alignment value types.
pub const geometry = @import("core/geometry.zig");
/// Deterministic structural identity used for host-local state keys.
pub const NodeID = @import("core/identity.zig").NodeID;
/// Unicode validation, grapheme iteration and default lowercase helpers.
pub const unicode = @import("core/unicode.zig");
/// Grapheme-based editing, width measurement and owned line wrapping.
pub const text = @import("core/text.zig");

/// Maximum number of cells admitted by the shared frame/wire boundary.
pub const maximum_cell_count = @import("draw/cells.zig").maximum_cell_count;

/// Validate dimensions before allocating frame storage, including on 32-bit hosts.
pub fn checkedCellCount(width: u32, height: u32) error{
    /// Surface dimensions exceed the admitted nonnegative cell allocation bounds.
    FrameTooLarge,
}!usize {
    const count = @as(u64, width) * height;
    if (count > maximum_cell_count) return error.FrameTooLarge;
    return @intCast(count);
}

test "cell admission is bounded before allocation" {
    try std.testing.expectEqual(@as(usize, 0), try checkedCellCount(0, 0));
    try std.testing.expectEqual(@as(usize, 80 * 24), try checkedCellCount(80, 24));
    try std.testing.expectEqual(@as(usize, maximum_cell_count), try checkedCellCount(4096, 4096));
    try std.testing.expectError(error.FrameTooLarge, checkedCellCount(4097, 4096));
    try std.testing.expectError(error.FrameTooLarge, checkedCellCount(std.math.maxInt(u32), std.math.maxInt(u32)));
}

/// Copyable colors, decoration masks and border glyph selections.
pub const style = @import("core/style.zig");
/// Copyable RGB/default color value from core/style.zig.
pub const Color = style.Color;
/// Copyable text colors and decoration bitset from core/style.zig.
pub const TextStyle = style.TextStyle;
/// Compile-time #RGB or #RRGGBB color-literal parser from core/style.zig.
pub const rgb = style.rgb;
/// Portable render-tree value borrowing child/text storage through paint.
pub const Node = @import("core/node.zig").Node;
/// Frame allocation, action capture and host-registration interfaces.
pub const context = @import("core/context.zig");
/// Shared recoverable state/render/service error set.
pub const Error = context.Error;
/// Frame-building context borrowing allocation storage and host callbacks.
pub const BuildContext = context.BuildContext;
/// Frame arena owner with managed-capture cleanup; deinit releases all frame allocations.
pub const FrameStorage = context.FrameStorage;
/// Typed tuple, branch, iteration and identity-scope composition helpers.
pub const composition = @import("core/composition.zig");
/// Portable text/control components and layout/environment modifiers.
pub const authoring = @import("core/authoring.zig");
/// Scene descriptors and owned graphs requiring exactly one primary scene.
pub const scenes = @import("core/scenes.zig");

// Exact target selector is enforced by the source-policy verifier.
const SelectedGuard = if (@import("builtin").target.os.tag == .freestanding) @import("core/state.zig").SingleExecutor else @import("services/native_guard.zig").NativeGuard;
/// Select the hosted executor guard or freestanding single-executor host implementation.
pub fn Host(comptime App: type) type {
    return @import("core/host.zig").Implementation(App, SelectedGuard);
}
/// Select an observable owner with the target-appropriate executor guard.
pub fn Signal(comptime T: type) type {
    return @import("core/signal.zig").Implementation(T, SelectedGuard);
}
/// Typed generation-checked state reference; the issuing store must outlive it.
pub const StateRef = @import("core/state.zig").StateRef;
/// Typed observable reference borrowing a live stable signal owner.
pub const SignalRef = @import("core/signal.zig").SignalRef;
/// Managed UTF-8 value with explicit clone/deinit hooks for state and captures.
pub const String = @import("core/state.zig").String;
/// Copyable application completion code and optional borrowed message.
pub const Completion = @import("core/host.zig").Completion;
/// Validated 1...255 process exit byte; init returns null outside that range.
pub const FailureExitCode = @import("core/host.zig").FailureExitCode;
/// Application/scene lifecycle notification with optional scene identity.
pub const Lifecycle = @import("core/host.zig").Lifecycle;
/// Semantic host input and lifecycle event union; payload borrows last through dispatch.
pub const Event = @import("core/host.zig").Event;
/// Semantic keyboard event; character slices borrow adapter storage through dispatch.
pub const Key = @import("core/host.zig").Key;
/// Signal-issued owner/generation token used to cancel one observer.
pub const SubscriptionToken = @import("core/signal.zig").Token;
/// Physical gamepad positions and the supported semantic-key mapping.
pub const GamepadButton = @import("core/input.zig").GamepadButton;
/// Portable measurement and placement, with optional borrowed metric callbacks.
pub const layout = @import("core/layout.zig");
/// Return the borrowed one-step pump type specialized for this application.
pub fn HostPump(comptime App: type) type {
    return @import("core/pump.zig").Implementation(Host(App));
}
/// Cell planes, painting and owned output serializers/presenters.
pub const draw = @import("draw/root.zig");
/// Non-owning host link; the adapter owns only raster storage. Destroy it before Host.
pub fn DrawingPump(comptime App: type) type {
    return @import("draw/pump.zig").Implementation(Host(App), HostPump(App));
}

/// Cooperative plugin lifecycle, revocable handles and capability interfaces.
pub const plugins = @import("plugins/root.zig");
/// Plugin runtime using the selected native or caller-confined executor guard.
pub const PluginRuntime = plugins.Implementation(SelectedGuard);
/// Native std.Io service adapter; resolves to void on freestanding targets.
pub const HostedServices = if (@import("builtin").target.os.tag == .freestanding) void else @import("services/hosted.zig").HostedServices;

/// Hosted terminal/plain runtime namespace; resolves to void on freestanding targets.
pub const tui = if (@import("builtin").target.os.tag == .freestanding) void else @import("tui/root.zig");

/// ABI implementation and allocator-injected test seam; native C symbols use c_embed.zig.
pub const abi = @import("abi/root.zig");

/// Textual generic MLIR lowering; returned text is caller-owned.
pub const mlir = @import("mlir/root.zig");
