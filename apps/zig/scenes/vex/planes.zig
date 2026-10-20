// --------------------------------------------------------------------------
// The four layers, kept as the ST kept them: 1-bit-per-pixel rows of 16-px
// words.  On the real machine they were bitplanes of one 320x200 screen —
// planes 0+1 the cubes, plane 2 the credits page and the small scroller,
// plane 3 the big scroller — and the blit code below writes exactly the words
// the 68000 wrote.  vex.zig collapses them into palette indices at the end of
// the frame, which is what the ST's 16 colours amounted to (colours 4..7 were
// always one value, and 8..15 another).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const WORDS: usize = 20; // 320 px
pub const ROWS: usize = 200;

// The plane is an OVERSCAN plane (vex.zig's init) whose borders stay closed
// unless ZIG MODE opens the sides (zig_mode.zig): closed, it shows exactly the
// 320x200 window a normal plane would.  It is 26 words wide rather than the
// 400-px raster so every word stays on a 16-px boundary: the hardware pan of
// SCROLL_X puts the visible left edge at buffer px 8, the window at 48..367
// (words 3..22), and the right border ends at 407, inside word 25.  The two
// scroller layers are kept that wide too, so their border words always exist.
pub const BUF_WORDS: usize = 26;
pub const BUF_W: u16 = BUF_WORDS * 16;
pub const WIN_WORD: usize = 3; // the window's first word
pub const ORG_X: usize = WIN_WORD * 16; // the window's top-left in the buffer
pub const ORG_Y: usize = zg.VERTICAL_BORDERS_HEIGHT;
pub const SCROLL_X: u32 = ORG_X - zg.HORIZONTAL_BORDERS_WIDTH; // 8: buffer px of the raster's left edge

/// The credits page block: $340c blits 120 lines to screen offset $2444.
pub const CREDIT_TOP: usize = 58;
pub const CREDIT_ROWS: usize = 120;
/// $3306 blits the small scroller to screen offset $7760 + 4.
pub const SMALL_TOP: usize = 191;
pub const SMALL_ROWS: usize = 8;

/// The band vex.zig recomposes every frame: everything that moves lives in it.
pub const LIVE_TOP: usize = CREDIT_TOP;
pub const LIVE_ROWS: usize = CREDIT_ROWS;

pub var cube_lo: *[ROWS][WORDS]u16 = undefined;
pub var cube_hi: *[ROWS][WORDS]u16 = undefined;
pub var scroll: *[ROWS][BUF_WORDS]u16 = undefined;
pub var credits: *[CREDIT_ROWS][WORDS]u16 = undefined;
pub var small: *[SMALL_ROWS][BUF_WORDS]u16 = undefined;
var owned = false;

/// The layers come from the RAM arena (zg.mem), once per cart load: as
/// module-scope arrays they were 29 KB of zeros written into the cart binary,
/// since imported memory is not known to be zero. Call before clear().
pub fn alloc() void {
    if (owned) return;
    cube_lo = zg.mem.mustAlloc([WORDS]u16, ROWS)[0..ROWS];
    cube_hi = zg.mem.mustAlloc([WORDS]u16, ROWS)[0..ROWS];
    scroll = zg.mem.mustAlloc([BUF_WORDS]u16, ROWS)[0..ROWS];
    credits = zg.mem.mustAlloc([WORDS]u16, CREDIT_ROWS)[0..CREDIT_ROWS];
    small = zg.mem.mustAlloc([BUF_WORDS]u16, SMALL_ROWS)[0..SMALL_ROWS];
    owned = true;
}

/// The plane from the window's top-left on: index it `y * stride + x` with the
/// window's own (x, y), as a normal 320x200 plane would be indexed.
pub fn window(fb: *const zg.LogicalFB) []u8 {
    const all = @as(usize, fb.stride) * fb.fb_h;
    return fb.fb[ORG_Y * @as(usize, fb.stride) + ORG_X .. all];
}

pub fn clear() void {
    for (cube_lo) |*r| @memset(r, 0);
    for (cube_hi) |*r| @memset(r, 0);
    for (scroll) |*r| @memset(r, 0);
    for (credits) |*r| @memset(r, 0);
    for (small) |*r| @memset(r, 0);
}

// --------------------------------------------------------------------------
// The flatten: the four layers collapsed into the one plane's palette indices,
// the inverse of the blits above.  It runs over the band that moves plus the
// small scroller's eight rows -- the rest of the screen is painted once.
// --------------------------------------------------------------------------

/// The palette entries the Timer-B chain drives (vex.zig installs them per row
/// from an HBL).  0..15 stay the logo's own palette; nothing below row 46 uses
/// them.  A cube pixel of 0 is transparent, which is why BG == CUBE0 - 1.
pub const BG: u8 = 16;
pub const CUBE0: u8 = 17; // ..19, the three cube shades
pub const PANEL_INK: u8 = 20;
pub const SCROLL_INK: u8 = 21;
pub const DRIVEN: usize = 6; // entries 16..21
/// The open side borders' background (ZIG MODE): the border's own colour per
/// line, which is not always BG's (raster.side_bg says why).
pub const SIDE_BG: u8 = BG + DRIVEN;

