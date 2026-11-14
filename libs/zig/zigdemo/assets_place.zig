//! zigdemo assets: where a new blob goes in the arena, beside the blobs already in slots:
//! the lowest ALIGN-aligned offset whose [off, off + len) overlaps no occupied slot, or null.

pub const ALIGN = 16;

fn alignUp(x: u32) u32 {
    return (x + ALIGN - 1) & ~@as(u32, ALIGN - 1);
}

/// `slots` is a slice of structs with `id: ?u16`, `off: u32`, `len: u32` (assets.Slot).
/// The candidates are the arena's start and the aligned end of each occupied slot.
pub fn find(slots: anytype, len: u32, arena: u32) ?u32 {
    if (fits(slots, 0, len, arena)) return 0;
    var best: ?u32 = null;
    for (slots) |s| {
        if (s.id == null) continue;
        const at = alignUp(s.off + s.len);
        if (fits(slots, at, len, arena) and (best == null or at < best.?)) best = at;
    }
    return best;
}

fn fits(slots: anytype, at: u32, len: u32, arena: u32) bool {
    if (at > arena or len > arena - at) return false;
    for (slots) |s| {
        if (s.id == null) continue;
        if (at < s.off + s.len and s.off < at + len) return false;
    }
    return true;
}
