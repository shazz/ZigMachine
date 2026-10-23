// --------------------------------------------------------------------------
// The REAL raster: one HBL handler on plane 0, at the overscan magic column.
//
// Per PHYSICAL line (0..279) it
//   1. flickers the resolution (flickerBorder) when the line is to be open:
//      in the top band that opens the top border from this row down, on a
//      visible line it opens both side borders for that line, in the bottom
//      band it opens the bottom border from this row down -- the overscan is
//      earned line by line, and the DARK/OPEN phases show it being earned;
//   2. writes up to MAX colour registers from the line's row of `lines`, the
//      entries a part chose with `use` (the oldschool part: entry 0 = the
//      raster, the logo's body, the font's body; the rotozoom: 16 entries a
//      line, a palette per line). A register already holding its colour is
//      not rewritten.
//
// Entry 0 is the plane's background, so a raster on it runs edge to edge
// through every open border, as on an ST where the border is painted from the
// same register.
//
// THE GAG: `timing(fb, false)` registers the handler off the magic column, so
// every flicker of that frame is mistimed and the machine shows noise in the
// borders, exactly as a botched cycle count does on a real ST.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const T = @import("timeline.zig");

pub const ROWS: usize = zg.PHYSICAL_HEIGHT; // 280
pub const TOP: usize = zg.VERTICAL_BORDERS_HEIGHT; // 40: first visible row
pub const BOTTOM: usize = TOP + zg.HEIGHT; // 240: first bottom-border row
const MID: usize = TOP + zg.HEIGHT / 2; // 140
pub const MAX = 16;

pub var lines: [ROWS][MAX]u32 = @splat(@splat(0xFF00_0000));
var entries: [MAX]u8 = @splat(0);
var count: usize = 0;
/// 1 = flicker on this line.
pub var open: [ROWS]u8 = @splat(0);
var open_tick: u32 = 0xFFFF_FFFF;

pub fn install(fb: *zg.LogicalFB) void {
    fb.setOverscanBuffer();
    open = @splat(0);
    open_tick = 0xFFFF_FFFF;
    count = 0;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

/// The palette entries the HBL drives from `lines` (slot i -> entry e[i]).
pub fn use(e: []const u8) void {
    for (e, 0..) |v, i| entries[i] = v;
    count = e.len;
}

/// Good timing (the magic column) or a botched one (noise in every open border).
pub fn timing(fb: *zg.LogicalFB, good: bool) void {
    const x: u16 = if (good) zg.OVERSCAN_MAGIC_X else zg.OVERSCAN_MAGIC_X + 24;
    if (fb.fb_hbl_handler_position != x) fb.setFrameBufferHBLHandler(x, hbl);
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    const r: usize = line; // an overscan plane's handler gets PHYSICAL lines
    if (r >= ROWS) return;
    if (open[r] != 0) fb.flickerBorder();
    const pal = fb.palette;
    const row = &lines[r];
    for (entries[0..count], 0..) |e, i| {
        if (pal[e] != row[i]) pal[e] = row[i];
    }
}

/// Forget the cached open table: the next openAt/openAll rebuilds it.
pub fn reopen() void {
    open_tick = 0xFFFF_FFFF;
}

/// Every line flickers: the whole 400x280 is open (the newschool parts).
pub fn openAll() void {
    if (open_tick == 0xFFFF_FFFE) return;
    open_tick = 0xFFFF_FFFE;
    open = @splat(1);
}

/// Which lines flicker at tick t. Sides first, from the middle line out; then
/// the top border opens upward from the visible edge (a band row opens from the
/// first flicker down) and the bottom one rises from the screen's last line.
/// Once every line is open the table stays as it is: no stores.
pub fn openAt(t: u32) void {
    const key = @min(t, T.OPEN + T.SIDES_TICKS + T.BANDS_TICKS);
    if (key == open_tick) return;
    open_tick = key;
    const sides = T.ramp(t, T.OPEN, T.SIDES_TICKS) * (zg.HEIGHT / 2) / 256;
    const bands = T.ramp(t, T.OPEN + T.SIDES_TICKS, T.BANDS_TICKS) * TOP / 256;
    for (0..ROWS) |r| {
        const on = if (r < TOP)
            r + bands >= TOP
        else if (r < BOTTOM)
            t >= T.OPEN and (if (r < MID) MID - r else r - MID) <= sides
        else
            r + bands >= ROWS;
        const v: u8 = @intFromBool(on);
        if (open[r] != v) open[r] = v;
    }
}

/// True when line r flickers (the harness's view of what should be open).
pub fn isOpen(r: usize) bool {
    return r < ROWS and open[r] != 0;
}
