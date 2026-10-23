// --------------------------------------------------------------------------
// The breathing ANIMA logo.
//
// THE PICTURE is built at build time (art.zig, by gen_anima.zig on the host):
// "ANIMA" in the 16x16 font, EPX-doubled twice to 64-pixel letters, bevelled,
// outlined, drop-shadowed, and padded with WOB blank columns each side. Its
// body index is a copper slot (a chrome ramp per line, bars.zig).
//
// THE FRAME: the logo lives in a fixed band of BAND rows. Each band row shows
// one source row (a vertical stretch: the breath) at one x (a sine wobble),
// as ONE CHISEL blit straight from cart RAM. The source row is LW wide with
// WOB blank pixels each side, so as long as a row's x moves less than WOB a
// frame, the blit overwrites everything the row drew last frame: no erase.
// A row whose (source row, x) did not change is not blitted at all, rows that
// became blank are cleared with one fill a run, and consecutive rows that
// continue each other (next source row, same x) go out as one blit.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const art = @import("art.zig");
const P = @import("palette.zig");
const T = @import("timeline.zig");

const LW = art.LW;
const LH = art.LH;
pub const TOP = 4; // first band row (physical)
pub const BAND = 84; // rows the breath may cover (76 x 280/256 = 83)
const X0: i16 = (zg.PHYSICAL_WIDTH - LW) / 2;
const WAMP: i32 = 10; // wobble amplitude, px (< art.WOB)

/// The finished logo, LH rows of LW palette indices (0 = the raster shows).
pub const PIXELS: *const [LH * LW]u8 = @import("packed_assets").anima_logo;

comptime {
    if (WAMP >= art.WOB) @compileError("logo: the wobble must stay inside the blank margin");
}


const BLANK: i16 = -1;
var last_src: [BAND]i16 = @splat(BLANK);
var last_dx: [BAND]i16 = @splat(0);
pub var blits: u32 = 0; // CHISEL ops this frame (the harness counts them too)

/// Forget what the band holds (after init or a timeline jump): every row is
/// redrawn, and the band is cleared once.
pub fn reset(fb: *zg.LogicalFB, bl: *zg.Blitter) void {
    bl.fill(fb, 0, TOP, zg.PHYSICAL_WIDTH, BAND, P.BG);
    last_src = @splat(BLANK);
    last_dx = @splat(0);
}

/// The breath: the logo's height scale at tick t, Q8 (256 = natural size).
pub fn scale(t: u32) i32 {
    const inhale: i32 = @intCast(T.ramp(t, T.BREATHE, T.BREATHE_TICKS));
    const breath = (24 * trig.sin(t *% (0xFFFF_FFFF / 150))) >> 16; // +-9 %, 2.5 s a breath
    return (inhale * (256 + breath)) >> 8;
}

pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, t: u32) void {
    blits = 0;
    const s = scale(t);
    const inv: i32 = if (s > 0) @divTrunc(1 << 24, s) else 0; // source rows per band row, Q16
    const phase = t *% (1 << 25);
    var fill_from: ?usize = null;
    var run: ?Run = null;
    for (0..BAND + 1) |y| {
        var src: i16 = BLANK;
        var dx: i16 = 0;
        if (y < BAND and s > 0) {
            const off: i32 = (@as(i32, @intCast(y)) - BAND / 2) * inv;
            const sr = (off >> 16) + LH / 2;
            if (sr >= 0 and sr < LH) src = @intCast(sr);
            dx = @intCast((WAMP * trig.sin(phase +% @as(u32, @intCast(y)) *% (1 << 26))) >> 16);
        }
        const same = y < BAND and src == last_src[y] and (src == BLANK or dx == last_dx[y]);
        // blank runs that were not blank: one fill each
        if (y < BAND and src == BLANK and !same) {
            if (fill_from == null) fill_from = y;
        } else if (fill_from) |f| {
            bl.fill(fb, 0, @intCast(TOP + f), zg.PHYSICAL_WIDTH, @intCast(y - f), P.BG);
            blits += 1;
            fill_from = null;
        }
        // logo rows that changed: merged into runs that continue each other
        const want = y < BAND and src != BLANK and !same;
        if (run) |*r| {
            if (want and dx == r.dx and src == r.src + @as(i16, @intCast(r.n)) and y == r.y + r.n) {
                r.n += 1;
            } else {
                r.flush(fb, bl);
                run = null;
            }
        }
        if (want and run == null) run = .{ .y = y, .src = src, .dx = dx, .n = 1 };
        if (y < BAND) {
            if (last_src[y] != src) last_src[y] = src;
            if (last_dx[y] != dx) last_dx[y] = dx;
        }
    }
    if (run) |*r| r.flush(fb, bl);
}

const Run = struct {
    y: usize,
    src: i16,
    dx: i16,
    n: u16,

    fn flush(r: *const Run, fb: *zg.LogicalFB, bl: *zg.Blitter) void {
        bl.blitImage(fb, X0 + r.dx, @intCast(TOP + r.y), PIXELS, LW, 0, @intCast(r.src), LW, r.n, null);
        blits += 1;
    }
};
