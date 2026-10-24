// --------------------------------------------------------------------------
// OBJ 3D demo: a Wavefront OBJ (zigos/utils/obj_loader.zig) or a procedural
// sphere, spun and drawn in six shading modes, in fixed point on one plane.
// It is also the board's polygon benchmark: the sphere's resolution goes up
// and down, and the top lines show V/F and, where the host has a clock, the
// fps and the cart's own time a frame.
//
//   keys 1 2 3  the OBJECT: icosahedron, gem, sphere
//   S           the SHADING: FLAT (CHISEL triangles, flat-lit), GLENZ (OR
//               see-through), WIRE (every edge), SOFT (CPU scanline fill),
//               GOURAUD (CPU, per-vertex light), HIDDEN (hidden-line wire)
//   + / -       the sphere's resolution (13 levels, 36 to 3968 faces)
//   C           where faces/edges go: CHISEL, the CPU below 8/16/24/48 rows, or the CPU
//   Esc         back to the menu
// The cart owns the keyboard (so + / - reach it, not the host's channel
// change), and digits come through key() too.
//
// Per frame it is all integers (obj/fixed3d.zig): a Q14 rotation matrix, one
// divide per vertex, culling by screen winding, a radix depth sort, and the
// faces and edges split between CHISEL and the CPU by size (obj/draw.zig).
// Only the box the object covered last frame is erased.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const fx = @import("obj/fixed3d.zig");
const fmesh = @import("obj/fmesh.zig");
const sphere = @import("obj/sphere.zig");
const xform = @import("obj/xform.zig");
const draw = @import("obj/draw.zig");
const pal = @import("obj/palette.zig");
const Hud = @import("obj/hud.zig").Hud;

const MODELS = [_][]const u8{
    @embedFile("../assets/obj/icosahedron.obj"),
    @embedFile("../assets/obj/gem.obj"),
};
const OBJECTS = [_][]const u8{ "ICOSAHEDRON", "GEM", "SPHERE" };
const SPHERE: u8 = 2;
const K_ESC: u32 = 0xE012;
// The old f32 steps a frame (0.019, 0.027, 0.011 rad) as Angles.
const STEP = [3]fx.Angle{ fx.angle(0.019), fx.angle(0.027), fx.angle(0.011) };

pub const Demo = struct {
    blitter: zg.Blitter = .{},
    os: *zg.ZigOS = undefined,
    // From the cart RAM arena once, in init(): the OBJ text's f32 mesh, the
    // integer mesh the frame uses, and the frame's working arrays.
    loader: *zg.obj.Mesh = undefined,
    mesh: *fmesh.Mesh = undefined,
    frame: *xform.Frame = undefined,
    hud: Hud = .{},
    object: u8 = 0,
    mode: draw.Mode = .flat,
    level: u8 = 0, // the sphere's
    split: u8 = draw.DEFAULT_SPLIT, // CPU / CHISEL split preset (key C)
    ang: [3]fx.Angle = .{ 0, 0, 0 },
    drawn: [4]i32 = .{ 0, 0, -1, -1 }, // last frame's box, x0 y0 x1 y1
    full_clear: bool = true,
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        zg.Console.log("obj_demo init", .{});
        self.* = .{}; // the cart is `undefined` (zeroed), not default-initialised
        self.loader = &zg.mem.mustAlloc(zg.obj.Mesh, 1)[0];
        self.mesh = &zg.mem.mustAlloc(fmesh.Mesh, 1)[0];
        self.frame = &zg.mem.mustAlloc(xform.Frame, 1)[0];
        self.os = zigos;
        self.blitter.init();
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        pal.fixed(fb);
        zigos.setBackgroundColor(.{ .r = 6, .g = 8, .b = 18, .a = 255 });
        self.selectObject(0);
        pal.program(fb, self.mode);
    }

    fn selectObject(self: *Demo, o: u8) void {
        self.object = o;
        if (o == SPHERE) sphere.build(self.mesh, sphere.LEVELS[self.level]) else self.loadObj(MODELS[o]);
        zg.Console.log("obj: object {} -> {} verts, {} faces", .{ o, self.mesh.nverts, self.mesh.nfaces });
    }

    /// The OBJ text through the loader (f32, once a model), into the Q14 mesh.
    fn loadObj(self: *Demo, text: []const u8) void {
        const src = self.loader;
        src.load(text);
        const m = self.mesh;
        m.nverts = src.nverts;
        for (src.verts[0..src.nverts], 0..) |v, i| m.verts[i] = .{ fmesh.q14(v.x), fmesh.q14(v.y), fmesh.q14(v.z), 0 };
        m.nfaces = src.nfaces;
        for (src.faces[0..src.nfaces], 0..) |f, i| m.faces[i] = .{ .a = f.a, .b = f.b, .c = f.c };
        m.finish();
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.wants_quit = true,
            '1'...'3' => self.selectObject(@intCast(cp - '1')),
            's', 'S' => {
                self.mode = @enumFromInt((@intFromEnum(self.mode) + 1) % draw.NAMES.len);
                pal.program(&self.os.lfbs[0], self.mode);
            },
            'c', 'C' => self.split = (self.split + 1) % @as(u8, draw.SPLITS.len),
            '+', '=' => self.resolution(1),
            '-', '_' => self.resolution(-1),
            else => {},
        }
    }

    /// The host's 1-7 switch, for a host that still sends it: 1-3 pick the object.
    pub fn setShadeMode(self: *Demo, m: u32) void {
        if (m < OBJECTS.len) self.selectObject(@intCast(m));
    }

    fn resolution(self: *Demo, d: i8) void {
        if (self.object != SPHERE) return; // the OBJ models have one resolution
        const l = @as(i16, self.level) + d;
        if (l < 0 or l >= sphere.LEVELS.len) return;
        self.level = @intCast(l);
        self.selectObject(SPHERE);
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.hud.workStart();
        for (0..3) |k| self.ang[k] +%= STEP[k];
        const m = fx.rotation(self.ang[0], self.ang[1], self.ang[2]);
        self.frame.transform(self.mesh, &m, self.mode == .gouraud);
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        self.erase(fb);
        const split = draw.SPLITS[self.split];
        draw.draw(.{ .fb = fb, .b = &self.blitter, .m = self.mesh, .fr = self.frame, .split = split }, self.mode);
        self.drawn = self.frame.box;
        const level: ?u8 = if (self.object == SPHERE) self.level else null;
        self.hud.draw(zigos, fb, .{ .mode = draw.NAMES[@intFromEnum(self.mode)], .object = OBJECTS[self.object], .level = level, .split = split.name, .v = self.mesh.nverts, .f = self.mesh.nfaces });
        self.hud.workEnd();
    }

    /// The whole plane once, then only the box last frame's object covered.
    fn erase(self: *Demo, fb: *zg.LogicalFB) void {
        if (self.full_clear) {
            self.blitter.clear(fb, 0);
            self.full_clear = false;
            return;
        }
        const x0 = @max(self.drawn[0], 0);
        const y0 = @max(self.drawn[1], 0);
        const x1 = @min(self.drawn[2], @as(i32, fb.fb_w) - 1);
        const y1 = @min(self.drawn[3], @as(i32, fb.fb_h) - 1);
        if (x1 < x0 or y1 < y0) return;
        self.blitter.fill(fb, @intCast(x0), @intCast(y0), @intCast(x1 - x0 + 1), @intCast(y1 - y0 + 1), 0);
    }
};
