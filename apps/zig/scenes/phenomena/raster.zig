// --------------------------------------------------------------------------
// Colour registers: the palette, and the two entries that change per scanline
// (zg.copper, tables indexed by physical row).
//
//   BAR   the purple bars, cnvRasterBar's gradient a row each. The bar lines
//         are painted with BAR across the whole 800-pixel raster, borders
//         included, so the register is the bar, exactly as a copper bar is.
//         While a bar fades in, each line is the canvas's globalAlpha blend
//         over what is under it: black on line 64 (canvas row 129), the panel
//         on 65..69, black under the bottom bar.
//   TEXT  page 1's ink: screen.js punches the text out of a black page ('xor')
//         and slides rasterbar.png behind it, so the glyphs show the grey bar
//         line by line and are black elsewhere. Page 2's ink is one grey.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const G = @import("geom.zig");
const A = @import("assets.zig");

const SLOT_BAR: zg.copper.Slot = 0;
const SLOT_TEXT: zg.copper.Slot = 1;
var tables: [2]zg.copper.Table = undefined; // module scope: the scene owns the tables

const BLACK: A.Rgb = .{ 0, 0, 0 };
const WHITE: A.Rgb = .{ 255, 255, 255 };

inline fn set(fb: *zg.LogicalFB, i: usize, c: A.Rgb) void {
    const w = A.word(c);
    if (fb.palette[i] != w) fb.palette[i] = w;
}

/// The whole palette, then the copper on BAR and TEXT (seeded black).
pub fn install(fb: *zg.LogicalFB) void {
    for (0..256) |i| set(fb, i, BLACK);
    logoNormal(fb);
    set(fb, G.PANEL, A.rgb(A.PANEL_RGB, 0));
    set(fb, G.PHOTON, WHITE);
    for (0..G.STRIP_ROWS) |r| {
        set(fb, G.SILVER + r, A.rgb(A.SILVER_ROWS, r));
        set(fb, G.PURPLE + r, A.rgb(A.PURPLE_ROWS, r));
    }
    for (0..G.RED_ROWS) |r| set(fb, G.RED + r, A.rgb(A.RED_ROWS, r));
    zg.copper.install(fb, &.{ G.BAR, G.TEXT }, &tables, .{});
}

// --- logo ------------------------------------------------------------------
pub fn logoNormal(fb: *zg.LogicalFB) void {
    for (0..G.LOGO_N) |i| set(fb, G.LOGO + i, A.logoRgb(i));
}

/// showLogo's first half: the logo's silhouette in hsl(0 0% p%).
pub fn logoGrey(fb: *zg.LogicalFB, p: u32) void {
    const c = A.rgb(A.GREY, p);
    for (0..G.LOGO_N) |i| set(fb, G.LOGO + i, c);
}

/// ...its second half: the white silhouette at alpha a/100 over the logo.
pub fn logoWhite(fb: *zg.LogicalFB, a: u32) void {
    for (0..G.LOGO_N) |i| set(fb, G.LOGO + i, A.blend(WHITE, A.logoRgb(i), a));
}

pub fn photon(fb: *zg.LogicalFB, c: A.Rgb) void {
    set(fb, G.PHOTON, c);
}

// --- per-line registers ----------------------------------------------------
inline fn row(slot: zg.copper.Slot, fb: *zg.LogicalFB, phys: usize, c: A.Rgb) void {
    zg.copper.table(fb, slot)[phys] = A.word(c);
}

/// The two bars, each at alpha a/100 (100 = drawn plain, 0 = not yet).
pub fn bars(fb: *zg.LogicalFB, a_top: u32, a_bottom: u32) void {
    const panel = A.rgb(A.PANEL_RGB, 0);
    for (0..G.BAR_LINES) |j| {
        const bg = if (j == 0) BLACK else panel;
        row(SLOT_BAR, fb, G.CY + G.BAR_TOP + j, A.blend(A.rgb(A.BAR_ROWS, 2 * j), bg, a_top));
        row(SLOT_BAR, fb, G.CY + G.BAR_BOTTOM + j, A.blend(A.rgb(A.BAR_ROWS, 2 * j + 1), BLACK, a_bottom));
    }
}

/// Page 1: rasterbar.png drawn at y = rb2/2 (rb2 = 2 * rasterbarY), smoothing
/// off, so canvas row Y shows its row ceil(Y + 0.5 - y) - 1 (tables.zig,
/// NEAREST) = floor((2Y - rb2) / 2).
pub fn textBar(fb: *zg.LogicalFB, rb2: i32) void {
    const t = zg.copper.table(fb, SLOT_TEXT);
    for (0..G.ROWS) |phys| {
        var c: u32 = A.word(BLACK);
        if (phys >= G.CY and phys < G.CY + G.H) {
            const y = G.canvasRow(phys - G.CY);
            const src = @divFloor(2 * y - rb2, 2);
            if (src >= 0 and src < A.bar_intro.len) {
                const v = A.bar_intro[@intCast(src)];
                c = A.word(.{ v, v, v });
            }
        }
        if (t[phys] != c) t[phys] = c;
    }
}

/// Page 2: one ink on every line.
pub fn textFlat(fb: *zg.LogicalFB, c: A.Rgb) void {
    const w = A.word(c);
    const t = zg.copper.table(fb, SLOT_TEXT);
    for (t) |*v| {
        if (v.* != w) v.* = w;
    }
}
