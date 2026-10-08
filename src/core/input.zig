//! Portable semantic keys; adapters translate their native event forms here.
/// Normalized scalar shortcut with independent modifier flags.
pub const Shortcut = struct {
    /// Unicode scalar identifying the shortcut key.
    codepoint: u21,
    /// Control modifier is held.
    control: bool = false,
    /// Alt/option modifier is held.
    alt: bool = false,
    /// Shift modifier is held.
    shift: bool = false,
};
/// Semantic keyboard event; character bytes are borrowed for the dispatch call.
pub const Key = union(enum) {
    /// UTF-8 character input; the adapter must retain bytes through dispatch.
    character: []const u8,
    /// Numbered function key as decoded by the adapter.
    function: u8,
    /// Scalar key with explicit modifiers.
    shortcut: Shortcut,
    /// Enter/return activation key.
    enter,
    /// Space activation key.
    space,
    /// Advance focus to the next eligible control.
    tab,
    /// Move focus to the previous eligible control.
    back_tab,
    /// Move left within the focused control.
    left,
    /// Move right within the focused control.
    right,
    /// Move upward within the focused control.
    up,
    /// Move downward within the focused control.
    down,
    /// Move to the beginning of the focused content.
    home,
    /// Move to the end of the focused content.
    end,
    /// Move one page toward earlier content.
    page_up,
    /// Move one page toward later content.
    page_down,
    /// Delete before the cursor.
    backspace,
    /// Delete after the cursor.
    delete,
    /// Escape/cancel key.
    escape,
    /// Reserved request to leave the runtime input loop.
    quit,
};
/// Controller presses reuse keyboard dispatch; releases and unmapped buttons are ignored.
pub const GamepadButton = enum {
    /// Bottom face button; mapped by the host to activation.
    south,

    /// Right face button; mapped by the host to escape.
    east,

    /// Left face button; currently has no built-in semantic-key mapping.
    west,

    /// Top face button; currently has no built-in semantic-key mapping.
    north,

    /// Directional-pad up button.
    dpad_up,

    /// Directional-pad down button.
    dpad_down,

    /// Directional-pad left button.
    dpad_left,

    /// Directional-pad right button.
    dpad_right,

    /// Left shoulder button.
    left_shoulder,

    /// Right shoulder button.
    right_shoulder,

    /// Start/menu button.
    start,

    /// Select/back button.
    select,

    /// Translate mapped controller presses into shared semantic keyboard keys.
    pub fn semanticKey(self: GamepadButton) ?Key {
        return switch (self) {
            .south => .enter,
            .east => .escape,
            .dpad_up => .up,
            .dpad_down => .down,
            .dpad_left => .left,
            .dpad_right => .right,
            else => null,
        };
    }
};
