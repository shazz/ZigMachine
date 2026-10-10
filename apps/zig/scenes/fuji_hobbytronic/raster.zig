// --------------------------------------------------------------------------
// FUJI HOBBYTRONIC: the rasters. REAL ones: colour registers rewritten per
// scanline from the plane's HBL handler, never colour bars drawn as pixels.
//
// The Fuji's front cap is filled with ONE palette index (FRONT) and its back cap
// with another (BACK); this handler gives each a new colour on every line, so
// the copper bars run down through the logo wherever it turns, exactly like an
// 8-bit or ST logo raster: the logo's pixels never change colour index, only
// the register behind them does. The scroller's ink (SCROLL) gets a fixed gold
// ramp on its own eight lines.
//
// THE BUDGET. On an ST one `move.w Dn,(abs).w` to a colour register is 12
// cycles = 12 low-res pixels of the 512-cycle line, and a raster coder never
// rewrites a register that already holds the right colour. So the handler
// writes only CHANGES: at most two a line inside the logo's band (FRONT and
// BACK, 24 cycles) and one a line in the scroller's band, where the logo
// cannot reach. Each ramp holds its peak for two lines, so some lines need one.
//
// THE COLOURS are ST-legal: every channel is a 3-bit nibble x 32 (0..224).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const FRONT: u8 = 4;
pub const BACK: u8 = 5;
pub const SCROLL: u8 = 14;
/// First logical line of the scroller's band; the logo's band is above it.
pub const SCROLL_Y: u16 = 184;

/// An ST colour register, nibbles 0..7, as the plane's RGBA word.
pub fn st(r: u32, g: u32, b: u32) u32 {
    return 0xFF00_0000 | (b * 32) << 16 | (g * 32) << 8 | (r * 32);
}

const BAR = 16; // lines per copper bar
const BARS = 8;
pub const LEN = BAR * BARS; // 128: a power of two, so the offset may wrap freely

// Brightness down one bar: up, a two-line peak, down, one dark line.
const RAMP = [BAR]u32{ 1, 2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 3, 2, 1, 1, 0 };
// The Atari rainbow's hues, as channel weights 0..2 (2 = full).
const HUES = [BARS][3]u32{
    .{ 2, 0, 0 }, .{ 2, 1, 0 }, .{ 2, 2, 0 }, .{ 0, 2, 0 },
    .{ 0, 2, 2 }, .{ 1, 1, 2 }, .{ 1, 0, 2 }, .{ 2, 0, 2 },
};

fn bars(comptime dim: u5) [LEN]u32 {
    @setEvalBranchQuota(10_000);
    var t: [LEN]u32 = undefined;
    for (&t, 0..) |*c, i| {
        const lvl = RAMP[i % BAR];
        const h = HUES[i / BAR];
        var n: [3]u32 = undefined;
        // The peak lines get a white sheen on the channels the hue lacks.
        for (0..3) |k| {
            const full: u32 = @min(7, (lvl * h[k] + 1) / 2 + (if (lvl == 7) 2 else 0));
            n[k] = full >> dim;
        }
        c.* = st(n[0], n[1], n[2]);
    }
    return t;
}

pub const FRONT_TAB = bars(0);
pub const BACK_TAB = bars(1); // the same bars at half strength, run the other way

pub const SCROLL_TAB = [8]u32{
    st(7, 7, 5), st(7, 7, 3), st(7, 6, 1), st(7, 5, 0),
    st(7, 4, 0), st(6, 3, 0), st(5, 2, 0), st(4, 1, 0),
};

/// Advanced each frame by the scene: the bars roll down the front cap and up
/// the back one.
pub var offset: u32 = 0;

inline fn set(fb: *zg.LogicalFB, entry: u8, rgba: u32) void {
    if (fb.palette[entry] == rgba) return; // a change, or nothing
    fb.palette[entry] = rgba;
}

pub fn handler(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    if (line >= SCROLL_Y) {
        set(fb, SCROLL, SCROLL_TAB[(line - SCROLL_Y) & 7]);
        return;
    }
    set(fb, FRONT, FRONT_TAB[(line +% offset) % LEN]);
    set(fb, BACK, BACK_TAB[(@as(u32, line) -% offset) % LEN]);
}

comptime {
    @setEvalBranchQuota(10_000);
    for (FRONT_TAB ++ BACK_TAB ++ SCROLL_TAB) |c| {
        for (0..3) |k| {
            const ch = (c >> (8 * k)) & 0xFF;
            if (ch % 32 != 0 or ch > 224) @compileError("a raster colour off the ST's 3-bit grid");
        }
    }
}
