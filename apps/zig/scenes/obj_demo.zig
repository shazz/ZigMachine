// --------------------------------------------------------------------------
// OBJ 3D demo — loads a Wavefront OBJ (zigos/utils/obj_loader.zig) and spins it,
// rendered several ways to contrast HARDWARE and SOFTWARE effects:
//
//   key 1  FLAT   hardware blitter triangles, flat-lit (normal·light -> ramp)
//   key 2  GLENZ  hardware OR-minterm see-through vectors
//   key 3  WIRE   hardware blitter lines (wireframe)
//   key 4  SOFT   a CPU scanline fill of the same mesh (software rasteriser)
//   key 5  MODEL  cycle the loaded model (icosahedron <-> gem)
//
// Models are @embedFile'd .obj text, parsed at runtime. Select in apps/floppy.zig.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const Blitter = zg.Blitter;
const Vec2 = zg.BlitVec2;
const obj = zg.obj;

const WIDTH: i32 = zg.WIDTH;
const HEIGHT: i32 = zg.HEIGHT;
const DIST: f32 = 3.2;
const FOV: f32 = 150.0;
const LEVELS: u8 = 12; // flat/soft light ramp steps (palette 1..12)
const LIGHT = [3]f32{ 0.36, 0.48, -0.80 };

const MODELS = [_][]const u8{
    @embedFile("../assets/obj/icosahedron.obj"),
    @embedFile("../assets/obj/gem.obj"),
};
const NAMES = [4][]const u8{ "FLAT", "GLENZ", "WIRE", "SOFT" };

pub const Demo = struct {
    blitter: Blitter = .{},
    mesh: obj.Mesh = .{},
    os: *ZigOS = undefined,
    style: u8 = 0,
    model: u8 = 0,
    ax: f32 = 0,
    ay: f32 = 0,
    az: f32 = 0,
    pos: [obj.MAX_VERTS][3]f32 = undefined,
    screen: [obj.MAX_VERTS]Vec2 = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("obj_demo init", .{});
        self.os = zigos;
        self.blitter.init();
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(200, .{ .r = 235, .g = 235, .b = 245, .a = 255 }); // text
        fb.setPaletteEntry(201, .{ .r = 120, .g = 235, .b = 255, .a = 255 }); // wire ink
        zigos.setBackgroundColor(.{ .r = 6, .g = 8, .b = 18, .a = 255 });
        self.loadModel(0);
    }

    fn loadModel(self: *Demo, m: u8) void {
        self.model = m;
        self.mesh.load(MODELS[m]);
        Console.log("obj: model {} -> {} verts, {} faces", .{ m, self.mesh.nverts, self.mesh.nfaces });
        self.programPalette();
    }

    pub fn setShadeMode(self: *Demo, mm: u32) void {
        if (mm >= 4) {
            self.loadModel((self.model + 1) % @as(u8, MODELS.len));
        } else {
            self.style = @intCast(mm);
            self.programPalette();
        }
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.ax += 0.019;
        self.ay += 0.027;
        self.az += 0.011;
        self.project();
    }

    // --- rendering ---------------------------------------------------------
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        const b = &self.blitter;
        b.clear(fb, 0);
        switch (self.style) {
            1 => self.drawGlenz(fb),
            2 => self.drawWire(fb),
            3 => self.drawSoft(fb),
            else => self.drawFlat(fb),
        }
        zigos.printText(fb, NAMES[self.style], 10, 8, 200, 0);
    }

    fn drawFlat(self: *Demo, fb: *LogicalFB) void {
        const b = &self.blitter;
        var order: [obj.MAX_FACES]u16 = undefined;
        self.sortFaces(&order);
        for (order[0..self.mesh.nfaces]) |f| {
            const t = self.mesh.faces[f];
            const shade: u8 = 1 + self.brightness(f);
            b.triangle(fb, self.screen[t.a], self.screen[t.b], self.screen[t.c], shade);
        }
    }

    fn drawGlenz(self: *Demo, fb: *LogicalFB) void {
        const b = &self.blitter;
        for (self.mesh.faces[0..self.mesh.nfaces], 0..) |t, i| {
            const bit: u8 = @as(u8, 1) << @intCast(i % 6);
            b.triangleEx(fb, self.screen[t.a], self.screen[t.b], self.screen[t.c], bit, 0, .glenz);
        }
    }

    fn drawWire(self: *Demo, fb: *LogicalFB) void {
        const b = &self.blitter;
        for (self.mesh.faces[0..self.mesh.nfaces]) |t| {
            const va = self.screen[t.a];
            const vb = self.screen[t.b];
            const vc = self.screen[t.c];
            b.line(fb, va.x, va.y, vb.x, vb.y, 201, .copy);
            b.line(fb, vb.x, vb.y, vc.x, vc.y, 201, .copy);
            b.line(fb, vc.x, vc.y, va.x, va.y, 201, .copy);
        }
    }

    // SOFT: the same mesh drawn by a CPU scanline rasteriser (no blitter).
    fn drawSoft(self: *Demo, fb: *LogicalFB) void {
        var order: [obj.MAX_FACES]u16 = undefined;
        self.sortFaces(&order);
        for (order[0..self.mesh.nfaces]) |f| {
            const t = self.mesh.faces[f];
            const shade: u8 = 1 + self.brightness(f);
            softTriangle(fb, self.screen[t.a], self.screen[t.b], self.screen[t.c], shade);
        }
    }

    // --- palette -----------------------------------------------------------
    fn programPalette(self: *Demo) void {
        const fb: *LogicalFB = &self.os.lfbs[0];
        if (self.style == 1) {
            // glenz bit-combo palette (indices 1..63)
            var i: u8 = 1;
            while (i < 64) : (i += 1) {
                var acc = [3]f32{ 0, 0, 0 };
                const hue = [6][3]f32{
                    .{ 0.95, 0.3, 0.4 }, .{ 0.3, 0.9, 0.5 }, .{ 0.98, 0.8, 0.2 },
                    .{ 0.3, 0.6, 0.98 }, .{ 0.85, 0.4, 0.95 }, .{ 0.3, 0.9, 0.9 },
                };
                for (0..6) |k| if (i & (@as(u8, 1) << @intCast(k)) != 0) {
                    for (0..3) |c| acc[c] += hue[k][c];
                };
                fb.setPaletteEntry(i, rgb(acc, 0.72));
                if (i == 63) break;
            }
        } else {
            // teal->white light ramp (indices 1..LEVELS) for FLAT/SOFT/WIRE
            var l: u8 = 0;
            while (l < LEVELS) : (l += 1) {
                const f: f32 = @as(f32, @floatFromInt(l)) / @as(f32, LEVELS - 1);
                fb.setPaletteEntry(1 + l, .{
                    .r = chan(0.15 + 0.85 * f),
                    .g = chan(0.45 + 0.55 * f),
                    .b = chan(0.55 + 0.45 * f),
                    .a = 255,
                });
            }
        }
    }

    // --- geometry ----------------------------------------------------------
    fn project(self: *Demo) void {
        const sx = @sin(self.ax);
        const cx = @cos(self.ax);
        const sy = @sin(self.ay);
        const cy = @cos(self.ay);
        const sz = @sin(self.az);
        const cz = @cos(self.az);
        for (self.mesh.verts[0..self.mesh.nverts], 0..) |p, i| {
            const y1 = p.y * cx - p.z * sx;
            const z1 = p.y * sx + p.z * cx;
            const x2 = p.x * cy + z1 * sy;
            const z2 = -p.x * sy + z1 * cy;
            self.pos[i] = .{ x2 * cz - y1 * sz, x2 * sz + y1 * cz, z2 };
            const zc = z2 + DIST;
            self.screen[i] = .{
                .x = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(WIDTH, 2))) + self.pos[i][0] * FOV / zc),
                .y = @intFromFloat(@as(f32, @floatFromInt(@divTrunc(HEIGHT, 2))) + self.pos[i][1] * FOV / zc),
            };
        }
    }

    fn brightness(self: *Demo, face: u16) u8 {
        const t = self.mesh.faces[face];
        const a = self.pos[t.a];
        const e1 = sub(self.pos[t.b], a);
        const e2 = sub(self.pos[t.c], a);
        const n = cross(e1, e2);
        const d = @abs(dot(n, LIGHT)) / (len(n) + 0.0001);
        return @intFromFloat(@min(d, 0.999) * @as(f32, LEVELS - 1));
    }

    fn sortFaces(self: *Demo, order: *[obj.MAX_FACES]u16) void {
        const n = self.mesh.nfaces;
        for (0..n) |i| order[i] = @intCast(i);
        var i: usize = 1;
        while (i < n) : (i += 1) {
            const cur = order[i];
            const key = self.avgZ(cur);
            var j: usize = i;
            while (j > 0 and self.avgZ(order[j - 1]) < key) : (j -= 1) order[j] = order[j - 1];
            order[j] = cur;
        }
    }

    fn avgZ(self: *Demo, face: u16) f32 {
        const t = self.mesh.faces[face];
        return self.pos[t.a][2] + self.pos[t.b][2] + self.pos[t.c][2];
    }
};

