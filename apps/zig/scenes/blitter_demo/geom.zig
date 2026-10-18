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

// An inclusive pixel box.
pub const Box = struct { x0: i32, y0: i32, x1: i32, y1: i32 };

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

    // Rotate the mesh into camera space. Once a frame: step() calls it, and the
    // tile/delay modes then only re-project (they used to redo six sin/cos for it).
    pub fn rotate(self: *Cube) void {
        const sx = @sin(self.ax);
        const cx = @cos(self.ax);
        const sy = @sin(self.ay);
        const cy = @cos(self.ay);
        const sz = @sin(self.az);
        const cz = @cos(self.az);
        for (CUBE, 0..) |p, i| {
            const y1 = p[1] * cx - p[2] * sx;
            const z1 = p[1] * sx + p[2] * cx;
            const x2 = p[0] * cy + z1 * sy;
            const z2 = -p[0] * sy + z1 * cy;
            self.pos[i] = .{ x2 * cz - y1 * sz, x2 * sz + y1 * cz, z2 };
        }
    }

    // Perspective-project the rotated vertices around (cx_i, cy_i).
    pub fn project(self: *Cube, fov: f32, cx_i: i32, cy_i: i32) void {
        const ox: f32 = @floatFromInt(cx_i);
        const oy: f32 = @floatFromInt(cy_i);
        for (self.pos, 0..) |p, i| {
            const zc = p[2] + DIST;
            self.screen[i] = .{
                .x = @intFromFloat(ox + p[0] * fov / zc),
                .y = @intFromFloat(oy + p[1] * fov / zc),
            };
        }
    }

    // The box the cube's triangles can touch, clipped to a w x h target (every
    // span the blitter draws lies between its vertices); null when it is off it.
    pub fn bounds(self: *const Cube, w: i32, h: i32) ?Box {
        var b = Box{ .x0 = w, .y0 = h, .x1 = -1, .y1 = -1 };
        for (self.screen) |v| {
            b.x0 = @min(b.x0, v.x);
            b.y0 = @min(b.y0, v.y);
            b.x1 = @max(b.x1, v.x);
            b.y1 = @max(b.y1, v.y);
        }
        b = .{ .x0 = @max(b.x0, 0), .y0 = @max(b.y0, 0), .x1 = @min(b.x1, w - 1), .y1 = @min(b.y1, h - 1) };
        return if (b.x1 < b.x0 or b.y1 < b.y0) null else b;
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
// Only LIT changes with the cube; the flat hues and the 63 glenz blends are
// worked out once (the same f32 maths) and copied in, like an ST palette table.
pub const Palettes = struct {
    flat: [6]Color = undefined,
    glenz: [63]Color = undefined,

    pub fn init(self: *Palettes) void {
        for (HUE, 0..) |c, f| self.flat[f] = rgb(c, 1.0);
        for (&self.glenz, 1..) |*g, i| {
            var acc = [3]f32{ 0, 0, 0 };
            for (0..6) |f| if (i & (@as(usize, 1) << @intCast(f)) != 0) {
                for (0..3) |k| acc[k] += HUE[f][k];
            };
            g.* = rgb(acc, 0.72); // <1 keeps single faces translucent
        }
    }

    pub fn program(self: *const Palettes, cube: *const Cube, mode: u8, fb: *LogicalFB) void {
        switch (mode) {
            1 => for (0..6) |f| fb.setPaletteEntry(@intCast(f + 1), rgb(HUE[f], cube.brightness(@intCast(f)))),
            3 => for (self.glenz, 1..) |c, i| fb.setPaletteEntry(@intCast(i), c),
            else => for (self.flat, 1..) |c, i| fb.setPaletteEntry(@intCast(i), c), // flat hues (0,2,4,5)
        }
    }
};

// A 16x16 halftone pattern whose set-bit density tracks `b` (0..1) via a
// tiled 4x4 Bayer matrix: denser where brighter, for ordered-dither shading.
// Only 17 levels exist, so they are built once at compile time (the loop that
// ran 256 steps per face per frame, kept as the generator) and indexed.
const HALFTONES: [17][16]u16 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [17][16]u16 = undefined;
    for (&t, 0..) |*rows, level| {
        for (0..16) |y| {
            var row: u16 = 0;
            for (0..16) |x| {
                if (level > BAYER[(y % 4) * 4 + (x % 4)]) row |= @as(u16, 1) << @intCast(x);
            }
            rows[y] = row;
        }
    }
    break :blk t;
};

pub fn genHalftone(b: f32) [16]u16 {
    return HALFTONES[@intCast(@as(i32, @intFromFloat(@min(b, 1.0) * 16.0)))];
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
