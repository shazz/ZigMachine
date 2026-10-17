// --------------------------------------------------------------------------
// The "THE FATE" logo (screen.js dancingFate, 242-338): 113 two-row slices of
// the_fate.png, each placed on a 3D curve (y, z) that one of six waveforms
// computes, sorted by z, and drawn with a perspective x, width and y. It lives
// under the scroller: only the glyphs show it (see scroller.zig).
//
// Every constant and every float step is screen.js's own; the positions use
// f64 exactly as the JS numbers do, and ~~ is truncation toward zero.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");

pub const SLICES = 113; // i = 0..112
const ROWS = 112; // the_fate.png is 320x112: slice 111 is one row, 112 none
const SRC_W = 320;
const SPEED: f64 = 0.095; // fateSpeed
const INC: f64 = 0.018; // fateInc
const PERSP: f64 = 200; // fatePersp
const TOP = 286; // drawImage(..., ~~x, 286 + ~~y, ~~l, 2)
// Math.PI as a JS number: typed f64, so every expression using it rounds in
// f64 as the JS does (a bare std.math.pi would fold at comptime precision).
const PI: f64 = std.math.pi;

/// A unit vector turned by constant angles. Every waveform's angle is the
/// frame counter plus a constant per slice, so the frame needs no sin/cos:
/// the persistent rotors below are turned once a frame and each slice turns
/// a copy by INC (six f64 operations against a soft-float sine's hundreds).
/// The errors (~1e-15 a slice, ~1e-12 over a lap of the demo) sit below the
/// JavaScript's own accumulated rounding, and the gate replays 30000 frames.
const Rot = struct {
    c: f64,
    s: f64,

    fn of(a: f64) Rot {
        return .{ .c = @cos(a), .s = @sin(a) }; // comptime constants only
    }

    fn turn(r: Rot, by: Rot) Rot {
        return .{ .c = r.c * by.c - r.s * by.s, .s = r.s * by.c + r.c * by.s };
    }

    fn double(r: Rot) Rot {
        return .{ .c = r.c * r.c - r.s * r.s, .s = 2 * r.s * r.c };
    }
};
const INC_ROT = Rot.of(INC);
const INC2_ROT = Rot.of(INC * 2);
const INC5_ROT = Rot.of(INC * 5);
const INC_HALF_ROT = Rot.of(INC / 2);
const HALF_ROT = Rot.of(SPEED / 2); // ctr / 2 per frame
const THIRD_ROT = Rot.of(SPEED / 1.5); // ctr / 1.5 per frame
const SIN_120 = @sin(2 * PI / 3);
const COS_120 = @cos(2 * PI / 3);

/// One slice as drawImage places it, in canvas pixels.
pub const Slice = struct { i: u8, x: i32, y: i32, l: i32 };
const Pos = struct { i: u8, y: f64, z: f64 };

pub const Fate = struct {
    shown: bool,
    /// shown when step() last ran: ^CLogoFate; lands after it (in scroller()),
    /// so on that frame the JS has no slices to draw yet, and neither does this.
    placed: bool,
    wave: u8,
    half: Rot, // angle ctr / 2
    third: Rot, // angle ctr / 1.5
    slices: [SLICES]Slice, // in draw order: z ascending, stable

    pub fn init(self: *Fate) void {
        self.shown = false;
        self.placed = false;
        self.wave = 0;
        self.half = .{ .c = 1, .s = 0 };
        self.third = .{ .c = 1, .s = 0 };
        self.slices = undefined;
    }

    /// ^CLogoFate; — the logo appears on the first waveform.
    pub fn logoFate(self: *Fate) void {
        self.shown = true;
        self.wave = 0;
    }

    /// ^CLogoWaveform; — the next of the six curves.
    pub fn logoWaveform(self: *Fate) void {
        self.wave += 1;
        if (self.wave > 5) self.wave = 0;
    }

    /// dancingFate()'s maths for this frame; then fateCtr advances.
    pub fn step(self: *Fate) void {
        self.placed = self.shown;
        if (!self.shown) return;
        var pos: [SLICES]Pos = undefined;
        curve(self.wave, self.half, self.third, &pos);
        std.sort.insertion(Pos, &pos, {}, byZ); // stable, like V8's Array.sort
        for (&self.slices, pos) |*s, p| {
            s.* = .{
                .i = p.i,
                .x = trunc(600 * PERSP / (p.z + PERSP) - 357),
                .y = TOP + trunc(p.y * PERSP / (p.z + PERSP)),
                .l = trunc(264 + 5.6 * p.z),
            };
        }
        self.half = self.half.turn(HALF_ROT);
        self.third = self.third.turn(THIRD_ROT);
    }

    /// Draw the slices into `bg`, a `bg_w`-wide buffer whose (0, 0) is ST
    /// pixel (ox, oy). ST pixel (X, Y) is canvas pixel (2X, 2Y), so a slice
    /// shows only on its even canvas rows and columns.
    pub fn draw(self: *const Fate, bg: []u8, bg_w: usize, ox: i32, oy: i32) void {
        if (!self.placed) return;
        const bg_h: i32 = @intCast(bg.len / bg_w);
        for (self.slices) |s| {
            for (0..2) |dy| {
                const cy = s.y + @as(i32, @intCast(dy));
                const row = @as(usize, s.i) + dy;
                if (@mod(cy, 2) != 0 or row >= ROWS) continue;
                const by = @divExact(cy, 2) - oy;
                if (by < 0 or by >= bg_h) continue;
                const out = bg[@as(usize, @intCast(by)) * bg_w ..][0..bg_w];
                sliceRow(out, ox, s, A.fate.data[(row >> 1) * A.fate.w ..][0..A.fate.w]);
            }
        }
    }
};

