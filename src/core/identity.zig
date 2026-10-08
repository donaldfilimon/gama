//! Exact baseline wrapping identity mixing; explicit identities replace inherited ones.
/// Deterministic structural identity; derived children and scopes form host-local state keys.
pub const NodeID = struct {
    /// Hash bits used for equality; collisions represent the same logical identity.
    raw: u64,

    /// FNV offset-basis identity from which root child paths derive.
    pub const root: NodeID = .{ .raw = 0xCBF29CE484222325 };

    /// Derive a deterministic child identity/context from its positional index.
    pub fn child(self: NodeID, index: i64) NodeID {
        const h = (self.raw ^ 0x9E3779B97F4A7C15) *% 0x100000001B3;
        return .{ .raw = h ^ (@as(u64, @bitCast(index)) +% 0x517CC1B727220A95) };
    }
};
