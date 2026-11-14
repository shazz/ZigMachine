// --------------------------------------------------------------------------
// The harnesses' mutants (deskSetEngine's bits 8.., eng/engine.zig): each one
// puts back a bug a harness must catch, in the old path and the engine alike.
// The engine's own (repaint all, unclipped, ...) are in engine.zig; these are the
// desktop's, read through Desktop.breaks (apps/gem_desk_bugs_check.mjs --break).
// --------------------------------------------------------------------------
pub const REFLOW: u32 = 1 << 13; // the icon grid frozen at the width the window opened with
pub const PAGE: u32 = 1 << 14; // a click in a scroll track does nothing (no page)
pub const HASH_POS: u32 = 1 << 15; // the engine's damage blind to a clipped object that moved
pub const ROW_SCROLL: u32 = 1 << 16; // text view: folder rows do not scroll sideways
pub const ROW_GHOST: u32 = 1 << 17; // text view: a dragged file shows the icon ghost
pub const CLICK: u32 = 1 << 18; // a click is a drag (no slop) and drops on the icons under a window
pub const SEL_DRIVE: u32 = 1 << 20; // the selection lights its indices in EVERY drive's windows (by index only)
pub const MIN_ROW: u32 = 1 << 21; // a directory window's minimum holds one icon CELL, not the row with its names
pub const NAME_COL: u32 = 1 << 22; // a window's icon column is the desktop's 72 px cell: 12-character names run together
pub const ROW_CUT: u32 = 1 << 23; // a window's icon row is drawn even when its names fall below the window (cut off)
