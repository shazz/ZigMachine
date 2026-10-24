// --------------------------------------------------------------------------
// The sine scroller, riding the sea in the bottom border.
//
// THE FONT is built at build time (art.zig, by gen_anima.zig on the host):
// the 16x16 font EPX-doubled to 32x32, bevelled and outlined, every glyph in
// one strip of CELL_W x CELL_H cells in cart RAM. Its body index is a copper
// slot (a rainbow per line, bars.zig).
//
// THE FRAME: one CHISEL fill clears the band, then the 400 pixels are cut in
// 8-pixel columns; each column is ONE keyed blit straight from the strip in
// cart RAM, dropped to its own height on two sines. Columns are aligned in
// TEXT space (x = 8k - pos%8), so a column never straddles two glyphs, and two
// neighbours at the same height that continue each other go out as one blit.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const art = @import("art.zig");
const P = @import("palette.zig");
const T = @import("timeline.zig");

const CELL_W = art.CELL_W;
const CELL_H = art.CELL_H;
const STRIP_W = art.STRIP_W;
const COL = 8;
const AMP1: i32 = 7;
const AMP2: i32 = 4;
pub const TOP = 218; // the band's first row (physical): it ends at 276, in the bottom border
pub const BAND = CELL_H + 2 * (AMP1 + AMP2) + 2; // 58
const SPEED = 2; // px a tick

const TEXT =
    "ANIMA ...   A NEW SCREEN FOR THE ZIGMACHINE, WRITTEN FOR IT AND FOR NOTHING ELSE.   " ++
    "ONE OVERSCAN PLANE, EVERY BORDER OPENED BY HAND ON EVERY LINE...   " ++
    "COPPER BARS TURNING ON A DRUM, REFLECTED IN THE SEA: REAL RASTERS FROM THE HBL...   " ++
    "A LOGO THAT BREATHES, ONE BLITTER ROW AT A TIME...   " ++
    "GLENZ GLASS ON CHISEL, TURNED BY THE FPU...   " ++
    "MUSIC: BREATH 2000 BY TAO, PLAYED BY BARD...   " ++
    "GREETINGS TO EVERY ST AND AMIGA SCENER WHO EVER OPENED A BORDER OR CHASED A RASTER...   " ++
    "THE SOUL OF THE MACHINE IS IN ITS TIMING.   ";

const STRIP: *const [CELL_H * STRIP_W]u8 = &@import("anima_art").font;

pub var blits: u32 = 0;
var cleared = false;

pub fn reset() void {
    cleared = false;
}

fn glyphAt(text: []const u8, tx: i32) u32 {
    const n: i32 = @intCast(text.len);
    const c = text[@intCast(@mod(@divFloor(tx, CELL_W), n))];
    return if (c >= 32 and c < 32 + art.GLYPHS) c - 32 else 0;
}

fn waveAt(x: i32, t: u32) i32 {
    const a = t *% (1 << 25) +% @as(u32, @bitCast(x)) *% (1 << 23);
    const b = t *% (0xFFFF_FFFF - (3 << 24)) +% @as(u32, @bitCast(x)) *% (27 << 21);
    return (AMP1 * trig.sin(a) + AMP2 * trig.sin(b)) >> 16;
}

/// The oldschool scroller at tick t (it starts at T.SCROLL).
pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, t: u32) void {
    run(fb, bl, if (t < T.SCROLL) null else t - T.SCROLL, t, TEXT);
}

/// `st` ticks into `text` (null: not started, the band kept clear); t drives the wave.
pub fn run(fb: *zg.LogicalFB, bl: *zg.Blitter, st: ?u32, t: u32, text: []const u8) void {
    blits = 0;
    const s = st orelse {
        if (!cleared) bl.fill(fb, 0, TOP, zg.PHYSICAL_WIDTH, BAND, P.BG);
        cleared = true;
        return;
    };
    cleared = false;
    bl.fill(fb, 0, TOP, zg.PHYSICAL_WIDTH, BAND, P.BG);
    blits += 1;
    const pos: i32 = @intCast(s * SPEED);
    const base = pos - @mod(pos, COL) - zg.PHYSICAL_WIDTH; // the text enters from the right
    var k: i32 = 0;
    var run_x: i32 = 0;
    var run_y: i32 = 0;
    var run_sx: u32 = 0;
    var run_w: u16 = 0;
    while (k <= zg.PHYSICAL_WIDTH / COL) : (k += 1) {
        const tx = base + k * COL;
        const x = k * COL - @mod(pos, COL);
        const y = TOP + 1 + AMP1 + AMP2 + waveAt(x, t);
        const g = if (tx < 0) 0 else glyphAt(text, tx);
        const sx = g * CELL_W + @as(u32, @intCast(@mod(tx, CELL_W)));
        const blank = g == 0; // before the text, or a space: nothing to blit
        if (run_w > 0 and !blank and y == run_y and sx == run_sx + run_w) {
            run_w += COL;
            continue;
        }
        if (run_w > 0) flush(fb, bl, run_x, run_y, run_sx, run_w);
        run_w = 0;
        if (blank) continue;
        run_x = x;
        run_y = y;
        run_sx = sx;
        run_w = COL;
    }
    if (run_w > 0) flush(fb, bl, run_x, run_y, run_sx, run_w);
}

fn flush(fb: *zg.LogicalFB, bl: *zg.Blitter, x: i32, y: i32, sx: u32, w: u16) void {
    bl.blitImage(fb, @intCast(x), @intCast(y), STRIP, STRIP_W, @intCast(sx), 0, w, CELL_H, 0);
    blits += 1;
}
