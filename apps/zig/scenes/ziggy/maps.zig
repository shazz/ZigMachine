// --------------------------------------------------------------------------
// ZIGGY showcase: the generated data (no assets), built once in init().
//   textures   the rotozoom's 64x64, 128x128 and 256x256 maps: the same picture
//              at three sizes, so only the D$ footprint changes (4, 16, 64 KB)
//   terrain    the voxel's 256x256 height map (diamond-square, a fixed seed,
//              wrapping) and its colour map (height bands, shaded by slope)
//   palettes   one per mode; entries 254/255 are the HUD's paper and ink
// Integers only (the board's cart CPU has no FPU on its soft-float images).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const PAPER: u8 = 254;
pub const INK: u8 = 255;
pub const SKY0: u8 = 200; // the voxel sky ramp: 200..247
pub const TEX_BYTES: usize = 64 * 64 + 128 * 128 + 256 * 256;

/// The texture of side 2^log inside `all` (64, then 128, then 256): the generated
/// textures and the photo (photo.zig) share this layout.
pub fn texture(all: []const u8, log: u4) []const u8 {
    const lo, const hi = bounds(log);
    return all[lo..hi];
}

fn bounds(log: u4) [2]usize {
    return switch (log) {
        6 => .{ 0, 64 * 64 },
        7 => .{ 64 * 64, 64 * 64 + 128 * 128 },
        else => .{ 64 * 64 + 128 * 128, TEX_BYTES },
    };
}

/// One picture at three sizes: a XOR weave under concentric rings, in 0..247.
pub fn buildTextures(all: []u8) void {
    for ([_]u4{ 6, 7, 8 }) |log| {
        const lo, const hi = bounds(log);
        const t = all[lo..hi];
        const n: u32 = @as(u32, 1) << log;
        for (0..n) |y| for (0..n) |x| {
            // Coordinates on a 256 grid whatever the size: the same picture.
            const gx: u32 = @intCast(x * 256 / n);
            const gy: u32 = @intCast(y * 256 / n);
            const dx: i32 = @as(i32, @intCast(gx)) - 128;
            const dy: i32 = @as(i32, @intCast(gy)) - 128;
            const ring: u32 = @intCast(@divTrunc(dx * dx + dy * dy, 160) & 63);
            const weave = (gx ^ gy) & 0xC0;
            t[y * n + x] = @intCast((weave + ring * 2 + (gx & 32)) % 248);
        };
    }
}

/// A wrapping 256x256 diamond-square height map, 0..255.
pub fn buildHeights(h: []u8) void {
    var seed: u32 = 0x5EED_2611;
    const m = zg.mem.mark(); // the i32 map is scratch: released on return, `h` stays
    defer zg.mem.release(m);
    const map = zg.mem.mustAlloc(i32, 256 * 256).ptr;
    map[0] = 128 << 8;
    var step: usize = 256;
    var amp: i32 = 96 << 8;
    while (step > 1) : (step /= 2) {
        const half = step / 2;
        var y: usize = 0;
        while (y < 256) : (y += step) {
            var x: usize = 0;
            while (x < 256) : (x += step) {
                const s = at(map, x, y) + at(map, x + step, y) + at(map, x, y + step) + at(map, x + step, y + step);
                map[(y + half) * 256 + x + half] = @divTrunc(s, 4) + rnd(&seed, amp);
            }
        }
        y = 0;
        while (y < 256) : (y += half) {
            var x: usize = if ((y / half) % 2 == 0) half else 0;
            while (x < 256) : (x += step) {
                const s = at(map, x -% half, y) + at(map, x + half, y) + at(map, x, y -% half) + at(map, x, y + half);
                map[(y & 255) * 256 + (x & 255)] = @divTrunc(s, 4) + rnd(&seed, amp);
            }
        }
        amp = @divTrunc(amp * 9, 16);
    }
    // Stretched to the full 0..255, so every band (water to snow) appears.
    var lo: i32 = map[0];
    var hi: i32 = map[0];
    for (0..256 * 256) |i| {
        lo = @min(lo, map[i]);
        hi = @max(hi, map[i]);
    }
    const span: i64 = @max(1, hi - lo);
    for (0..256 * 256) |i| h[i] = @intCast(@divTrunc(@as(i64, map[i] - lo) * 255, span));
}

fn at(m: [*]i32, x: usize, y: usize) i32 {
    return m[(y & 255) * 256 + (x & 255)];
}

fn rnd(seed: *u32, amp: i32) i32 {
    seed.* = seed.* *% 1664525 +% 1013904223;
    const r: i32 = @intCast(seed.* >> 16 & 0xFFFF); // 0..65535
    return @divTrunc((r - 32768) * @divTrunc(amp, 256), 128);
}

/// Colours: water, sand, grass, rock, snow by height, lit by the slope to the east.
pub fn buildColours(h: []const u8, c: []u8) void {
    for (0..256) |y| for (0..256) |x| {
        const i = y * 256 + x;
        const e: i32 = @as(i32, h[i]) - @as(i32, h[y * 256 + ((x + 1) & 255)]);
        const band: i32 = @divTrunc(@as(i32, h[i]) * 5, 256); // 0..4
        const shade: i32 = @max(0, @min(39, 20 + e * 3));
        c[i] = @intCast(band * 40 + shade);
    };
}

/// ROTO: a hue wheel over 0..247 (three triangle waves), the HUD at 254/255.
pub fn rotoPalette(fb: *zg.LogicalFB) void {
    for (0..248) |i| {
        const p: u32 = @intCast(i * 256 / 248);
        fb.setPaletteEntry(@intCast(i), .{ .r = tri(p), .g = tri(p + 85), .b = tri(p + 170), .a = 255 });
    }
    hud(fb);
}

/// VOXEL: five 40-step bands (water, sand, grass, rock, snow), dark to lit; a sky ramp.
pub fn voxelPalette(fb: *zg.LogicalFB) void {
    const lo = [5][3]u32{ .{ 10, 30, 90 }, .{ 120, 100, 50 }, .{ 30, 80, 20 }, .{ 70, 60, 55 }, .{ 170, 170, 180 } };
    const hi = [5][3]u32{ .{ 40, 110, 200 }, .{ 240, 220, 150 }, .{ 110, 200, 70 }, .{ 170, 160, 150 }, .{ 255, 255, 255 } };
    for (0..5) |b| for (0..40) |s| {
        var col: [3]u8 = undefined;
        for (0..3) |k| col[k] = @intCast((lo[b][k] * (39 - s) + hi[b][k] * s) / 39);
        fb.setPaletteEntry(@intCast(b * 40 + s), .{ .r = col[0], .g = col[1], .b = col[2], .a = 255 });
    };
    for (0..48) |r| { // SKY0.. : deep blue at the top to haze at the horizon
        const k: u32 = @intCast(r);
        fb.setPaletteEntry(@intCast(SKY0 + r), .{ .r = @intCast(20 + k * 3), .g = @intCast(40 + k * 3), .b = @intCast(110 + k * 2), .a = 255 });
    }
    hud(fb);
}

pub fn hud(fb: *zg.LogicalFB) void {
    fb.setPaletteEntry(PAPER, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
    fb.setPaletteEntry(INK, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
}

fn tri(p: u32) u8 {
    const q = p & 255;
    const t: u32 = if (q < 128) q * 2 else (255 - q) * 2;
    return @intCast(40 + t * 215 / 254);
}
