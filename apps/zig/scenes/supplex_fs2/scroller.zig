// --------------------------------------------------------------------------
// SUPPLEX FS2 — the 22-letter scroller: drawn into a 320x16 strip (CODEF's
// 640x32 scrollcanvas, halved), then copied column by column onto the screen
// with each column displaced vertically by sin(v0)*15 + sin(v1)*50 (CODEF
// myfxparam), flat grey.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const panel = @import("panel.zig");

const LogicalFB = zg.LogicalFB;

// CODEF: 640x32 strip, tiles 32 wide, speed 4, wide=21 and the loop runs
// i <= wide, so 22 letters, laid out at wide*fontw + i*fontw. Halved.
pub const STRIP_W: i32 = 320;
pub const STRIP_H: i32 = 16;
pub const NB_LETTERS: usize = 22;
pub const SCROLL_SPEED: i32 = 2; // whole pixels, so the integer ring is bit-exact
pub const SCROLL_START: i32 = 21 * 16; // wide*fontw, halved
pub const SCROLL_X: i32 = 28 + panel.X_OFF; // distcanvas is blitted at CODEF x=56

// FX.siny(0, 340) over the strip: every source COLUMN is drawn at
// y = 340 + sin(v0)*30 + sin(v1)*100, v0/v1 advancing 0.03/0.01 per doubled
// column and drifting -0.05/-0.04 per frame. Halved: amplitudes and the base y
// halve, the per-column incs double (an ST column is two CODEF columns), the
// per-frame drift is a phase and does not change.
// Phases are u32 turns (zg.fixtrig), the sine a table: no float per column.
const SINY_AMP_A: i32 = 15;
const SINY_AMP_B: i32 = 50;
const SINY_INC_A = zg.fixtrig.angle(0.06);
const SINY_INC_B = zg.fixtrig.angle(0.02);
pub const SINY_OFF_A = zg.fixtrig.angle(-0.05);
pub const SINY_OFF_B = zg.fixtrig.angle(-0.04);
const SINY_Y: i32 = 170; // CODEF posy 340

// The band the sine can reach: rows SINY_Y +-65 (+ the 16-row strip) with a
// margin, over the strip's 320 columns. Nothing outside it ever changes.
pub const BAND_TOP: i32 = SINY_Y - 74;
pub const BAND_H: i32 = 2 * 74 + STRIP_H;

comptime {
    const reach = SINY_AMP_A + SINY_AMP_B + 1; // +1: the sum truncates
    if (SINY_Y - reach < BAND_TOP or SINY_Y + reach + STRIP_H > BAND_TOP + BAND_H) @compileError("the band misses the sine's reach");
}

/// wave.SineSum(2) in integers: yields SINY_Y + 15 sin(a) + 50 sin(b) per
/// column (truncated), the phases advancing by their incs.
const SinySweep = struct {
    a: zg.fixtrig.Angle,
    b: zg.fixtrig.Angle,
    pub fn next(it: *SinySweep) i32 {
        const q = SINY_Y * zg.fixtrig.ONE + SINY_AMP_A * zg.fixtrig.sin(it.a) + SINY_AMP_B * zg.fixtrig.sin(it.b);
        it.a +%= SINY_INC_A;
        it.b +%= SINY_INC_B;
        return @divTrunc(q, zg.fixtrig.ONE);
    }
};

// The screen's own scrolltext, verbatim from screen.js.
pub const SCROLL_TEXT =
    "            ***   S U P P L E X   ***       IS PROUD TO PRESENT THEIR LATEST RELEASE CALLED    *** FLIGHT SIMULATOR II NEW DATA DISK ***      " ++
    "RELEASED ON 26/02/90              TO CONTACT US WRITE TO : (ONLY THESE 4 LINES) SUPPLEX, POSTE RESTANTE, 8450 HAMMEL, DENMARK   " ++
    "OR CALL OUR BBS IN ITALY AT 0039 40 57 54 24 OR CALL SUPPLEX WHQ AT 704 254 9142                GREETINGS TO ALL CONTACTS!!!    " ++
    "THEREFORE SEE YOU SOON AT THE CE-BIT !!!!!!!!     ---------------------------               ...CODEF REMAKE BY MELLOW MAN....          ";

pub const Ring = zg.scrollring.Ring(i32, NB_LETTERS);

// The scroll strip (CODEF's scrollcanvas), rebuilt every frame. Module scope:
// a buffer this size inside the Demo struct costs a duplicate data segment.
var strip = [_]u8{0} ** @as(usize, STRIP_W * STRIP_H);

// scrolltext_horizontal.draw(0) into the 640x32 (here 320x16) strip.
pub fn buildStrip(ring: *const Ring) void {
    @memset(&strip, 0);
    var i: usize = 0;
    while (i < NB_LETTERS) : (i += 1) {
        const c = ring.c[i];
        if (c < panel.FIRST_CHAR or c > panel.LAST_CHAR) continue;
        blitGlyphToStrip(c, ring.x[i]);
    }
}

// FX.siny + the flat grey fill: source column i goes to (SCROLL_X + i,
// SINY_Y + sin(a)*15 + sin(b)*50), and every drawn pixel is the grey entry.
pub fn blitStrip(fb: *LogicalFB, siny_a: zg.fixtrig.Angle, siny_b: zg.fixtrig.Angle) void {
    var it = SinySweep{ .a = siny_a, .b = siny_b };
    zg.wave.siny(zg.blit.Dst.plane(fb), zg.blit.Image.init(&strip, @intCast(STRIP_W)), null, SCROLL_X, 0, 1, &it, 0, .{ .flat = panel.GREY });
}

fn blitGlyphToStrip(c: u8, x: i32) void {
    const tile: usize = c - panel.FIRST_CHAR;
    const sx0: usize = (tile % panel.FONT_COLS) * @as(usize, panel.GW);
    const sy0: usize = (tile / panel.FONT_COLS) * @as(usize, panel.GH);
    var gy: i32 = 0;
    while (gy < panel.GH) : (gy += 1) {
        var gx: i32 = 0;
        while (gx < panel.GW) : (gx += 1) {
            const dx = x + gx;
            if (dx < 0 or dx >= STRIP_W) continue;
            const si = (sy0 + @as(usize, @intCast(gy))) * panel.FONT_SHEET_W + sx0 + @as(usize, @intCast(gx));
            if (panel.font_b[si] == 0) continue;
            strip[@intCast(gy * STRIP_W + dx)] = 1;
        }
    }
}
