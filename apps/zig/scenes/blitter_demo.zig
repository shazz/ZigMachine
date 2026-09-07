// --------------------------------------------------------------------------
// Blitter demo — a rotating vector cube drawn entirely through the sealed 2D
// blitter (docs/BLITTER_HW_SPEC.md), switchable between seven modes that exercise
// the hardware's fill / minterm / halftone / block-copy paths:
//
//   key 1  FLAT      one solid COLOR per face (painter's sort)
//   key 2  LIT       per-face flat lighting (palette recomputed each frame)
//   key 3  HALFTONE  ordered-dither shading (COLOR/BG via the halftone register)
//   key 4  GLENZ     additive OR minterm + a bit-combo palette = see-through
//                    "glenz vectors" (all faces drawn, overlaps blend)
//   key 5  RUBBER    render once, strip-blit back with a per-row sine offset
//                    (bitmap deformation via H one-row BLITs)
//   key 6  TILE      render one small cube, block-copy it across an overlapping
//                    grid (the whole screen for one rasterisation; cost = pixels)
//   key 7  DELAY     video-feedback grid: a ring of the last DN tiles, each cell
//                    showing the cube from N frames ago (a trail through time)
//
// The scene owns only the mesh, rotation and palette; the machine owns the fill
// rule (the sealed ethos). Select it in apps/floppy.zig. Plane 0 displays; planes
// 1 (ring) and 2 (tile) are borrowed as blitter scratch. Index 0 = transparent.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const Blitter = zg.Blitter;
const Vec2 = zg.BlitVec2;

const WIDTH: i32 = zg.WIDTH;
const HEIGHT: i32 = zg.HEIGHT;
const DIST: f32 = 4.2;
const FOV: f32 = 150.0;

