// --------------------------------------------------------------------------
// The ST screen, kept as the ST kept it (200 lines of 80 interleaved plane
// words), collapsed once a frame into ONE overscan plane's palette indices.
//
// Index 16 is ST colour 0 (opaque, so the window does not fall through to the
// border colour), 1..15 the other ST colours, 17..58 the 42 colour-0 writes of
// a rainbow line. The plane's HBL installs each line's 16 colours (and, on
// the four rainbow lines, the 42 rainbow colours and an open side border); a
// global HBL paints the closed border with the line's colour 0, because on an
// ST the border IS colour 0 (vex/raster.zig did the same for SLiPPY's VEX).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

pub const ROWS = 200;
pub const WORDS = 80;
pub const LOGO_ROWS = 43;
pub const BG: u8 = 16; // ST colour 0
pub const RAIN0: u8 = 17; // first rainbow entry
pub const RAIN_N = 42; // $102B2: 42 `move.w (a1)+,$8240` a line
/// The two lines each rainbow is held for ($102B2 runs its 42 writes twice).
pub const rain_rows = [4]u16{ 42, 43, 197, 198 };

// The overscan plane, as vex/planes.zig lays it: 26 words wide so every word
// stays on a 16-px boundary; the window at buffer x 48, the raster's left edge
// at buffer x 8.
pub const BUF_W: u16 = 26 * 16;
pub const ORG_X: usize = 48;
pub const ORG_Y: usize = zg.VERTICAL_BORDERS_HEIGHT;
pub const SCROLL_X: u32 = ORG_X - zg.HORIZONTAL_BORDERS_WIDTH;

/// 4-aligned: a pair of plane words is often read or written as one 32-bit
/// access, and a misaligned one traps on the board.
pub const Screen = struct {
    rows: [ROWS][WORDS]u16 align(4),
};
const Logo = struct {
    c: [2][LOGO_ROWS][WORDS]u16 align(4),
};

pub var st: *Screen = undefined;
/// The logo on each of the two ST screens: the glint XORs one per frame ($126E8).
pub var logo: *[2][LOGO_ROWS][WORDS]u16 = undefined;
/// What each line was last composed from: a line is recomposed only when its
/// words changed (the drum and the scroller move ~60 of 200 lines a frame, and
/// every VRAM store is a bus write on the board).
var shown: *Screen = undefined;
/// Set by invalidate(): the next compose draws everything, `shown` regardless.
var stale = true;
var owned = false;

/// This frame's colours, built by palette.zig, played by the HBLs.
pub var row_pal: [ROWS][16]u32 = undefined;
pub var rain_pal: [2][RAIN_N]u32 = undefined;

pub fn alloc() void {
    if (owned) return;
    st = &zg.mem.mustAlloc(Screen, 1)[0];
    shown = &zg.mem.mustAlloc(Screen, 1)[0];
    logo = &zg.mem.mustAlloc(Logo, 1)[0].c;
    owned = true;
}

pub fn clear() void {
    for (&st.rows) |*r| @memset(r, 0);
}

/// Forget what is on the plane: the next compose redraws every line.
pub fn invalidate() void {
    stale = true;
    border_last = 0;
}

/// Which rainbow (0 top, 1 bottom) line `y` shows, if any.
fn rainRow(y: usize) ?usize {
    if (y == rain_rows[0] or y == rain_rows[1]) return 0;
    if (y == rain_rows[2] or y == rain_rows[3]) return 1;
    return null;
}

/// EXPAND[n]: nibble n's four bits as four byte lanes of 0/1, leftmost pixel lowest.
const EXPAND: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (&t, 0..) |*e, n| {
        var v: u32 = 0;
        for (0..4) |m| v |= @as(u32, (n >> (3 - m)) & 1) << (8 * m);
        e.* = v;
    }
    break :blk t;
};

/// What colour 0 shows as, 4 pixels a word: BG on an ordinary line.
const BG4 = [4]u32{ 0x1010_1010, 0x1010_1010, 0x1010_1010, 0x1010_1010 };

/// RAIN_W: on a rainbow line, the rainbow entry under each buffer pixel, packed
/// 4 a word like the plane (leftmost lowest). The raster's x 0..399 is buffer
/// x 8..407; segment boundaries fall where Hatari's capture put them, content
/// x = 9 mod 12. The ST's border is 48 px to our 40: in the capture the first,
/// partial segment shows the line's 2nd colour and the next starts at content x -39.
const RAIN_W: [BUF_W / 4]u32 = blk: {
    var t = [_]u32{0} ** (BUF_W / 4);
    for (8..408) |bx| {
        const seg = (bx - 8 + 11) / 12 + 1;
        t[bx / 4] |= @as(u32, RAIN0 + @min(seg, RAIN_N - 1)) << (8 * (bx % 4));
    }
    break :blk t;
};

