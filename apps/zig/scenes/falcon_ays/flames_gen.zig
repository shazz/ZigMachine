// --------------------------------------------------------------------------
// The flames' stand-ins (no rip): a generated fireball and its halftone negative, sine warps
// (plus value noise for the turbulent map), a Lissajous offset walk and the caption in the
// system font. Integer only; run once at init.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const fixtrig = zg.fixtrig;

pub const W = 320;
pub const ROWS = 150;

fn hash(x: u32, y: u32) u32 {
    var h = x *% 374761393 +% y *% 668265263;
    h = (h ^ (h >> 13)) *% 1274126177;
    return h ^ (h >> 16);
}

// Value noise, 16-texel cells, smooth enough to read as turbulence: 0..255.
fn noise(x: u32, y: u32) u32 {
    const cx = x >> 4;
    const cy = y >> 4;
    const fx = x & 15;
    const fy = y & 15;
    const a = hash(cx & 15, cy & 15) & 255;
    const b = hash((cx + 1) & 15, cy & 15) & 255;
    const c = hash(cx & 15, (cy + 1) & 15) & 255;
    const d = hash((cx + 1) & 15, (cy + 1) & 15) & 255;
    const top = a * (16 - fx) + b * fx;
    const bot = c * (16 - fx) + d * fx;
    return (top * (16 - fy) + bot * fy) >> 8;
}

/// Texel (x, y) of the fireball: a white-yellow core, orange, red, dark at the rim, a blue-white
/// glow under it. `halftone`: its negative, ordered-dithered black on white (texB's look).
pub fn texel(x: usize, y: usize, halftone: bool) u16 {
    const bayer = [16]u32{ 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    const dx: i32 = @as(i32, @intCast(x)) - 128;
    const dy: i32 = @as(i32, @intCast(y)) - 112;
    const n = noise(@intCast(x), @intCast(y)) + noise(@intCast(x * 2 & 255), @intCast(y * 2 & 255)) / 2;
    const d: u32 = @intCast(@divTrunc(dx * dx + dy * dy, 64)); // 0..~400
    const heat: u32 = (300 -| d) * (128 + n) / 300 & ~@as(u32, 3); // 0..~320, in steps of 4
    var r: u32 = @min(255, heat * 2);
    var g: u32 = @min(255, heat * heat / 220);
    var b: u32 = @min(255, (heat -| 200) * 3);
    if (dy > 40 and d > 150 and d < 260) { // the blue rim below
        const rim = (110 -| (if (d > 205) d - 205 else 205 - d) * 2) & ~@as(u32, 15);
        r += rim / 2;
        g += rim;
        b += rim * 2;
    }
    const lum = (@min(255, r) * 3 + @min(255, g) * 6 + @min(255, b)) / 10;
    if (halftone) return if ((255 - lum) / 16 > bayer[(y & 3) * 4 + (x & 3)]) 0xFFFF else 0;
    return zg.tc.rgb565(@intCast(@min(255, r)), @intCast(@min(255, g)), @intCast(@min(255, b)));
}

/// The warp: ~1.9 texels a pixel across, ~2.2 down, bent by sines (and noise for mapB).
pub fn genMap(m: []u16, turbulent: bool) void {
    for (0..ROWS) |y| for (0..W) |x| {
        const ax: u32 = @intCast(y * 0x0180_0000 + x * 0x0080_0000);
        const ay: u32 = @intCast(x * 0x00C0_0000 + y * 0x0040_0000);
        var u: i32 = @intCast(x * 19 / 10);
        var v: i32 = @intCast(y * 22 / 10 + x / 3);
        u += @divFloor(fixtrig.sin(ax) * 22, fixtrig.ONE);
        v += @divFloor(fixtrig.sin(ay) * 28, fixtrig.ONE);
        if (turbulent) {
            u += @as(i32, @intCast(noise(@intCast(x * 3), @intCast(y * 3)) >> 4)) - 8;
            v += @as(i32, @intCast(noise(@intCast(x * 3 + 77), @intCast(y * 3)) >> 4)) - 8;
        }
        m[y * W + x] = @as(u16, @as(u8, @truncate(@as(u32, @bitCast(v))))) << 8 | @as(u8, @truncate(@as(u32, @bitCast(u))));
    };
}

/// A Lissajous walk, one texel a step at most (v<<8 | u).
pub fn genPath(path: []u16) void {
    for (path, 0..) |*p, i| {
        const a: u32 = @as(u32, @intCast(i)) << 22;
        const u: i32 = 128 + @divFloor(fixtrig.sin(a *% 2) * 100, fixtrig.ONE);
        const v: i32 = 128 + @divFloor(fixtrig.sin(a *% 3 +% 0x4000_0000) * 100, fixtrig.ONE);
        p.* = @as(u16, @intCast(v & 255)) << 8 | @as(u16, @intCast(u & 255));
    }
}

/// "are you sitting comfortably?" in the 8x8 system font, 10x16 a letter: 1 = ink.
pub fn genCaption(caption: []u8, font: []const u8) void {
    @memset(caption, 0);
    const s = "are you sitting comfortably?";
    const x0 = (W - s.len * 10) / 2;
    for (s, 0..) |ch, k| for (0..16) |y| for (0..10) |x| {
        if (font.len < (@as(usize, ch) + 1) * 64) continue;
        if (font[@as(usize, ch) * 64 + (y / 2) * 8 + x * 8 / 10] != 0) caption[(3 + y) * W + x0 + k * 10 + x] = 1;
    };
}