const CUBE = [8][3]f32{
    .{ -1, -1, -1 }, .{ 1, -1, -1 }, .{ 1, 1, -1 }, .{ -1, 1, -1 },
    .{ -1, -1, 1 },  .{ 1, -1, 1 },  .{ 1, 1, 1 },  .{ -1, 1, 1 },
};
const FACES = [6][4]u8{
    .{ 0, 1, 2, 3 }, .{ 5, 4, 7, 6 }, .{ 4, 0, 3, 7 },
    .{ 1, 5, 6, 2 }, .{ 4, 5, 1, 0 }, .{ 3, 2, 6, 7 },
};
// Per-face base hue (0..1 RGB); face index -> palette entry (f+1) in flat/lit/halftone.
const HUE = [6][3]f32{
    .{ 0.95, 0.25, 0.35 }, .{ 0.25, 0.85, 0.45 }, .{ 0.98, 0.80, 0.20 },
    .{ 0.30, 0.55, 0.98 }, .{ 0.85, 0.45, 0.95 }, .{ 0.30, 0.85, 0.90 },
};
const LIGHT = [3]f32{ 0.32, 0.42, -0.85 }; // toward the viewer (-z)
// 4x4 Bayer ordered-dither thresholds (0..15), tiled to the 16x16 halftone reg.
const BAYER = [16]u8{ 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
const NAMES = [7][]const u8{ "FLAT", "LIT", "HALFTONE", "GLENZ", "RUBBER", "TILE", "DELAY" };
const MODE_MAX: u32 = 6;

// RUBBER: per-row horizontal sine displacement (strip blits).
const WOB_AMP: f32 = 14.0;
const WOB_FREQ: f32 = 0.11;
// TILE: render the cube once into a TILE_W×TILE_H corner of a scratch plane, then
// block-copy that tile across a GRID_X×GRID_Y grid — the whole screen for the
// cost of copies, one rasterisation.
const TILE_W: u16 = 74;
const TILE_H: u16 = 60;
const GRID_X: u16 = 10; // overlapping grid (step < tile) so tile COUNT drives the
const GRID_Y: u16 = 8; //  pixels-copied cost — watch the FPS readout vs the count
const TILE_STEP_X: u16 = 34;
const TILE_STEP_Y: u16 = 26;
const TILE_ORIGIN_X: i16 = -20; // pull the grid left so the first column hugs the border

// DELAY: a video-feedback grid. Each frame renders one small tile of the cube
// and pushes it into a ring of the last DN tiles (kept packed side-by-side in a
// spare plane buffer); grid cell g displays the slot from g frames ago, so the
// grid reads as a trail through time. DGX*DGY must equal DN.
const DTILE_W: u16 = 26;
const DTILE_H: u16 = 20;
const DGX: u16 = 12;
const DGY: u16 = 10;
const DN: u32 = 120; // ring length = tile count; DN*DTILE_W*DTILE_H (62400) must fit a plane (64000)

// Fixed UI palette indices, kept ABOVE the glenz bit-combo range (1..63) so the
// glenz palette reprogram never clobbers the frame / halftone-bg / text colours.
const FRAME_COL: u8 = 200;
const HT_BG: u8 = 201;
const TEXT_COL: u8 = 202;

pub const Demo = struct {
    blitter: Blitter = .{},
    mode: u8 = 0,
    ax: f32 = 0,
    ay: f32 = 0,
    az: f32 = 0,
    wob: f32 = 0, // rubber-wobble phase
    head: u32 = 0, // DELAY ring write position
    pos: [8][3]f32 = undefined, // rotated camera-space vertices
    screen: [8]Vec2 = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("blitter_demo init", .{});
        self.blitter.init();
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(FRAME_COL, .{ .r = 120, .g = 130, .b = 150, .a = 255 });
        fb.setPaletteEntry(HT_BG, .{ .r = 18, .g = 20, .b = 30, .a = 255 });
        fb.setPaletteEntry(TEXT_COL, .{ .r = 235, .g = 235, .b = 245, .a = 255 });
        zigos.setBackgroundColor(.{ .r = 8, .g = 8, .b = 16, .a = 255 });
        self.blitter.clear(&zigos.lfbs[1], 0); // wipe the DELAY ring (plane 1 scratch)
        self.setShadeMode(0);
    }

    pub fn setShadeMode(self: *Demo, m: u32) void {
        self.mode = @intCast(@min(m, MODE_MAX));
        Console.log("blitter_demo mode -> {s}", .{NAMES[self.mode]});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.ax += 0.030;
        self.ay += 0.023;
        self.az += 0.013;
        self.wob += 0.14;
        self.project(FOV, @divTrunc(WIDTH, 2), @divTrunc(HEIGHT, 2));
        self.programPalette(&zigos.lfbs[0]);
    }

    // --- rendering ---------------------------------------------------------
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        const b = &self.blitter;
        b.clearHalftone();
        b.clear(fb, 0);
        self.drawFrame(fb);

        switch (self.mode) {
            3 => self.renderGlenz(fb),
            4 => self.renderRubber(zigos, fb),
            5 => self.renderTile(zigos, fb),
            6 => self.renderDelay(zigos, fb),
            else => self.renderSolid(fb),
        }
        zigos.printText(fb, NAMES[self.mode], 10, 8, TEXT_COL, 0);
    }

    // RUBBER: render the cube (flat) into a scratch plane once, then strip-blit it
    // back row-by-row with a per-row sine X offset — a bitmap deformation for the
    // cost of H one-row BLITs (the classic "rubber" wobble).
    fn renderRubber(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const scratch = &zigos.lfbs[1];
        const b = &self.blitter;
        b.clear(scratch, 0);
        self.drawFacesFlat(scratch);
        var y: i16 = 0;
        while (y < HEIGHT) : (y += 1) {
            const dx: i16 = @intFromFloat(WOB_AMP * @sin(@as(f32, @floatFromInt(y)) * WOB_FREQ + self.wob));
            b.bob(fb, dx, y, scratch, 0, y, @intCast(WIDTH), 1, 0); // key 0 keeps the frame
        }
    }

    // TILE: render the cube small ONCE into a TILE_W×TILE_H corner of a scratch
    // plane, then block-copy that tile across the grid — the whole screen filled
    // with cubes for one rasterisation + cheap copies.
    fn renderTile(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const scratch = &zigos.lfbs[1];
        const b = &self.blitter;
        b.fill(scratch, 0, 0, TILE_W, TILE_H, 0);
        self.project(FOV * @as(f32, @floatFromInt(TILE_W)) / @as(f32, @floatFromInt(WIDTH)), TILE_W / 2, TILE_H / 2);
        self.drawFacesFlat(scratch);
        self.project(FOV, @divTrunc(WIDTH, 2), @divTrunc(HEIGHT, 2)); // restore
        var gy: u16 = 0;
        while (gy < GRID_Y) : (gy += 1) {
            var gx: u16 = 0;
            while (gx < GRID_X) : (gx += 1) {
                b.bob(fb, @as(i16, @intCast(gx * TILE_STEP_X)) + TILE_ORIGIN_X, @intCast(gy * TILE_STEP_Y), scratch, 0, 0, TILE_W, TILE_H, 0);
            }
        }
        zigos.printText(fb, "TILES:80", 250, 8, TEXT_COL, 0);
    }

    // DELAY: render one mini-tile of the cube, push it into a ring of the last DN
    // tiles (packed side-by-side in plane 1), then show cell g from g frames ago —
    // a blitter video-feedback trail. Ring stride = DN*DTILE_W keeps it one tile
    // tall, so the machine's stride->height clip leaves the slots addressable.
    fn renderDelay(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const b = &self.blitter;
        var tile = view(&zigos.lfbs[2], DTILE_W, DTILE_W, DTILE_H); // current-frame tile
        var ring = view(&zigos.lfbs[1], @intCast(DN * DTILE_W), @intCast(DN * DTILE_W), DTILE_H);

        b.fill(&tile, 0, 0, DTILE_W, DTILE_H, 0);
        self.project(FOV * @as(f32, @floatFromInt(DTILE_W)) / @as(f32, @floatFromInt(WIDTH)), DTILE_W / 2, DTILE_H / 2);
        self.drawFacesFlat(&tile);
        self.project(FOV, @divTrunc(WIDTH, 2), @divTrunc(HEIGHT, 2)); // restore
        b.blitCopy(&ring, @intCast(self.head * DTILE_W), 0, &tile, 0, 0, DTILE_W, DTILE_H);

        var g: u32 = 0;
        var gy: u16 = 0;
        while (gy < DGY) : (gy += 1) {
            var gx: u16 = 0;
            while (gx < DGX) : (gx += 1) {
                const slot = (self.head + DN - g) % DN; // g frames old
                b.bob(fb, @intCast(gx * DTILE_W), @intCast(gy * DTILE_H), &ring, @intCast(slot * DTILE_W), 0, DTILE_W, DTILE_H, 0);
                g += 1;
            }
        }
        self.head = (self.head + 1) % DN;
    }

    // Flat-shaded cube into an arbitrary target (used by RUBBER/TILE scratch).
    fn drawFacesFlat(self: *Demo, target: *LogicalFB) void {
        const b = &self.blitter;
        var order = [6]u8{ 0, 1, 2, 3, 4, 5 };
        self.sortFaces(&order);
        for (order) |f| {
            const q = FACES[f];
            const v = self.screen;
            b.triangleEx(target, v[q[0]], v[q[1]], v[q[2]], f + 1, HT_BG, .copy);
            b.triangleEx(target, v[q[0]], v[q[2]], v[q[3]], f + 1, HT_BG, .copy);
        }
    }

    // FLAT / LIT / HALFTONE: opaque faces, painter's sort (far first).
    fn renderSolid(self: *Demo, fb: *LogicalFB) void {
        const b = &self.blitter;
        var order = [6]u8{ 0, 1, 2, 3, 4, 5 };
        self.sortFaces(&order);
        for (order) |f| {
            if (self.mode == 2) b.setHalftone(genHalftone(self.brightness(f)));
            const idx: u8 = f + 1;
            const q = FACES[f];
            const v = self.screen;
            b.triangleEx(fb, v[q[0]], v[q[1]], v[q[2]], idx, HT_BG, .copy);
            b.triangleEx(fb, v[q[0]], v[q[2]], v[q[3]], idx, HT_BG, .copy);
        }
    }

    // GLENZ: every face drawn with a single-bit colour OR'd into the buffer; the
    // bit-combo palette (see programPalette) turns overlaps into blended shades.
    fn renderGlenz(self: *Demo, fb: *LogicalFB) void {
        const b = &self.blitter;
        for (FACES, 0..) |q, f| {
            const bit: u8 = @as(u8, 1) << @intCast(f);
            const v = self.screen;
            b.triangleEx(fb, v[q[0]], v[q[1]], v[q[2]], bit, 0, .glenz);
            b.triangleEx(fb, v[q[0]], v[q[2]], v[q[3]], bit, 0, .glenz);
        }
    }

    fn drawFrame(self: *Demo, fb: *LogicalFB) void {
        const b = &self.blitter;
        const w: u16 = @intCast(WIDTH);
        const h: u16 = @intCast(HEIGHT);
        b.fill(fb, 0, 0, w, 4, FRAME_COL);
        b.fill(fb, 0, @intCast(HEIGHT - 4), w, 4, FRAME_COL);
        b.fill(fb, 0, 0, 4, h, FRAME_COL);
        b.fill(fb, @intCast(WIDTH - 4), 0, 4, h, FRAME_COL);
    }

    // --- palette -----------------------------------------------------------
    // Reprogram the shared palette for the active mode each frame: flat = static
    // hues, lit = hue*brightness per face, glenz = additive blend of face bits.
    fn programPalette(self: *Demo, fb: *LogicalFB) void {
        switch (self.mode) {
            1 => for (0..6) |f| fb.setPaletteEntry(@intCast(f + 1), rgb(HUE[f], self.brightness(@intCast(f)))),
            3 => self.programGlenz(fb),
            else => for (HUE, 0..) |c, f| fb.setPaletteEntry(@intCast(f + 1), rgb(c, 1.0)), // flat hues (0,2,4,5)
        }
    }

    fn programGlenz(self: *Demo, fb: *LogicalFB) void {
        _ = self;
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

    // --- geometry / lighting ----------------------------------------------
    fn project(self: *Demo, fov: f32, cx_i: i32, cy_i: i32) void {
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

    fn brightness(self: *Demo, face: u8) f32 {
        const q = FACES[face];
        const a = self.pos[q[0]];
        const e1 = sub(self.pos[q[1]], a);
        const e2 = sub(self.pos[q[3]], a);
        const n = cross(e1, e2);
        const d = @abs(dot(n, LIGHT)) / (len(n) + 0.0001);
        return 0.2 + 0.8 * @min(d, 1.0);
    }

    fn sortFaces(self: *Demo, order: *[6]u8) void {
        var i: usize = 1;
        while (i < 6) : (i += 1) {
            const cur = order[i];
            const key = self.avgZ(cur);
            var j: usize = i;
            while (j > 0 and self.avgZ(order[j - 1]) < key) : (j -= 1) order[j] = order[j - 1];
            order[j] = cur;
        }
    }

    fn avgZ(self: *Demo, face: u8) f32 {
        const q = FACES[face];
        return self.pos[q[0]][2] + self.pos[q[1]][2] + self.pos[q[2]][2] + self.pos[q[3]][2];
    }
};

// --- small helpers ---------------------------------------------------------
// A re-strided view onto an existing plane's buffer, for treating a scratch
// plane as a packed tile ring / small render target (same backing bytes).
fn view(src: *LogicalFB, stride: u16, w: u16, h: u16) LogicalFB {
    var v = src.*;
    v.stride = stride;
    v.fb_w = w;
    v.fb_h = h;
    return v;
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

// Build a 16x16 halftone pattern whose set-bit density tracks `b` (0..1) via a
// tiled 4x4 Bayer matrix — denser where brighter, for ordered-dither shading.
fn genHalftone(b: f32) [16]u16 {
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
