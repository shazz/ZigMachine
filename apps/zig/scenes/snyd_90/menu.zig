// --------------------------------------------------------------------------
// The menu (part 0: tracks 1..14 side 0, read to $1000 and entered there).
// TFE of OMEGA's code, Red's graphics, Mad Max's tune (subtune 1 of the
// module at $79C4). Ported against the part's own memory (st.zig), so every
// table is the disk's and every variable sits where the 68000 kept it; the
// result is checked byte for byte against Hatari RAM (menu_test.zig).
//
// One iteration of the main loop ($29E0), once a VBL:
//   phases     $29CA idles 500 iterations; then the sprites' band slides up
//              64 lines ($29DC -= 160 a frame) while the two Y walkers' amplitudes
//              ($2F76/$2F94) shrink with it, pauses 100 frames ($29DE), swaps
//              to the next letter set (OMEGA -> SYNC -> TCB), and slides back.
//   flip       draw into $6D800 / $78000 in turn, shown from the next VBL.
//   clear      62 rows x 40 bytes at each sprite's address of two frames ago.
//   scroller   13 lines at line 140 (menu_draw.zig).
//   sprites    the head: Y = walker 1 + walker 2, X = walker 3 + walker 4
//              ($2F2E: a sine table of longs, stepped by a list of (count,
//              step) pairs), pushed on a 25-entry ring; the letters read it
//              6 entries apart, the oldest drawn first.
// The VBL ($1562) only counts frames and takes F1..F6 ($3B..$40) as d0 1..6.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const draw = @import("menu_draw.zig");

pub const BASE: u32 = 0x1000;
pub const TOP: u32 = 0x80000;
pub const IMAGE: usize = 140 * 512; // the loader's read: 140 sectors
pub const SCREEN_A: u32 = 0x6D800;
pub const SCREEN_B: u32 = 0x78000;
pub const PALETTE: u32 = 0x384C;

const WALKERS = [4]u32{ 0x2F68, 0x2F86, 0x2FA4, 0x2FC2 };
const Y_AMP_1: u32 = 0x2F76;
const Y_AMP_2: u32 = 0x2F94;
const AMP: u16 = 0x44;
const IDLE: u32 = 0x29CA;
const SETS: u32 = 0x29CC; // three set pointers, rotated
const FLIP: u32 = 0x29D8;
const PHASE: u32 = 0x29DA; // 0 idle, 1 sliding up, 2 sliding down
pub const SLIDE: u32 = 0x29DC; // bytes: -160 a line
const PAUSE: u32 = 0x29DE;
const SET: u32 = 0x158E;
const SLIDE_TOP: u16 = 0xD800; // -64 lines

/// After the part is in memory: the original's set-up ($1000..$1072) minus
/// the sprite compiler (menu_draw.zig blits what it compiles).
pub fn init(r: *const st.Ram) void {
    draw.indexSprites(r);
    for (WALKERS) |w| _ = walk(r, w);
    r.zero(SCREEN_A, TOP - SCREEN_A);
}

/// One pass of the main loop. Returns the screen it drew: the one shown next.
pub fn iteration(r: *const st.Ram) u32 {
    phases(r);
    flip(r);
    const set = r.l(SET);
    r.sw(draw.COUNT, r.w(set));
    r.sl(draw.TABLES, set + 2);
    draw.clear(r, r.w(draw.COUNT));
    draw.scroller(r);
    const y = amplitude(r, WALKERS[0]) +% amplitude(r, WALKERS[1]);
    const x = amplitude(r, WALKERS[2]) +% amplitude(r, WALKERS[3]);
    draw.sprites(r, x, y);
    return r.l(draw.DRAW);
}

/// $2F2E: the walker's value, then its step (and, on a wrap, its count).
fn walk(r: *const st.Ram, a: u32) u16 {
    var cur = r.l(a);
    const v = r.w(cur + 2);
    cur +%= 2 * @as(u32, r.w(a + 0x10));
    if (cur == r.l(a + 4)) {
        cur = r.l(a + 8);
        r.sw(a + 0xC, r.w(a + 0xC) -% 1);
        if (r.w(a + 0xC) == 0) {
            var p = r.l(a + 0x12);
            r.sw(a + 0xC, r.w(p));
            r.sw(a + 0x10, r.w(p + 2));
            p += 4;
            if (p == r.l(a + 0x16)) p = r.l(a + 0x1A);
            r.sl(a + 0x12, p);
        }
    }
    r.sl(a, cur);
    return v;
}

/// addi.w #$8000 / mulu.w amplitude / swap.
fn amplitude(r: *const st.Ram, a: u32) u16 {
    const v: u32 = walk(r, a) +% 0x8000;
    return @truncate(v * r.w(a + 0xE) >> 16);
}

fn phases(r: *const st.Ram) void {
    if (r.w(PAUSE) != 0) {
        r.sw(PAUSE, r.w(PAUSE) - 1);
        if (r.w(PAUSE) == 0) rotateSets(r);
        return;
    }
    const phase = r.w(PHASE);
    if (phase != 0) {
        const d: u16 = if (phase == 2) 1 else 0xFFFF;
        r.sw(SLIDE, r.w(SLIDE) +% 160 *% d);
        r.sw(Y_AMP_1, r.w(Y_AMP_1) +% d);
        r.sw(Y_AMP_2, r.w(Y_AMP_2) +% d);
        if (phase == 1 and r.w(SLIDE) == SLIDE_TOP) {
            r.sw(Y_AMP_1, 0);
            r.sw(Y_AMP_2, 0);
            r.sw(PHASE, 2);
            r.sw(PAUSE, 100);
        }
        if (phase != 2 or r.w(SLIDE) != 0) return;
        r.sw(Y_AMP_1, AMP); // back down: idle again, from this very iteration
        r.sw(Y_AMP_2, AMP);
        r.sw(PHASE, 0);
    }
    r.sw(IDLE, r.w(IDLE) -% 1);
    if (r.w(IDLE) != 0) return;
    r.sw(PHASE, 1);
    r.sw(IDLE, 500);
}

fn rotateSets(r: *const st.Ram) void {
    const a = r.l(SETS);
    r.sl(SETS, r.l(SETS + 4));
    r.sl(SETS + 4, r.l(SETS + 8));
    r.sl(SETS + 8, a);
    r.sl(SET, r.l(SETS));
}

/// $2AB6: alternate the screens; swap the two clear lists.
fn flip(r: *const st.Ram) void {
    r.sw(FLIP, r.w(FLIP) -% 1);
    if (r.w(FLIP) == 0) {
        r.sw(FLIP, 2);
        r.sl(draw.DRAW, SCREEN_A);
    } else {
        r.sl(draw.DRAW, SCREEN_B);
    }
    const a = r.l(draw.CLEAR);
    r.sl(draw.CLEAR, r.l(draw.CLEAR + 4));
    r.sl(draw.CLEAR + 4, a);
}