/// 16 pixels of one ST word group; colour-0 pixels take `fill`'s lane.
fn group(dst: *[4]u32, w: *const [4]u16, fill: *const [4]u32) void {
    inline for (0..4) |j| {
        const sh = 12 - 4 * j;
        const v = EXPAND[(w[0] >> sh) & 15] | EXPAND[(w[1] >> sh) & 15] << 1 |
            EXPAND[(w[2] >> sh) & 15] << 2 | EXPAND[(w[3] >> sh) & 15] << 3;
        // lanes holding 0 take the fill: (v + 0x7F) sets bit 7 exactly where v != 0
        const zero = ~(v +% 0x7F7F_7F7F) & 0x8080_8080;
        dst[j] = v | (fill[j] & ((zero >> 7) * 0xFF));
    }
}

/// One ST line into the window; on a rainbow line colour 0 becomes the
/// rainbow entry under it. Word stores only, and nothing read back from VRAM.
/// With `old` (what the line was last composed from) a group whose four words
/// did not change is skipped: its pixels are already right, since a group's
/// pixels depend only on its words and on whether the line is a rainbow line.
/// Without it (after invalidate) every group is drawn, and the rainbow lines'
/// open side borders too (RAIN_W never changes, so once is enough).
fn line(buf: []u8, stride: usize, y: usize, words: *const [WORDS]u16, old: ?*const [WORDS]u16) void {
    // the row starts 4-aligned: the plane is (vramAlloc) and the stride is 416
    const out: *[BUF_W / 4]u32 = @ptrCast(@alignCast(buf[(ORG_Y + y) * stride ..][0..BUF_W]));
    const rain = rainRow(y) != null;
    for (0..20) |g| {
        const w = words[4 * g ..][0..4];
        if (old) |o| if (std.mem.eql(u16, w, o[4 * g ..][0..4])) continue;
        const k = ORG_X / 4 + 4 * g;
        group(out[k..][0..4], w, if (rain) RAIN_W[k..][0..4] else &BG4);
    }
    if (!rain or old != null) return;
    @memcpy(out[8 / 4 .. ORG_X / 4], RAIN_W[8 / 4 .. ORG_X / 4]);
    @memcpy(out[(ORG_X + 320) / 4 .. 408 / 4], RAIN_W[(ORG_X + 320) / 4 .. 408 / 4]);
}

/// The whole frame: the logo from this frame's screen, the rest from st.
/// Only the lines, and in them the 16-px groups, whose words changed.
pub fn compose(fb: *LogicalFB, parity: u1) void {
    const buf = fb.fb[0 .. @as(usize, fb.stride) * fb.fb_h];
    const stride: usize = fb.stride;
    const full = stale;
    stale = false;
    for (0..ROWS) |y| {
        const words = if (y < LOGO_ROWS) &logo[parity][y] else &st.rows[y];
        const was = &shown.rows[y];
        if (!full and std.mem.eql(u16, words, was)) continue;
        line(buf, stride, y, words, if (full) null else was);
        was.* = words.*;
    }
}

/// The plane's HBL (overscan: PHYSICAL lines). Only entries that changed are
/// stored, judged against the previous line's colours (cart RAM, hot in the
/// D$) rather than by reading the palette back out of VRAM; the first line
/// stores all 16. Each rainbow is held for two lines, so it is stored once.
pub fn planeHbl(fb: *LogicalFB, _: *ZigOS, ln: u16, _: u16) void {
    if (ln < ORG_Y or ln >= ORG_Y + ROWS) return;
    const y = ln - ORG_Y;
    const p = &row_pal[y];
    if (y == 0) {
        fb.palette[BG] = p[0];
        for (1..16) |i| fb.palette[i] = p[i];
    } else {
        const q = &row_pal[y - 1];
        if (q[0] != p[0]) fb.palette[BG] = p[0];
        for (1..16) |i| {
            if (q[i] != p[i]) fb.palette[i] = p[i];
        }
    }
    if (rainRow(y)) |r| {
        if (y == rain_rows[0] or y == rain_rows[2]) {
            for (rain_pal[r], 0..) |c, i| fb.palette[RAIN0 + i] = c;
        }
        fb.flickerBorder();
    }
}

/// The colour last put in the border register (0: none yet, rgba() is opaque).
var border_last: u32 = 0;

/// The global HBL: the border is the line's colour 0 (above and below the
/// screen, what the first and last lines left behind). Stored only on a change.
pub fn borderHbl(zigos: *ZigOS, ln: u16) void {
    const y: usize = if (ln < ORG_Y) 0 else @min(ln - ORG_Y, ROWS - 1);
    const c = row_pal[y][0];
    if (c == border_last) return;
    border_last = c;
    zigos.setBackgroundColor(Color.fromRGBA(c));
}
