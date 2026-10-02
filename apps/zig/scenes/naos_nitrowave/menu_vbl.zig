// --------------------------------------------------------------------------
// The menu VBL's logical program: what the template at $E10 and the 5,823
// fragments of $1688..$C3F8 do once the border code between them is set
// aside. Read back from the code by prototypes/naos_nitrowave_re/sem_extract.py
// and checked equal, byte for byte, to the 68000 code run by vbl68k.py over
// 1,500 frames (menu_sem.py):
//
//   erase  path word e: 32 rows of 224 bytes, screen+e <- picture+e
//          (56 x move.l (a2)+,(a3)+ then lea 6 on both, a row)
//   draw   path word d: from screen+d+16, 22 columns 16 px apart, 31 rows
//          each: planes 0..3 &= the mask long (both longs of the group),
//          planes 0,1 |= the font's long, plane 2 |= the font's plane-2 word --
//          or, on rows 4 and 5, its PLANE-3 word (those two rows read
//          `move.l $284(a4),d2` / `$324(a4)` where the rest read move.w).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const M = @import("menu.zig");

pub const LINE: u32 = 230; // bytes an overscan line
const ERASE_ROWS = 32;
const ERASE_BYTES = 224;
const COLS = 22;
const ROWS = 31;
const SRC_LINE: u32 = 160; // the font sheets are low-res screens
const BAND_X: u32 = 16; // lea $10(a5),a5
const PLANE3_ROWS = [_]u32{ 4, 5 };

pub fn run(r: *const st.Ram) void {
    const path = r.l(M.V_PATH);
    const e: u32 = r.w(path);
    const d: u32 = r.w(path + 2);
    r.sl(M.V_PATH, path + 4);
    const scr = r.l(M.V_DRAW);
    erase(r, scr, r.l(M.V_BG), e);
    const gfx = r.l(M.V_GFX);
    const mask = r.l(M.V_MASK);
    for (0..COLS) |c| {
        const cc: u32 = @intCast(c);
        column(r, r.l(gfx + 4 * cc), r.l(mask + 4 * cc), scr + d + BAND_X + 8 * cc);
    }
}

fn erase(r: *const st.Ram, scr: u32, bg: u32, e: u32) void {
    for (0..ERASE_ROWS) |row| {
        const o = e + LINE * @as(u32, @intCast(row));
        r.cp(scr + o, bg + o, ERASE_BYTES);
    }
}

fn column(r: *const st.Ram, g: u32, k: u32, dst0: u32) void {
    for (0..ROWS) |row| {
        const rr: u32 = @intCast(row);
        const dst = dst0 + LINE * rr;
        const src = g + SRC_LINE * rr;
        const m = r.l(k + SRC_LINE * rr);
        r.sl(dst, (r.l(dst) & m) | r.l(src));
        const plane2 = if (rr == PLANE3_ROWS[0] or rr == PLANE3_ROWS[1]) r.w(src + 6) else r.w(src + 4);
        r.sl(dst + 4, r.l(dst + 4) & m);
        r.sw(dst + 4, r.w(dst + 4) | plane2);
    }
}