/// One 16-pixel word, in the ST's plane order: scroller over panel over cubes.
fn bandWord(out: *[16]u8, s: u16, c: u16, lo: u16, hi: u16) void {
    // Most of the band is empty every frame; an empty word is 16 x BG.
    if ((s | c | lo | hi) == 0) return @memset(out, BG);
    for (out, 0..) |*px, k| {
        const bit: u4 = @intCast(15 - k);
        const m = @as(u16, 1) << bit;
        px.* = if (s & m != 0) SCROLL_INK else if (c & m != 0) PANEL_INK else CUBE0 - 1 +
            @as(u8, @intCast(((lo >> bit) & 1) | (((hi >> bit) & 1) << 1)));
    }
}

/// EXPAND[n]: the four bits of nibble n as four byte lanes holding 0 or 1, the
/// leftmost pixel (the nibble's top bit) in the lowest byte. Built at compile
/// time; it is what lets four pixels be composed with u32 maths.
const EXPAND: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (&t, 0..) |*e, n| {
        var v: u32 = 0;
        for (0..4) |m| v |= @as(u32, (n >> (3 - m)) & 1) << (8 * m);
        e.* = v;
    }
    break :blk t;
};
const BG4: u32 = @as(u32, BG) * 0x01010101;
const CUBE_BASE4: u32 = @as(u32, CUBE0 - 1) * 0x01010101;
const PANEL4: u32 = @as(u32, PANEL_INK) * 0x01010101;
const SCROLL4: u32 = @as(u32, SCROLL_INK) * 0x01010101;

/// bandWord() four pixels at a time: the same priority (scroller over panel
/// over cube shade), done as byte-lane select masks on a u32 (the byte loop
/// did ~16 shifts, tests and a store per pixel; this is 4 stores a word).
fn bandWord4(out: *align(4) [16]u8, s: u16, c: u16, lo: u16, hi: u16) void {
    const dst: *[4]u32 = @ptrCast(out);
    if ((s | c | lo | hi) == 0) {
        dst.* = .{ BG4, BG4, BG4, BG4 };
        return;
    }
    inline for (0..4) |j| {
        const sh = 12 - 4 * j;
        const cube = CUBE_BASE4 + EXPAND[(lo >> sh) & 15] + (EXPAND[(hi >> sh) & 15] << 1);
        const cm = EXPAND[(c >> sh) & 15] * 255;
        const sm = EXPAND[(s >> sh) & 15] * 255;
        const panel = (cube & ~cm) | (PANEL4 & cm);
        dst[j] = (panel & ~sm) | (SCROLL4 & sm);
    }
}

/// One 16-px word of a single layer's ink over SIDE_BG: the scrollers' words
/// in the open side borders, where neither the cubes nor the panel reach.
pub fn inkWord(out: []u8, bits: u16, ink: u8) void {
    if (@intFromPtr(out.ptr) & 3 == 0) {
        const dst: *[4]u32 = @ptrCast(@alignCast(out[0..16]));
        const ink4 = @as(u32, ink) * 0x01010101;
        const bg4 = @as(u32, SIDE_BG) * 0x01010101;
        inline for (0..4) |j| {
            const m = EXPAND[(bits >> (12 - 4 * j)) & 15] * 255;
            dst[j] = (bg4 & ~m) | (ink4 & m);
        }
        return;
    }
    for (out[0..16], 0..) |*px, k| {
        const m = @as(u16, 1) << @as(u4, @intCast(15 - k));
        px.* = if (bits & m != 0) ink else SIDE_BG;
    }
}

/// The band that moves: cubes, credits panel and big scroller. `fb` is the
/// whole buffer; the band is drawn into the window.
pub fn composeBand(fb: []u8, stride: usize) void {
    const wide = @intFromPtr(fb.ptr) & 3 == 0 and stride & 3 == 0;
    for (0..LIVE_ROWS) |r| {
        const row = fb[(ORG_Y + LIVE_TOP + r) * stride + ORG_X ..][0 .. WORDS * 16];
        const win = scroll[LIVE_TOP + r][WIN_WORD..][0..WORDS];
        for (win, &credits[r], &cube_lo[LIVE_TOP + r], &cube_hi[LIVE_TOP + r], 0..) |s, c, lo, hi, g| {
            const out = row[g * 16 ..][0..16];
            if (wide) bandWord4(@alignCast(out), s, c, lo, hi) else bandWord(out, s, c, lo, hi);
        }
    }
}

/// Metallinos' eight rows, plane 2 only.
pub fn composeSmall(fb: []u8, stride: usize) void {
    for (small, 0..) |*bits, r| {
        const row = fb[(ORG_Y + SMALL_TOP + r) * stride + ORG_X ..][0 .. WORDS * 16];
        for (bits[WIN_WORD..][0..WORDS], 0..) |w, g| {
            const out = row[g * 16 ..][0..16];
            if (w == 0) {
                @memset(out, BG);
                continue;
            }
            for (out, 0..) |*px, k| {
                const m = @as(u16, 1) << @as(u4, @intCast(15 - k));
                px.* = if (w & m != 0) PANEL_INK else BG;
            }
        }
    }
}

comptime {
    if (SCROLL_X + zg.PHYSICAL_WIDTH > BUF_W) @compileError("the right border runs past the buffer");
    if (ORG_X < zg.HORIZONTAL_BORDERS_WIDTH) @compileError("the left border starts before the buffer");
    if (SMALL_TOP + SMALL_ROWS > ROWS) @compileError("the small scroller runs off the plane");
    if (LIVE_TOP + LIVE_ROWS > ROWS) @compileError("the recomposed band runs off the plane");
}
