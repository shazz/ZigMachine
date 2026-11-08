// --------------------------------------------------------------------------
// What the Timer-B chain ($102B2 ... $1068A) leaves in the colour registers on
// every line, rebuilt here a frame at a time (prototypes/erfurt_re/tools/
// reconstruct.py walks the original's chain and agrees with this):
//
//   0..41    the logo's 16 colours ($2E5FE, loaded by the VBL)
//   42, 43   a rainbow: colour 0 rewritten 42 times along the line, 12 px each
//   44..159  a record every 2 lines ($104FE): colour 0 (navy, or the marker's
//            $012), the drum's front/back colours from ramp $4E462 and the
//            scroller's from ramp $4DD36, both scrolled by `phase`
//   160..166 the 59th record, held ($105B2)
//   167..196 colours 0-3 from the floor's records ($105F4, $4D8E4)
//   197, 198 the rainbow again, the other way round ($1400E)
//   199      colour 0 back to $001
// Plane 0 is the drum's front face (and the floor), plane 1 the back face
// (and its shadow), plane 2 the scroller: so colour 1/3/5/7 is the front's,
// 2 the back's and 4/6 the scroller's (the front passes in front of the
// scroller, the back behind it).
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const C = @import("colour.zig");
const S = @import("screen.zig");

pub const RAIN_TABLE = 77; // $843DE: the 35 hues repeated
pub const RAIN_PERIOD = 0x46; // $843DC counts to 70

pub const Frame = struct {
    phase: u16, // $4EB8E, 0..152
    rain: u16, // $843DC, 0..69
    drum_top: i32,
    n: i32,
    r_a: i32,
    fade: u8, // exit fade steps done (0..7)
};

fn ramp(table: []const u8, i: i32) u32 {
    const k: usize = @intCast(@max(0, @min(i, A.RAMP_LEN - 1)));
    return (@as(u32, A.be(table, 2 * k)) << 16) | A.be(table, 2 * k + 1);
}

/// The record for the line pair starting at even line `y` (built for line y+1).
fn record(f: *const Frame, y: i32) [8]u16 {
    const l = y + 1;
    const g = ramp(A.ramp_scroll, l - 43 + @as(i32, f.phase));
    const gh: u16 = @truncate(g >> 16);
    const gl: u16 = @truncate(g);
    const i = l - f.drum_top;
    if (i < 0 or i >= f.n or l < 45 or l > 166) return .{ 0x001, 0, 0, 0, gh, gl, gh, gl };
    const t = i - f.r_a;
    const marker = t >= -10 and t <= 8;
    const d = ramp(A.ramp_drum, l - 43 + 0x99 - @as(i32, f.phase));
    const front: u16 = if (marker) 0x777 else @truncate(d >> 16);
    const back: u16 = if (marker) 0x012 else @truncate(d);
    return .{ if (marker) 0x012 else 0x001, front, back, front, gh, front, gh, front };
}

fn setRow(y: usize, words: *const [16]u16, fade: u8) void {
    for (words, 0..) |c, i| S.row_pal[y][i] = C.show(c, fade);
}

/// Rows from..to-1 all hold `words`: converted once, the rest copied.
fn setRows(from: usize, to: usize, words: *const [16]u16, fade: u8) void {
    setRow(from, words, fade);
    for (from + 1..to) |l| S.row_pal[l] = S.row_pal[from];
}

pub fn build(f: *const Frame) void {
    var cur: [16]u16 = undefined;
    for (0..16) |i| cur[i] = A.be(A.logo_pal, i);
    setRows(0, 44, &cur, f.fade);
    // rows 44.. : colours 8-15 are never shown below the logo (plane 3 is empty)
    var y: i32 = 44;
    while (y < 160) : (y += 2) {
        const r = record(f, y);
        @memcpy(cur[0..8], &r);
        if (y == 44) cur[0] = 0x001; // $10488 keeps colour 0 from the rainbow's `move.w #1`
        setRows(@intCast(y), @intCast(y + 2), &cur, f.fade);
    }
    @memcpy(cur[0..8], &record(f, 160));
    setRows(160, 167, &cur, f.fade);
    for (0..13) |k| {
        for (0..4) |i| cur[i] = A.be(A.floor_pal, 4 * k + i);
        const from = 167 + 2 * k;
        const to = if (k == 12) 199 else from + 2;
        setRows(from, to, &cur, f.fade);
    }
    cur[0] = 0x001;
    setRow(199, &cur, f.fade);
    rainbows(f);
}

/// $13FEA / $1400E: the top line reads the table forwards from rain/2, the
/// bottom one from 35 - rain/2, so the two run in opposite directions.
fn rainbows(f: *const Frame) void {
    const h = f.rain >> 1;
    const starts = [2]usize{ h, if (h == 0) 0 else 35 - h };
    for (starts, 0..) |s, r| {
        for (0..S.RAIN_N) |k| {
            const c = A.be(A.rainbow, (s + k) % 35);
            S.rain_pal[r][k] = C.show(c, f.fade);
        }
    }
}
