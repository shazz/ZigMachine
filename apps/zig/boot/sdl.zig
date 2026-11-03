// --------------------------------------------------------------------------
// "SDL" — the boot sector of the C ports' data disks (pt2-clone, GrafX2,
// klystrack, ChipNomad), celebrating SDL2 running on a fantasy ST.
// --------------------------------------------------------------------------
// Giant S D L letters whose ink is a REAL raster: palette entry 2 rewritten on
// every line by the plane's copper list (HW 1.9.0, machine/copper.zig, one PALREF
// a line into a 256-colour rainbow table), and wobbling like jelly through each
// line's LBASE record (HW 1.10.0, the STE video counter).
//
// On the board a boot sector runs in a wasm INTERPRETER (fpga/cycles/bbootsec.c),
// so a frame must touch almost nothing: the letters and the rainbow table are made
// once in boot(); a frame rewrites two copper words a line and no pixel. (The first
// version redrew 64,000 px a frame plus seven bouncing GEM pointers: 1 fps on the
// board. Drawn incrementally the pointers no longer fit the 1 KB sector: dropped.)
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

const INK: u32 = 2; // the letters' palette entry, driven by the copper
const LIST: u32 = hw.OFF_VRAM + 0x10000; // the copper list (plane 1's unused VRAM), 16 B a line
const TABLE: u32 = LIST + 0x1000; // 256 rainbow colours the PALREFs point into
const SCALE: u32 = 12; // letter pixel = 12x12 px
const X0: u32 = (W - 14 * SCALE) / 2 - 8;
const Y0: u32 = (H - 7 * SCALE) / 2;

var t: u32 = 0;
var base: u32 = 0; // the video region, asked once
var fb: u32 = 0; // the plane's pixels, a region offset

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

// The three letters as one 14-bit row each (4 px, a 1 px gap, 4, gap, 4), built at compile time.
const ROWS = blk: {
    var r: [7]u16 = undefined;
    for (0..7) |y| r[y] = @as(u16, GLYPHS[0][y]) << 10 | @as(u16, GLYPHS[1][y]) << 5 | GLYPHS[2][y];
    break :blk r;
};

/// A triangle wave in 0..len.
noinline fn bounce(v: u32, len: u32) u32 { // noinline: four call sites, 1 KB budget
    const p = v % (2 * len);
    return if (p < len) p else 2 * len - p;
}

export fn boot() void {
    t = 0;
    const b: u32 = @bitCast(hwVideoBase());
    base = b;
    fb = reg(b, hw.REG_FB_BASE).*;
    reg(b, hw.REG_BACKGROUND).* = 0xFF000000;
    reg(b, hw.OFF_PAL).* = 0xFF000000; // paper (the compositor paints every pixel)
    // The rainbow, once: three phase-shifted triangle waves.
    var i: u32 = 0;
    while (i < 256) : (i += 1)
        reg(b, TABLE + 4 * i).* = 0xFF000000 | bounce(6 * i + 340, 255) << 16 | bounce(6 * i + 170, 255) << 8 | bounce(6 * i, 255);
    // Per visible row: HEAD(row, 3 words), LBASE, PALREF(the ink), its table slot; frame() writes
    // the LBASE and the slot before the list is first read.
    i = 0;
    while (i < H) : (i += 1) {
        reg(b, LIST + 16 * i).* = 0xF000_0000 | (TOP + i) << 19 | 3;
        reg(b, LIST + 16 * i + 8).* = 0x4000_0000 | INK << 20 | 1 << 12;
    }
    // No END record: the plane covers no line after 239, so whatever follows is never read.
    @as(*volatile u16, @ptrCast(reg(b, hw.REG_FB_COPPER))).* = (LIST - hw.OFF_VRAM) / 16;
    // The letters, once (the copper moves them).
    const p: [*]u8 = @ptrFromInt(b + fb);
    @memset(p[0 .. W * H], 0);
    var y: u32 = 0;
    while (y < 7 * SCALE) : (y += 1) {
        var x: u32 = 0;
        while (x < 14 * SCALE) : (x += 1) {
            if (ROWS[y / SCALE] >> @intCast(13 - x / SCALE) & 1 != 0) p[(Y0 + y) * W + X0 + x] = INK;
        }
    }
}

export fn frame(dt: f32) void {
    _ = dt;
    const b = base;
    t +%= 1;
    // Per line: the jelly (each letter line read from a little to the left) and the rainbow's slot.
    var i: u32 = 0;
    while (i < H) : (i += 1) {
        const wob = if (i -% Y0 < 7 * SCALE) bounce(4 * t + i, 64) / 4 else 0; // 16 px of swing
        reg(b, LIST + 16 * i + 4).* = 0x5000_0000 | fb + W * i - wob;
        reg(b, LIST + 16 * i + 12).* = TABLE + 4 * (2 * i + 3 * t & 255);
    }
}

export fn isPlaneEnabled(plane: i32) i32 {
    return @intFromBool(plane == 0);
}

export fn pollCartRequest() i32 {
    return if (t >= HOLD_FRAMES) CHAINLOAD else 0;
}
