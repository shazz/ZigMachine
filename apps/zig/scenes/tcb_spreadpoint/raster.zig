// --------------------------------------------------------------------------
// The three rasters, as colour-register writes from the plane's HBL.
//
// The remake draws them as PIXELS: gradient.png stretched over the scroller with
// 'source-in', tcb-raster.png over the logo's inside the same way, and
// gradient_dna.png laid 'source-atop' over the DNA scroller. What those images
// carry is one colour per SCANLINE (each is constant across x, measured), so
// what the ST did was change a colour register per line. Here each layer draws
// in one fixed ink and this HBL rewrites the inks' colours line by line:
//
//   SCROLL_INK   scroll_ink[y], screen lines 0..199 (gradient.png's 200 rows)
//   LOGO_INK     logo_ink[y], lines 0..127 (tcb-raster.png: the logo canvas is
//                128 rows at the screen's top edge)
//   DNA_INK+k    the DNA font's colour k shaded by dna_shade_alpha[y - 121],
//                lines 121..170 (dna_canvas is 50 rows at screen y 121)
//
// None of the three is on colour 0, so none of them reaches the border: the
// border is the background colour, and it stays black (screen.js fills black).
//
// BUDGET. A line rewrites only the entries whose colour differs from the line
// above (line 0 reloads all five, as a VBL would). The tables change in bands of
// five or six lines, so a line needs at most MAX_WRITES of them: at 12 cycles
// a `move.w`, that is under 60 low-res pixels of the 512-cycle line.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const tables = @import("rasters.zig");
const pal = @import("palette.zig");

const LogicalFB = zg.LogicalFB;
const ZigOS = zg.ZigOS;

const LINES = zg.HEIGHT;
pub const DNA_TOP = 121; // dna_canvas.draw(main_canvas, 52, 150): 150 - 29
const DNA_ROWS = tables.dna_shade_alpha.len;
const ENTRIES = [_]u8{ pal.SCROLL_INK, pal.LOGO_INK, pal.DNA_INK, pal.DNA_INK + 1, pal.DNA_INK + 2 };

/// RGBA as the palette stores it (zg.Color.toRGBA): r in the low byte.
fn rgba(rgb: u24) u32 {
    const r: u32 = (rgb >> 16) & 0xFF;
    const g: u32 = (rgb >> 8) & 0xFF;
    const b: u32 = rgb & 0xFF;
    return 0xFF00_0000 | (b << 16) | (g << 8) | r;
}

/// 'source-atop' of `shade` at alpha a/255 over `base`, per channel, rounded.
fn shaded(base: u24, shade: u24, a: u32) u24 {
    var out: u24 = 0;
    inline for (.{ 16, 8, 0 }) |sh| {
        const c: u32 = (base >> sh) & 0xFF;
        const s: u32 = (shade >> sh) & 0xFF;
        out |= @as(u24, @intCast((c * (255 - a) + s * a + 127) / 255)) << sh;
    }
    return out;
}

/// Colour of each driven entry on each line.
fn colourAt(y: usize) [ENTRIES.len]u32 {
    const dna_row = @min(y -| DNA_TOP, DNA_ROWS - 1);
    const a: u32 = tables.dna_shade_alpha[dna_row];
    var c: [ENTRIES.len]u32 = undefined;
    c[0] = rgba(tables.scroll_ink[y]);
    c[1] = rgba(tables.logo_ink[@min(y, tables.logo_ink.len - 1)]);
    for (0..3) |k| c[2 + k] = rgba(shaded(pal.DNA_FONT[k], tables.dna_shade, a));
    return c;
}

const Line = struct { colours: [ENTRIES.len]u32, writes: u8 }; // writes: a bit per entry

/// The whole program, built at compile time: what each line writes.
pub const program: [LINES]Line = blk: {
    @setEvalBranchQuota(100_000);
    var p: [LINES]Line = undefined;
    for (0..LINES) |y| {
        const c = colourAt(y);
        var w: u8 = 0;
        for (0..ENTRIES.len) |e| {
            if (y == 0 or c[e] != p[y - 1].colours[e]) w |= 1 << e;
        }
        p[y] = .{ .colours = c, .writes = w };
    }
    break :blk p;
};

/// Most register writes any line makes (line 0, the reload, excepted).
pub const MAX_WRITES: u8 = blk: {
    var m: u8 = 0;
    for (program[1..]) |l| m = @max(m, @popCount(l.writes));
    break :blk m;
};

comptime {
    if (MAX_WRITES > 4) @compileError("a raster line writes more registers than budgeted");
}

pub fn hbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const y: usize = if (fb.hblLinesArePhysical()) @as(usize, line) -% zg.VERTICAL_BORDERS_HEIGHT else line;
    if (y >= LINES) return;
    const l = &program[y];
    inline for (ENTRIES, 0..) |e, k| {
        if (l.writes & (1 << k) != 0) fb.palette[e] = l.colours[k];
    }
}
