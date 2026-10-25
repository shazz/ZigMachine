// --------------------------------------------------------------------------
// The original's Timer B chain, as real rasters (RAM at load base $aa9a):
//   * $aff0, end of display line 1: the TOP LASER — 37 move.w (a0)+,$ff8240
//     on line 2, one colour-0 word every 12 cycles = 12 pixels, from a
//     124-word gradient table ($2ee54) whose read pointer steps one word a
//     frame over 86 starts; then colour 0 = $000 (the one black pixel at the
//     left edge of line 3) and the TOP palette's 16 registers;
//   * $b104, 194 lines on: the BOTTOM LASER (36 writes on line 196, the last
//     colour running on to the right edge, its pointer 39 words ahead of the
//     top one on the displayed frame) and the BOTTOM palette from line 197.
// Colour 0 changes mid-line, which one HBL a line cannot do, so each laser
// row holds a stripe of palette INDICES, one per 12-pixel write (17.. top,
// 61.. bottom), and the frame writes those entries' colours — what the
// registers held under the beam. The split is the plane's HBL: bottom
// palette on lines 0..17 (the previous frame's, as on the machine), top
// from 18, bottom from 212, with the border flicker on every line.
// Plane rows: ST display line L is physical row L + 15 (the plate's row).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub const TOP_ROW = A.ART_Y + 2; // line 2: the top laser
pub const BOT_ROW = A.ART_Y + 196; // line 196: the bottom laser
const TOP_PAL_ROW = TOP_ROW + 1;
const BOT_PAL_ROW = BOT_ROW + 1;
const TOP_IDX = 16; // + write k (1..37)
const BOT_IDX = 60; // + write k (1..36)
const BLACK_IDX = 100;
const STARTS = 86; // ($2ef00 - $2ee54) / 2
pub const BOT_LEAD = 39;

/// Stripe rows (cart RAM, so a plane copy reads them): write k of the top
/// laser starts at plane x = 12k - 43, the bottom's at 12k - 47.
const top_stripe: [zg.PHYSICAL_WIDTH]u8 = stripe(43, 37, TOP_IDX);
const bot_stripe: [zg.PHYSICAL_WIDTH]u8 = stripe(47, 36, BOT_IDX);

fn stripe(comptime lead: i32, comptime n: i32, comptime base: u8) [zg.PHYSICAL_WIDTH]u8 {
    var out: [zg.PHYSICAL_WIDTH]u8 = undefined;
    for (&out, 0..) |*p, x| p.* = base + @as(u8, @intCast(@min(@divFloor(@as(i32, @intCast(x)) + lead, 12), n)));
    return out;
}

/// The palettes the chain installs, as RGBA: lines 0..17 run on what the
/// previous frame's bottom load left (`first`: the bottom palette, colour 0
/// popped by the $38 key), the top from line 18, the bottom from 212.
var first: [16]u32 = undefined;
var top: [16]u32 = undefined;
var bot: [16]u32 = undefined;

pub fn setPalettes(t: *const [16]u16, b: *const [16]u16, c0: ?u16, pop: ?u16) void {
    for (0..16) |i| {
        top[i] = A.st(t[i]);
        bot[i] = A.st(b[i]);
    }
    if (c0) |c| {
        top[0] = A.st(c);
        bot[0] = A.st(c);
    }
    first = bot;
    if (pop) |c| first[0] = A.st(c);
}

fn load(fb: *zg.LogicalFB, p: *const [16]u32) void {
    for (0..16) |i| {
        if (fb.palette[i] != p[i]) fb.palette[i] = p[i];
    }
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    fb.flickerBorder(); // every line: top, side and bottom borders open
    if (line == 0) load(fb, &first) else if (line == TOP_PAL_ROW) load(fb, &top) else if (line == BOT_PAL_ROW) load(fb, &bot);
}

pub fn install(fb: *zg.LogicalFB) void {
    fb.setFrameBufferHBLHandlerPure(zg.OVERSCAN_MAGIC_X, hbl); // own palette + flicker only
}

/// The laser entries for laser frame `n` (frames the chain has run), or all
/// colour `off` when the chain is not running (the flash).
pub fn lasers(fb: *zg.LogicalFB, n: u32, off: ?u16) void {
    const t: usize = n % STARTS;
    const b: usize = (n + BOT_LEAD) % STARTS;
    for (1..38) |k| set(fb, TOP_IDX + k, off orelse A.laser[t + k - 1]);
    for (1..37) |k| set(fb, BOT_IDX + k, off orelse A.laser[b + k - 1]);
    set(fb, BLACK_IDX, off orelse 0);
}

fn set(fb: *zg.LogicalFB, i: usize, w: u16) void {
    const c = A.st(w);
    if (fb.palette[i] != c) fb.palette[i] = c;
}

/// Lay the stripes into buffer rows `y0 + TOP_ROW` / `+ BOT_ROW` (y0 = the
/// scroll offset), over pixels that are colour 0 only when `keep` (content
/// drawn on the line keeps its own colour, as on the machine).
pub fn stamp(d: blit.Dst, y0: usize, keep: bool) void {
    put(d, y0 + TOP_ROW, &top_stripe, keep);
    put(d, y0 + BOT_ROW, &bot_stripe, keep);
    const at = (y0 + TOP_PAL_ROW) * d.stride;
    if (!keep or d.buf[at] == 0) d.buf[at] = BLACK_IDX;
}

fn put(d: blit.Dst, y: usize, s: *const [zg.PHYSICAL_WIDTH]u8, keep: bool) void {
    const row = d.buf[y * d.stride ..][0..zg.PHYSICAL_WIDTH];
    if (!keep) {
        blit.blit(d, blit.Image.init(s, zg.PHYSICAL_WIDTH), null, 0, @intCast(y), null, .copy);
        return;
    }
    for (row, s) |*p, v| {
        if (p.* == 0) p.* = v;
    }
}

/// The stripe index at plane column x of a laser row (plate row 2 or 196):
/// what a colour-0 pixel there shows.
pub fn stripeAt(x: usize, plate_row: usize) u8 {
    return if (plate_row == TOP_ROW - A.ART_Y) top_stripe[x] else bot_stripe[x];
}

/// Clear the three stripe pixels' rows at offset y0 (the bob moved them).
pub fn unstamp(d: blit.Dst, y0: usize) void {
    d.fill(0, @intCast(y0 + TOP_ROW), zg.PHYSICAL_WIDTH, 2, 0);
    d.fill(0, @intCast(y0 + BOT_ROW), zg.PHYSICAL_WIDTH, 1, 0);
}
