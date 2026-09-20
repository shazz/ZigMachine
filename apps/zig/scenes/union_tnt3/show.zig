// --------------------------------------------------------------------------
// TNT3's object show: which object is up, how it comes in, and how it leaves
// (screen.js update(), 650-799, and draw()'s 3D loop, 817-832).
//
//   - an object starts at z 0 and backs off 10 a frame to -700, not turning;
//     from there it turns by its speed, once per frame after it is drawn;
//   - a key (1..5 / A..E, or ESC / SPACE to leave) starts a change: every
//     engine's camera backs off 100 a frame until engine 0's reaches 10000,
//     then the chosen object's engines are built fresh at its camera and
//     rotation (or, leaving, the screen ends there);
//   - the first object is the TNT logo, but built by init(), whose camera is
//     codef3D's camZ 10, not the key's 100.
//
// The source's '0' key (a frustumCulled debug toggle) is not carried over.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const c3 = zg.zig3d;
const blit = zg.blit;
const M = @import("models.zig");
const Vec3 = c3.Vec3;

/// In the order screen.js tests them: the first one held wins.
pub const Key = enum { exit, ball, tnt, glider, carrier, union_logo };
pub const Keys = std.EnumSet(Key);

const APPROACH_END = -700;
const APPROACH_STEP = 10;
const CAMERA_OUT = 10000;
const CAMERA_STEP = 100;
const INIT_CAMERA_Z = 10; // new codef3D(canvas3D[0], 10, 25, 1, 10000)

/// The ball and one engine's projection scratch, ~36 KB: the scene places it in
/// free cart RAM, since a module-scope array is written into the cart's data
/// segment as zeros, `undefined` or not.
pub const Work = struct {
    ball: M.Ball,
    screen: [M.MAX_VERTS]c3.Screen,
    polys: [M.MAX_FACES]c3.Poly,
};

const Engine = struct { camera: Vec3, z: f64, rotation: Vec3 };

pub const Show = struct {
    work: *Work,
    lens: c3.Lens,
    shown: *const M.Model,
    next: *const M.Model, // nextObj*
    engines: [M.MAX_PARTS]Engine,
    count: usize, // currentObjNb
    spin: Vec3, // rotSpeed
    speed: Vec3, // currentObjRotSpeed
    changing: bool, // timeToChange
    exiting: bool, // timeToExit
    finished: bool, // me.state.change(MENU_LOADER) was reached

    pub fn init(self: *Show, work: *Work) void {
        self.work = work;
        work.ball.build();
        self.lens = c3.Lens.init(640, 400, 25, 1, 10000);
        self.shown = &M.TNT;
        self.next = &M.TNT;
        self.engines[0] = .{ .camera = .{ .x = 0, .y = 0, .z = INIT_CAMERA_Z }, .z = 0, .rotation = M.TNT.rotation };
        self.count = 1;
        self.spin = .{ .x = 0, .y = 0, .z = 0 };
        self.speed = M.TNT.speed;
        self.changing = false;
        self.exiting = false;
        self.finished = false;
    }

    pub fn update(self: *Show, keys: Keys) void {
        // draw() turns each engine after drawing it: last frame's turn lands here
        for (self.engines[0..self.count]) |*e| e.rotation = .{ .x = e.rotation.x + self.spin.x, .y = e.rotation.y + self.spin.y, .z = e.rotation.z + self.spin.z };
        if (self.engines[0].z > APPROACH_END) {
            for (self.engines[0..self.count]) |*e| e.z -= APPROACH_STEP;
            self.spin = .{ .x = 0, .y = 0, .z = 0 };
        } else self.spin = self.speed;
        if (self.changing) self.change();
        self.read(keys);
    }

    fn change(self: *Show) void {
        if (self.engines[0].camera.z < CAMERA_OUT) {
            for (self.engines[0..self.count]) |*e| e.camera.z += CAMERA_STEP;
            return;
        }
        if (self.exiting) self.finished = true;
        self.shown = self.next;
        self.count = self.next.parts.len;
        for (self.engines[0..self.count]) |*e| e.* = .{ .camera = self.next.camera, .z = 0, .rotation = self.next.rotation };
        self.speed = self.next.speed;
        self.changing = false;
    }

    fn read(self: *Show, keys: Keys) void {
        if (keys.contains(.exit)) {
            self.changing = true;
            self.exiting = true;
            return;
        }
        for ([_]Key{ .ball, .tnt, .glider, .carrier, .union_logo }) |k| if (keys.contains(k)) {
            self.next = self.model(k);
            self.changing = true;
            return;
        };
    }

    fn model(self: *const Show, k: Key) *const M.Model {
        return switch (k) {
            .exit, .tnt => &M.TNT, // exit never reaches here: ESC/SPACE leave instead
            .ball => &self.work.ball.model, // 3 / C
            .glider => &M.GLIDER, // 4 / D
            .carrier => &M.CARRIER, // 5 / E
            .union_logo => &M.UNION, // 1 / A
        };
    }

    /// Each engine renders into its own canvas, composited in engine order.
    pub fn draw(self: *const Show, dst: blit.Dst) void {
        const w = self.work;
        for (self.engines[0..self.count], self.shown.parts[0..self.count]) |e, *part| {
            const position = Vec3{ .x = 0, .y = 0, .z = e.z };
            const faces = c3.project(&self.lens, e.camera, position, e.rotation, part, &w.screen, &w.polys);
            for (faces) |p| zg.canvas_poly.fill(dst, p.pts[0..p.n], p.ink);
        }
    }
};
