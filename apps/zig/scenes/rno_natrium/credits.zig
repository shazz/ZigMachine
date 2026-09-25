// --------------------------------------------------------------------------
// Part 4, the credits over the reclining girl ($FC0..$1200). The strip ILBM is
// the picture's own lines 182..197 three times, each with one credit burnt in;
// the sequencer overwrites those 16 lines with row k right after a VBL
// ($B41A / $B616 / $B812, three identical unrolled blocks), then closes on a
// white blinds wipe ($BA0E).
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");
const Screen = st.Screen;

pub const STRIP_LINE = 182; // $71C0 / 160
pub const STRIP_ROWS = 16;
/// Counter values at which rows 0 ("Code.Gfx britelite"), 1 ("Gfx bracket")
/// and 2 ("Music 505") go up.
pub const AT = [3]u32{ 0xFC0, 0x1080, 0x1140 };
pub const WIPE_AT: u32 = 0x1190;

/// Strip row k (0..2) over screen lines 182..197, all four planes.
pub fn stripRow(s: *Screen, k: usize) void {
    st.fromIlbm(s, A.strip[k * 0xA00 ..][0 .. STRIP_ROWS * st.LINE], STRIP_LINE, STRIP_ROWS);
}

/// Wipe step n: lines 2n and 199-2n all $FF (colour 15 = $777).
pub fn whiteWipe(s: *Screen, n: u16) void {
    for ([_]usize{ 2 * @as(usize, n), 199 - 2 * @as(usize, n) }) |y| {
        @memset(s[y * st.LINE ..][0..st.LINE], 0xFF);
    }
}
