// --------------------------------------------------------------------------
// Blitter demo — the cube: mesh, rotation/projection, face sort, lighting and
// the palette maths. Shared by every mode, and the same in BLITTER and CPU mode
// (only the drawing changes with key B, see gfx.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const Vec2 = zg.BlitVec2;

pub const DIST: f32 = 4.2;
pub const FOV: f32 = 150.0;

const CUBE = [8][3]f32{
    .{ -1, -1, -1 }, .{ 1, -1, -1 }, .{ 1, 1, -1 }, .{ -1, 1, -1 },
    .{ -1, -1, 1 },  .{ 1, -1, 1 },  .{ 1, 1, 1 },  .{ -1, 1, 1 },
};
pub const FACES = [6][4]u8{
    .{ 0, 1, 2, 3 }, .{ 5, 4, 7, 6 }, .{ 4, 0, 3, 7 },
    .{ 1, 5, 6, 2 }, .{ 4, 5, 1, 0 }, .{ 3, 2, 6, 7 },
};
// Per-face base hue (0..1 RGB); face index -> palette entry (f+1) in flat/lit/halftone.
pub const HUE = [6][3]f32{
    .{ 0.95, 0.25, 0.35 }, .{ 0.25, 0.85, 0.45 }, .{ 0.98, 0.80, 0.20 },
    .{ 0.30, 0.55, 0.98 }, .{ 0.85, 0.45, 0.95 }, .{ 0.30, 0.85, 0.90 },
};
const LIGHT = [3]f32{ 0.32, 0.42, -0.85 }; // toward the viewer (-z)
// 4x4 Bayer ordered-dither thresholds (0..15), tiled to the 16x16 halftone reg.
const BAYER = [16]u8{ 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };

pub const Cube = struct {
    ax: f32 = 0,
    ay: f32 = 0,
    az: f32 = 0,
    pos: [8][3]f32 = undefined, // rotated camera-space vertices
    screen: [8]Vec2 = undefined,

    pub fn spin(self: *Cube) void {
        self.ax += 0.030;
        self.ay += 0.023;
        self.az += 0.013;
    }

    pub fn project(self: *Cube, fov: f32, cx_i: i32, cy_i: i32) void {
        const sx = @sin(self.ax);
        const cx = @cos(self.ax);
        const sy = @sin(self.ay);
        const cy = @cos(self.ay);
        const sz = @sin(self.az);
        const cz = @cos(self.az);
        const ox: f32 = @floatFromInt(cx_i);
        const oy: f32 = @floatFromInt(cy_i);
        for (CUBE, 0..) |p, i| {
            const y1 = p[1] * cx - p[2] * sx;
            const z1 = p[1] * sx + p[2] * cx;
            const x2 = p[0] * cy + z1 * sy;
            const z2 = -p[0] * sy + z1 * cy;
            self.pos[i] = .{ x2 * cz - y1 * sz, x2 * sz + y1 * cz, z2 };
            const zc = z2 + DIST;
            self.screen[i] = .{
                .x = @intFromFloat(ox + self.pos[i][0] * fov / zc),
                .y = @intFromFloat(oy + self.pos[i][1] * fov / zc),
            };
        }
    }

    pub fn brightness(self: *const Cube, face: u8) f32 {
        const q = FACES[face];
        const a = self.pos[q[0]];
        const e1 = sub(self.pos[q[1]], a);
        const e2 = sub(self.pos[q[3]], a);
        const n = cross(e1, e2);
        const d = @abs(dot(n, LIGHT)) / (len(n) + 0.0001);
        return 0.2 + 0.8 * @min(d, 1.0);
    }

    // Painter's order, far first.
    pub fn sortFaces(self: *const Cube, order: *[6]u8) void {
        var i: usize = 1;
        while (i < 6) : (i += 1) {
            const cur = order[i];
            const key = self.avgZ(cur);
            var j: usize = i;
            while (j > 0 and self.avgZ(order[j - 1]) < key) : (j -= 1) order[j] = order[j - 1];
            order[j] = cur;
        }
    }

    fn avgZ(self: *const Cube, face: u8) f32 {
        const q = FACES[face];
        return self.pos[q[0]][2] + self.pos[q[1]][2] + self.pos[q[2]][2] + self.pos[q[3]][2];
    }
};

// --- palette -----------------------------------------------------------
// Reprogram the shared palette for the active mode each frame: flat = static
// hues, lit = hue*brightness per face, glenz = additive blend of face bits.
pub fn programPalette(cube: *const Cube, mode: u8, fb: *LogicalFB) void {
    switch (mode) {
        1 => for (0..6) |f| fb.setPaletteEntry(@intCast(f + 1), rgb(HUE[f], cube.brightness(@intCast(f)))),
        3 => programGlenz(fb),
        else => for (HUE, 0..) |c, f| fb.setPaletteEntry(@intCast(f + 1), rgb(c, 1.0)), // flat hues (0,2,4,5)
    }
}

fn programGlenz(fb: *LogicalFB) void {
    var i: u8 = 1;
    while (i < 64) : (i += 1) {
        var acc = [3]f32{ 0, 0, 0 };
        for (0..6) |f| if (i & (@as(u8, 1) << @intCast(f)) != 0) {
            for (0..3) |k| acc[k] += HUE[f][k];
        };
        fb.setPaletteEntry(i, rgb(acc, 0.72)); // <1 keeps single faces translucent
        if (i == 63) break;
    }
}

// Build a 16x16 halftone pattern whose set-bit density tracks `b` (0..1) via a
// tiled 4x4 Bayer matrix — denser where brighter, for ordered-dither shading.
pub fn genHalftone(b: f32) [16]u16 {
    const level: i32 = @intFromFloat(@min(b, 1.0) * 16.0);
    var rows: [16]u16 = undefined;
    for (0..16) |y| {
        var row: u16 = 0;
        for (0..16) |x| {
            const t: i32 = BAYER[(y % 4) * 4 + (x % 4)];
            if (level > t) row |= @as(u16, 1) << @intCast(x);
        }
        rows[y] = row;
    }
    return rows;
}

fn rgb(c: [3]f32, s: f32) Color {
    return .{ .r = chan(c[0] * s), .g = chan(c[1] * s), .b = chan(c[2] * s), .a = 255 };
}
fn chan(v: f32) u8 {
    return @intFromFloat(@min(v, 1.0) * 255.0);
}
fn sub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn len(a: [3]f32) f32 {
    return @sqrt(dot(a, a));
}