/// One destination row of a slice: the 320-wide source row scaled to l
/// pixels the way Chrome's nearest-neighbour scaler steps it, a 16.16 source
/// x starting half a step in, the step truncated (measured against Chrome:
/// see gen4_3615_replay.mjs).
fn sliceRow(out: []u8, ox: i32, s: Slice, src: []const u8) void {
    if (s.l <= 0) return; // 264 + 5.6z >= 152 on every curve; drawImage would draw nothing
    const step: i64 = @divTrunc(@as(i64, SRC_W) << 16, s.l);
    const first = @max(@divFloor(s.x + 1, 2), ox); // first even canvas x >= s.x, as ST x
    const end = @min(@divFloor(s.x + s.l + 1, 2), ox + @as(i32, @intCast(out.len)));
    var X = first;
    while (X < end) : (X += 1) {
        const d: i64 = 2 * X - s.x;
        const u: usize = @intCast((@divFloor(step, 2) + d * step) >> 16);
        out[@intCast(X - ox)] = src[u >> 1];
    }
}

fn byZ(_: void, a: Pos, b: Pos) bool {
    return a.z < b.z;
}

fn trunc(v: f64) i32 {
    return @intFromFloat(@trunc(v));
}

/// The six waveforms (screen.js 248-323), filling pos[i] by index. `half` and
/// `third` are the rotors of fateCtr / 2 and fateCtr / 1.5.
fn curve(wave: u8, half: Rot, third: Rot, pos: *[SLICES]Pos) void {
    switch (wave) {
        0 => { // ROLL
            var a = half.double();
            var i: usize = SLICES;
            while (i > 0) : (a = a.turn(INC_ROT)) {
                i -= 1;
                pos[i] = .{ .i = @intCast(i), .y = 40 + 40 * a.c, .z = 10 * a.s };
            }
        },
        1 => {
            var a = half.double().turn(half); // ctr * 1.5
            var b = half;
            var i: usize = SLICES;
            while (i > 0) : ({
                a = a.turn(INC5_ROT);
                b = b.turn(INC_HALF_ROT);
            }) {
                i -= 1;
                pos[i] = .{ .i = @intCast(i), .y = @floatFromInt(i), .z = 20 + 5 * a.c + 12 * b.c };
            }
        },
        2 => rotatingFlat(third, pos),
        3 => { // BIG WAVE
            var a = half;
            var i: usize = SLICES;
            while (i > 0) : (a = a.turn(INC_ROT)) {
                i -= 1;
                const shifted = a.s * COS_120 - a.c * SIN_120; // sin(a - 2 PI / 3)
                pos[i] = .{ .i = @intCast(i), .y = 50 + 50 * a.c, .z = 20 + 20 * shifted };
            }
        },
        4 => { // FLIGHING CARPET
            var a = half.double();
            var i: usize = SLICES;
            while (i > 0) : (a = a.turn(INC2_ROT)) {
                i -= 1;
                const fi: f64 = @floatFromInt(i);
                pos[i] = .{ .i = @intCast(112 - i), .y = 70 + 20 * a.c - fi / 3, .z = (112 - fi) / 10 };
            }
        },
        else => { // 5, SIMPLE SINE
            var a = half;
            var i: usize = SLICES;
            while (i > 0) : (a = a.turn(INC_ROT)) {
                i -= 1;
                const fi: f64 = @floatFromInt(i);
                pos[i] = .{ .i = @intCast(i), .y = 50 + 60 * a.c, .z = (112 - fi) / 10 };
            }
        },
    }
}

/// Waveform 2: a flat logo rotating, the slices stepped from one end to the other.
/// cos(a + PI) = -cos(a), sin(a + PI) = -sin(a).
fn rotatingFlat(third: Rot, pos: *[SLICES]Pos) void {
    var py = 50 + 30 * third.c;
    var pz = 20 * third.s;
    const iy = ((50 - 30 * third.c) - py) / 112;
    const iz = ((-20 * third.s) - pz) / 112;
    for (pos, 0..) |*p, i| {
        p.* = .{ .i = @intCast(i), .y = py, .z = pz };
        py += iy;
        pz += iz;
    }
}
