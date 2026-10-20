// --------------------------------------------------------------------------
// The raster bars, done the ST way: colour registers changed per scanline,
// nothing in the framebuffer.  Every row of the remake's rasterbar.png is one
// solid grey (asserted by the ripper), and its two 12-row purple "gradient"
// images are row gradients too, so all of them are tables here.
//
//   index 1  the bar: the opening greys (40 rows) or the purple frame bar
//            (rows 65..70 and 215..220 of the content)
//   index 15 the DNA red core -- except on the photon's eight lines, where it
//            is the live HSL colour (the photon sits below the DNA, so one
//            register can serve both)
//
// Like every overscan port here, the HBL also flickers EVERY line so the sides
// open and a bar runs edge to edge (the 400-column plane is filled with index
// 1 on those rows).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

pub const Mode = enum { off, intro, main };

pub var mode: Mode = .off;
/// The opening raster's top row, content 1x Q16.16 (starts above the screen).
pub var intro_y: i32 = -20 << 16;
pub var alpha_top: u8 = 100;
pub var alpha_bottom: u8 = 100;
/// The DNA is on screen: index 15 is red except on the photon's lines.
pub var dna: bool = false;
/// A photon is on screen: index 15 is its colour (all lines when no DNA).
pub var photon: bool = false;
pub var photon_rgb: [3]u8 = .{ 224, 224, 224 };

/// The photon mask's content rows 222..229 (main.go draws it at 445/2).
const PHOTON_LINE0: u16 = @as(u16, @intCast(A.CONTENT_Y + A.PHOTON_Y));
const PHOTON_LINE1: u16 = PHOTON_LINE0 + @as(u16, @intCast(A.PHOTON_H));

pub fn install(fb: *zg.LogicalFB) void {
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    fb.flickerBorder();
    fb.palette[A.IDX_BAR] = bar(line);
    fb.palette[A.IDX_RED] = red(line);
}

/// Snap an alpha-scaled channel to the ST's eight 3-bit levels.
inline fn scale3(c: u8, alpha: u8) u8 {
    const v: u32 = (@as(u32, c) * alpha) / 100;
    const lvl: u32 = @min(@as(u32, 7), (v + 16) / 32);
    return @intCast(lvl * 32);
}

fn alphaRGB(c: [3]u8, alpha: u8) u32 {
    return A.rgb(scale3(c[0], alpha), scale3(c[1], alpha), scale3(c[2], alpha));
}

fn bar(line: u16) u32 {
    const content_y: u16 = @intCast(A.CONTENT_Y);
    const content_h: u16 = @intCast(A.CONTENT_H);
    switch (mode) {
        .off => return A.rgb(0, 0, 0),
        .intro => {
            if (line < content_y or line >= content_y + content_h) return A.rgb(0, 0, 0);
            const y: i32 = @as(i32, line) - @as(i32, content_y);
            const d = y - (intro_y >> 16);
            if (d < 0 or d >= @as(i32, @intCast(A.BAR_INTRO_H))) return A.rgb(0, 0, 0);
            return A.introGrey(@intCast(d));
        },
        .main => {
            const top0: u16 = @intCast(A.CONTENT_Y + A.BAR_TOP_Y);
            if (line >= top0 and line < top0 + A.BAR_ROWS) {
                const r = 2 * (line - top0) + 1;
                return alphaRGB(A.mainBarRGB(r), alpha_top);
            }
            const bot0: u16 = @intCast(A.CONTENT_Y + A.BAR_BOTTOM_Y);
            if (line >= bot0 and line < bot0 + A.BAR_ROWS) {
                const r = 2 * (line - bot0) + 1;
                return alphaRGB(A.mainBarRGB(r), alpha_bottom);
            }
            return A.rgb(0, 0, 0);
        },
    }
}

fn red(line: u16) u32 {
    if (dna) {
        // The DNA core is red; the photon's own rows take the live colour.
        if (line >= PHOTON_LINE0 and line < PHOTON_LINE1) return A.rgb3(photon_rgb);
        return A.rgb(224, 64, 0);
    }
    if (photon) return A.rgb3(photon_rgb);
    return A.rgb(224, 64, 0);
}
