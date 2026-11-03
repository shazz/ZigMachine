// --------------------------------------------------------------------------
// "SDL" — the boot sector of the C ports' data disks (pt2-clone, GrafX2,
// klystrack, ChipNomad), celebrating SDL2 running on a fantasy ST.
// --------------------------------------------------------------------------
// Giant S D L letters whose ink is a REAL raster: palette entry 3 rewritten on
// every line by the plane's copper list (HW 1.9.0, machine/copper.zig, one PALREF
// a line into a 256-colour rainbow table), scrolled by rotating the table
// itself — no pixel is ever recoloured. Around them, a gang of GEM mouse
// pointers bounces off the screen edges like an idle DVD player: every one of
// these programs is driven by the mouse.
//
// A bare wasm boot program like apps/zig/boot/novirus.zig: NO ZigOS, NO ROM, it
// pokes the sealed video ABI directly and must fit the 1 KB sector (mkdisk.py
// takes at most 1015 B of wasm). Integer maths only. The host runs it through the
// render loop and boots GEM (a data disk names no cart) when pollCartRequest()
// returns 2.
// --------------------------------------------------------------------------
const hw = @import("hardware"); // sealed video ABI header (offsets only, no code)

extern fn hwVideoBase() i32;

const HOLD_FRAMES: u32 = 300; // 5 s at 60 fps
const CHAINLOAD: i32 = 2; // pollCartRequest(): "go on" (GEM, on a data disk)
const W: u32 = hw.WIDTH; // 320
const H: u32 = hw.HEIGHT; // 200
const TOP: u32 = 40; // the plane's first physical row: copper HEADs are physical rows

const INK: u32 = 3; // the letters' palette entry, driven by the copper
const LIST: u32 = hw.OFF_VRAM + 0x10000; // the copper list (plane 1's unused VRAM)
const TABLE: u32 = LIST + 0x1000; // 256 rainbow colours the PALREFs point into
const SCALE: u32 = 12; // letter pixel = 12x12 px
const MICE: u32 = 7;

var t: u32 = 0;
var base: u32 = 0; // the video region, asked once

// `b` is the video base held in a LOCAL: through a volatile store the global would be
// reloaded before every write (9 B each), which the 1 KB sector cannot afford.
inline fn reg(b: u32, off: u32) *volatile u32 {
    return @ptrFromInt(b + off);
}

// S, D, L: 4 columns x 7 rows, bit 3 = leftmost.
const GLYPHS = [3][7]u8{
    .{ 0x7, 0x8, 0x8, 0x6, 0x1, 0x1, 0xE },
    .{ 0xE, 0x9, 0x9, 0x9, 0x9, 0x9, 0xE },
    .{ 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0xF },
};

/// A triangle wave in 0..len: a pointer bouncing between two walls.
noinline fn bounce(v: u32, len: u32) u32 { // noinline: six call sites, 1 KB budget
    const p = v % (2 * len);
    return if (p < len) p else 2 * len - p;
}

/// A rainbow from three phase-shifted triangle waves: i in 0..255, integer only.
fn hue(i: u32) u32 {
    return 0xFF000000 | bounce(6 * i + 340, 255) << 16 | bounce(6 * i + 170, 255) << 8 | bounce(6 * i, 255);
}

export fn boot() void {
    t = 0;
    const b: u32 = @bitCast(hwVideoBase());
    base = b;
    reg(b, hw.REG_BACKGROUND).* = 0xFF000000;
    reg(b, hw.OFF_PAL).* = 0xFF000000; // paper (the compositor paints every pixel)
    reg(b, hw.OFF_PAL + 4).* = 0xFFFFFFFF; // the pointers' white (their outline is the paper)
    // Per visible row: HEAD(row, 2 words), PALREF(entry 3, 1 colour), its fixed table pointer.
    var i: u32 = 0;
    while (i < H) : (i += 1) {
        reg(b, LIST + 12 * i).* = 0xF000_0000 | (TOP + i) << 19 | 2;
        reg(b, LIST + 12 * i + 4).* = 0x4000_0000 | INK << 20 | 1 << 12;
        reg(b, LIST + 12 * i + 8).* = TABLE + 4 * (2 * i & 255);
    }
    // No END record: the plane covers no line after 239, so whatever follows is never read.
    @as(*volatile u16, @ptrCast(reg(b, hw.REG_FB_COPPER))).* = (LIST - hw.OFF_VRAM) / 16;
}

// The three letters as one 14-bit row each (4 px, a 1 px gap, 4, gap, 4), built at compile time.
const ROWS = blk: {
    var r: [7]u16 = undefined;
    for (0..7) |y| r[y] = @as(u16, GLYPHS[0][y]) << 10 | @as(u16, GLYPHS[1][y]) << 5 | GLYPHS[2][y];
    break :blk r;
};

fn drawLetters(p: [*]u8) void { // the S D L, wobbling
    const x0 = (W - 14 * SCALE) / 2 - 8;
    const y0 = (H - 7 * SCALE) / 2;
    var y: u32 = 0;
    while (y < 7 * SCALE) : (y += 1) {
        const wob = bounce(4 * t + y, 64) / 4; // jelly: a quarter pixel a line, 16 px of swing
        var x: u32 = 0;
        while (x < 14 * SCALE) : (x += 1) {
            if (ROWS[y / SCALE] >> @intCast(13 - x / SCALE) & 1 != 0) p[(y0 + y) * W + x0 + x + wob] = INK;
        }
    }
}

/// A mouse pointer: a 10-row arrowhead, white inside an edge of paper, drawn by formula (no bitmap).
fn drawMouse(p: [*]u8, x: u32, y: u32) void {
    var r: u32 = 0;
    while (r < 10) : (r += 1) {
        const w = if (r < 7) r else 9 - r; // widens to 6, then the tail tucks in
        var c: u32 = 0;
        while (c <= w) : (c += 1) p[(y + r) * W + x + c] = @intFromBool(c != 0 and c != w and r != 9);
    }
}

export fn frame(dt: f32) void {
    _ = dt;
    t +%= 1;
    const b = base;
    const p: [*]u8 = @ptrFromInt(b + reg(b, hw.REG_FB_BASE).*);
    @memset(p[0 .. W * H], 0);
    drawLetters(p);
    var k: u32 = 0;
    while (k < MICE) : (k += 1) drawMouse(p, bounce(t * (k + 2) + k * 97, W - 8), bounce(t * (k / 2 + 1) + k * 53, H - 12));
    // Scroll the rainbow: the lines keep their table slots, the table's colours move on.
    var i: u32 = 0;
    while (i < 256) : (i += 1) reg(b, TABLE + 4 * i).* = hue(i + 3 * t);
}

export fn isPlaneEnabled(plane: i32) i32 {
    return @intFromBool(plane == 0);
}

export fn pollCartRequest() i32 {
    return if (t >= HOLD_FRAMES) CHAINLOAD else 0;
}
