// --------------------------------------------------------------------------
// THE END: the ending card. The breathing chrome logo comes back over a
// copper plasma -- entry 0 rewritten every line on three sines, so the
// background is a different colour on each of the 280 lines and through every
// border -- the glenz returns as the finale (an icosahedron, then the spiked
// star), and the end scroller rolls the credits. It burns to white at the
// end, and ANIMA starts over in the dark.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const P = @import("palette.zig");
const T = @import("timeline.zig");
const raster = @import("raster.zig");
const bars = @import("bars.zig");
const logo = @import("logo.zig");
const glenz = @import("glenz.zig");
const scroller = @import("scroller.zig");
const grade = @import("grade.zig");

const LEN = T.LOOP - T.END;
const BURN: u32 = 45;
const HALF = LEN / 2;

const TEXT =
    "ANIMA ...   CODE, PIXELS AND TIMING: CLAUDE, FOR MATT ...   " ++
    "MUSIC: MAD MAX (CUDDLY DEMOS) AND TAO (BREATH 2000) ...   " ++
    "RUNNING ON KESTREL: ZIGGY, CHISEL, FRESCO AND BARD ...   " ++
    "THANKS FOR WATCHING!         ";

pub fn enter(fb: *zg.LogicalFB, bl: *zg.Blitter) void {
    P.install(fb.palette);
    raster.use(&.{ P.BG, P.LOGO_BODY, P.FONT_BODY });
    raster.timing(fb, true);
    raster.openAll();
    bl.clear(fb, P.BG);
    logo.reset(fb, bl);
    glenz.reset();
    scroller.reset();
}

pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, lt: u32) void {
    const white = grade.flash(lt, LEN - BURN + grade.BURN);
    plasma(lt, white);
    bars.bodies(lt, logo.TOP, logo.BAND, scroller.TOP, scroller.BAND);
    logo.draw(fb, bl, T.BREATHE + T.BREATHE_TICKS + lt);
    const n: usize = if (lt < HALF) 2 else 3;
    glenz.finale(fb, bl, n, lt, lt % HALF);
    scroller.run(fb, bl, lt, lt, TEXT);
    if (lt + BURN >= LEN) burn(fb, (lt + BURN + 1 - LEN) * 255 / BURN);
}

/// Entry 0 per line: three sines of the line and the time, dark enough for the
/// chrome to stand on.
fn plasma(lt: u32, white: u32) void {
    for (0..raster.ROWS) |r| {
        const ru: u32 = @intCast(r);
        const a = trig.sin(ru *% (3 << 23) +% lt *% (1 << 25));
        const b = trig.sin(ru *% (5 << 22) -% lt *% (3 << 24));
        const c = trig.sin((ru + lt) *% (1 << 24));
        const lv = [3]u8{
            @intCast(((a + 65536) * 8) >> 17),
            @intCast(((b + 65536) * 4) >> 17),
            @intCast(3 + (((c + 65536) * 8) >> 17)),
        };
        const v = grade.lit(&lv, 15, white);
        if (raster.lines[r][0] != v) raster.lines[r][0] = v;
    }
}

/// The last BURN ticks: every colour, registers and line tables, to white.
fn burn(fb: *zg.LogicalFB, k: u32) void {
    const w = 0xFF00_0000 | k << 16 | k << 8 | k;
    for (0..256) |i| fb.palette[i] = w;
    for (&raster.lines) |*row| {
        row[0] = w;
        row[1] = w;
        row[2] = w;
    }
}
