// --------------------------------------------------------------------------
// F5's giant scroller ($1407A): letters of 16x34 cells, 7 cells tall, drawn
// one 16-pixel column at a time just past the right edge of the picture.
// Two screen pairs scroll by moving the screen's START ($14D2E += 8 bytes
// every other frame: sync-scrolling, the hardware moves) and the frames in
// between show the other pair, whose columns are drawn from preshifted cells
// ($1E0EA, or two cells merged, $1E9F2): 8 pixels a frame. At $E4 bytes the
// pairs swap ($14904) and the start goes back to 0. The column's 15
// pointers go to $14926; the fullscreen routine copies them ($176A0..) into
// both screens (column()), and $138C2 clears the column the screen left.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

pub const SCROLL: u32 = 0x14D2E;
pub const SCREEN: u32 = 0x18076; // this frame's screen, $1807A the other
pub const OTHER: u32 = 0x14916; // its shifted twin, $1491A the other
const PHASE: u32 = 0x1491E; // even / odd frame
const PAIR: u32 = 0x14904;
const PAIRS: u32 = 0x14906;
const HALF: u32 = 0x14D32; // 0 / 2: which half of a 32-pixel cell column
const COL: u32 = 0x14924; // column (in words) inside the letter
const WIDTH: u32 = 0x14920; // the letter's width (in words); $14922 the last one's
const TEXT: u32 = 0x1811E;
const CUR: u32 = 0x14543;
const PREV: u32 = 0x14542;
const GLYPHS: u32 = 0x1A2E2;
const PTRS: u32 = 0x14926;
const DST: u32 = 0x14D26; // where this frame's column goes, $14D2A the twin's
const CELLS = [7]u32{ 0, 0x0C, 0x18, 0x24, 0x30, 0x3C, 0x48 };

pub fn advance(r: *const st.Ram) void {
    const odd = r.w(PHASE) ^ 1;
    r.sw(PHASE, odd);
    if (odd != 0) {
        if (r.w(HALF) == 0) merged(r) else shifted(r);
    } else {
        step(r);
        plain(r);
    }
    r.sl(DST, r.l(SCREEN) + r.l(SCROLL) + 0x47C);
    r.sl(DST + 4, r.l(OTHER) + r.l(SCROLL) + 0x47C);
}

/// $14086: 8 bytes on; the pair swap at $E4; every other time a column on.
fn step(r: *const st.Ram) void {
    r.sl(SCROLL, r.l(SCROLL) + 8);
    if (r.l(SCROLL) >= 0xE4) {
        const pair = r.w(PAIR) ^ 8;
        r.sw(PAIR, pair);
        r.cp(SCREEN, PAIRS + pair, 8);
        r.sl(OTHER, r.l(PAIRS + (pair ^ 8)));
        r.sl(OTHER + 4, r.l(PAIRS + (pair ^ 8) + 4));
        r.sl(SCROLL, 0);
    }
    const half = r.w(HALF) ^ 2;
    r.sw(HALF, half);
    if (half != 0) return;
    r.sw(COL, r.w(COL) + 2);
    if (r.w(COL) < r.w(WIDTH)) return;
    r.sw(COL, 0);
    var p = r.l(TEXT) + 1;
    if (p >= 0x18DBA) p = 0x18DAF;
    r.sl(TEXT, p);
    r.sb(PREV, r.b(p - 1));
    r.sb(0x14923, r.b(0x1A7C6 + @as(u32, r.b(p - 1) -% 0x20)));
    r.sb(CUR, r.b(p));
    r.sb(0x14921, r.b(0x1A7C6 + @as(u32, r.b(p) -% 0x20)));
}

fn glyph(r: *const st.Ram, c: u32, col: u32) u32 {
    return r.l(GLYPHS + 4 * ((c -% 0x20) & 0xFF)) +% col;
}

fn put(r: *const st.Ram, k: usize, cell: u32) void {
    r.sl(PTRS + 8 * @as(u32, @intCast(k)), cell);
    r.sl(PTRS + 8 * @as(u32, @intCast(k)) + 4, cell + 0x44);
}

/// $1415C: the column from the plain cells, the half $14D32 picks.
fn plain(r: *const st.Ram) void {
    const a0 = glyph(r, r.b(CUR), r.w(COL));
    const a2 = 0x1B85A + @as(u32, r.w(0x1DE6A + @as(u32, r.w(HALF))));
    for (CELLS, 0..) |o, k| put(r, k, st.add(a2, st.sx(r.w(0x14270 + 2 * @as(u32, r.w(a0 + o))))));
}

/// $1429E: the cells preshifted by 8 pixels.
fn shifted(r: *const st.Ram) void {
    const a0 = glyph(r, r.b(CUR), r.w(COL));
    for (CELLS, 0..) |o, k| put(r, k, st.add(0x1E0EA, st.sx(r.w(0x1DE6A + 2 * @as(u32, r.w(a0 + o))))));
}

/// $143A2: two adjacent cell columns merged (the 8 pixels across them).
fn merged(r: *const st.Ram) void {
    const a0 = glyph(r, r.b(CUR), r.w(COL));
    const a6 = if (r.w(COL) != 0) a0 - 2 else glyph(r, r.b(PREV), r.w(0x14922)) - 2;
    for (CELLS, 0..) |o, k| {
        const d1 = st.sx(r.w(0x1DE6A + 2 * @as(u32, r.w(a0 + o))));
        const d2 = r.l(0x1E06A + 4 * @as(u32, r.w(a6 + o)));
        put(r, k, st.add(0x1E9F2, d1) +% d2);
    }
}

/// The fullscreen routine's column copy ($176A0..$1787E): 15 pointers, 17
/// lines each, into this screen and (8 pixels left, $A2 back) its twin.
pub fn column(r: *const st.Ram) void {
    copy(r, r.l(DST) + 0x46);
    copy(r, r.l(DST + 4) -% 0xA2);
}

fn copy(r: *const st.Ram, to: u32) void {
    var a3 = to;
    for (0..15) |k| {
        const src = r.l(PTRS + 4 * @as(u32, @intCast(k)));
        for (0..17) |i| r.sl(a3 + 0xE6 * @as(u32, @intCast(i)), r.l(src + 4 * @as(u32, @intCast(i))));
        a3 += 0xF46;
    }
}

/// $138C2: the 16-pixel column the screen has left, 245 lines.
pub fn clear(r: *const st.Ram, screen: u32) void {
    const a0 = screen + r.l(SCROLL) + 0x132;
    for (0..245) |k| {
        r.sl(a0 + 0xE6 * @as(u32, @intCast(k)), 0);
        r.sl(a0 + 0xE6 * @as(u32, @intCast(k)) + 4, 0);
    }
}