// --- software flat-triangle fill (odd-even scanline, no blitter) -----------
fn softTriangle(fb: *LogicalFB, v0: Vec2, v1: Vec2, v2: Vec2, color: u8) void {
    const xs = [3]i32{ v0.x, v1.x, v2.x };
    const ys = [3]i32{ v0.y, v1.y, v2.y };
    const ymin = @max(@min(ys[0], @min(ys[1], ys[2])), 0);
    const ymax = @min(@max(ys[0], @max(ys[1], ys[2])), HEIGHT - 1);
    var y = ymin;
    while (y <= ymax) : (y += 1) {
        var xl: i32 = std.math.maxInt(i32);
        var xr: i32 = std.math.minInt(i32);
        var e: usize = 0;
        while (e < 3) : (e += 1) {
            var ay = ys[e];
            var ax = xs[e];
            var by = ys[(e + 1) % 3];
            var bx = xs[(e + 1) % 3];
            if (ay == by) continue;
            if (ay > by) {
                std.mem.swap(i32, &ay, &by);
                std.mem.swap(i32, &ax, &bx);
            }
            if (y < ay or y >= by) continue;
            const x = ax + @divFloor((bx - ax) * (y - ay), (by - ay));
            xl = @min(xl, x);
            xr = @max(xr, x);
        }
        if (xr < xl) continue;
        const l: u16 = @intCast(@max(xl, 0));
        const r: u16 = @intCast(@min(xr, WIDTH - 1));
        fb.drawScanline(l, r, @intCast(y), color);
    }
}

// --- small helpers ---------------------------------------------------------
fn rgb(c: [3]f32, s: f32) Color {
    return .{ .r = chan(c[0] * s), .g = chan(c[1] * s), .b = chan(c[2] * s), .a = 255 };
}
fn chan(v: f32) u8 {
    return @intFromFloat(@max(@as(f32, 0), @min(v, 1.0)) * 255.0);
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
