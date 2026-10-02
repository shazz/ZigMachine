// The ST's screen as this cart shows it: one overscan plane of 400x280 palette
// indices 0..15 (the four bitplanes of a low-res pixel), and the SIXTEEN COLOUR
// REGISTERS AS THEY STAND ON EVERY PHYSICAL LINE. The plane's HBL loads that
// line's sixteen into palette entries 0..15, so a raster here is what it was on
// the ST -- a colour register rewritten between two lines -- and, the border
// being colour 0 on an ST, it runs edge to edge: the handler also flickers the
// resolution on every line, so the plane's own pixels (index 0) are the border.
//
// ST line y is physical row y + 40, pixel x is physical x + 40 (OX, OY).
const zg = @import("zigos");

const LogicalFB = zg.LogicalFB;
const ZigOS = zg.ZigOS;

pub const PW: usize = zg.PHYSICAL_WIDTH; // 400
pub const PH: usize = zg.PHYSICAL_HEIGHT; // 280
pub const OX: usize = zg.HORIZONTAL_BORDERS_WIDTH; // 40
pub const OY: usize = zg.VERTICAL_BORDERS_HEIGHT; // 40
pub const W: usize = 320;
pub const H: usize = 200;

/// Colour registers 0..15 on each physical line, as palette RGBA.
pub var regs: [PH][16]u32 = undefined;

pub fn init(zigos: *ZigOS) *LogicalFB {
    const fb = &zigos.lfbs[0];
    fb.setOverscanBuffer();
    fb.is_enabled = true;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
    zigos.setBackgroundColor(zg.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    for (&regs) |*line| @memset(line, BLACK);
    return fb;
}

fn hbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    fb.flickerBorder();
    if (line >= PH) return;
    @memcpy(fb.palette[0..16], &regs[line]);
}

pub const BLACK: u32 = 0xFF00_0000;

/// An ST colour word ($0RGB, 3 bits a gun) as palette RGBA.
pub fn color(w: u16) u32 {
    const r: u32 = (w >> 8) & 7;
    const g: u32 = (w >> 4) & 7;
    const b: u32 = w & 7;
    return 0xFF00_0000 | (b * 255 / 7) << 16 | (g * 255 / 7) << 8 | (r * 255 / 7);
}

/// The whole frame under one palette (what a VBL's palette load does).
pub fn setPalette(words: *const [16]u16) void {
    var line: [16]u32 = undefined;
    for (&line, words) |*c, w| c.* = color(w);
    for (&regs) |*r| r.* = line;
}

/// All sixteen registers loaded on ST line `y`, held to the end of the frame.
pub fn setPaletteFrom(y: usize, words: *const [16]u16) void {
    var line: [16]u32 = undefined;
    for (&line, words) |*c, w| c.* = color(w);
    for (regs[y + OY ..]) |*r| r.* = line;
}

/// Register `reg` holds `w` from ST line `y` down to the end of the frame, as a
/// Timer B write does until the next VBL reloads the palette.
pub fn setFrom(y: usize, reg: usize, w: u16) void {
    const c = color(w);
    for (regs[y + OY ..]) |*r| r[reg] = c;
}

/// Register `reg` holds `w` on ST line `y` only (a Timer B write the next
/// line's overwrites).
pub fn set(y: usize, reg: usize, w: u16) void {
    regs[y + OY][reg] = color(w);
}

/// The pixel row of ST line `y` (y may run into the lower border, up to 239).
pub fn row(fb: *LogicalFB, y: usize) *[W]u8 {
    return fb.fb[(y + OY) * PW + OX ..][0..W];
}

/// Lines from..from+n of a 320x200 picture (palette indices) to screen lines
/// to.., as the movem copies do; nothing past line 199 of either.
pub fn copyRows(fb: *LogicalFB, pic: *const [W * H]u8, from: usize, to: usize, n: usize) void {
    for (0..n) |i| {
        if (from + i >= H or to + i >= H) break;
        @memcpy(row(fb, to + i), pic[(from + i) * W ..][0..W]);
    }
}

pub fn clear(fb: *LogicalFB) void {
    @memset(fb.fb[0 .. PW * PH], 0);
}

/// Sixteen pixels' worth of one bitplane word: OR bit `plane` into each pixel
/// whose bit is set (bit 15 = leftmost), clipped to the 320-pixel line.
pub fn orWord(px: *[W]u8, x: i32, word: u16, plane: u3) void {
    if (word == 0) return;
    const bit = @as(u8, 1) << plane;
    for (0..16) |i| {
        const xx = x + @as(i32, @intCast(i));
        if (xx < 0 or xx >= W) continue;
        if ((word >> @intCast(15 - i)) & 1 != 0) px[@intCast(xx)] |= bit;
    }
}
