/// Owned cell planes and borrowed cell/run values used by painting and presenters.
pub const cells = @import("cells.zig");
/// Cell value reexport: borrowed glyph, style and wide-cell continuation flag.
pub const Cell = cells.Cell;
/// CellBuffer reexport: owned front/back planes with transactional promotion.
pub const CellBuffer = cells.CellBuffer;
/// Paint a laid-out tree into the back plane, preserving the front publication.
pub const paint = @import("painter.zig").paint;
/// Owned ordered fill/text commands; deinit releases copied text and command storage.
pub const DrawList = @import("list.zig").DrawList;
/// Borrowed fill/text command value used within DrawList.
pub const DrawCommand = @import("list.zig").Command;
/// ANSI diff presenter; prepare leaves planes unchanged, present promotes on success.
pub const AnsiPresenter = @import("presenters.zig").AnsiPresenter;
/// Plain row presenter with owned lines and success-only plane promotion.
pub const StreamPresenter = @import("presenters.zig").StreamPresenter;
/// Non-mutating escaped HTML serializer returning allocator-owned bytes.
pub const HTMLSerializer = @import("html.zig").HTMLSerializer;
/// Non-mutating back-plane copier returning an owned DrawList, not wire bytes.
pub const DrawListSerializer = @import("list.zig").DrawListSerializer;
/// Select binary draw-list, HTML, ANSI diff or plain-text output.
pub const Format = @import("pump.zig").Format;
