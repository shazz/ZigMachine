// --------------------------------------------------------------------------
// CHISEL v2 test cart: the keys that play with the three texture modes, and the
// state they move. Every number is an integer (Q16.16 positions, zg.fixtrig
// angles); a frame adds the speeds to the phases (step), the modes read them.
// With no key pressed the phases run exactly as the old `t`-based formulas did:
// the default pictures are the same pixels as before the keys existed.
//   P  texture: generated (128) or the parrot photo    T  photo size 64/128/256
//   F  pause                                            X  reset this mode's keys
//   ROTOZOOM  + / - spin, R reverse, I / O zoom in / out, arrows pan the centre
//   MODE 7    left / right turn, up / down drive, + / - camera height
//   TUNNEL    up / down speed, left / right roll, R reverse the roll, B bend
// --------------------------------------------------------------------------
const trig = @import("zigos").fixtrig;

const K_UP: u32 = 0xE020;
const K_DOWN: u32 = 0xE021;
const K_LEFT: u32 = 0xE022;
const K_RIGHT: u32 = 0xE023;

/// The rotozoom's zoom, Q8 (256 = the original): ~2^(k/3) from 1/4 to 4.
pub const ZOOMS = [_]i64{ 64, 81, 102, 128, 161, 203, 256, 323, 406, 512, 645, 813, 1024 };
const ZOOM0: u8 = 6;
pub const HEIGHT0: i32 = 64; // Mode 7's camera height (the per-row reciprocal's numerator)

pub const Roto = struct { spin: i32 = 4, angle: u32 = 0, zoom: u8 = ZOOM0, pan_u: i64 = 0, pan_v: i64 = 0 };
pub const Floor = struct { turn: i32 = 2, heading: u32 = 0, speed: i32 = 0, driven: bool = false, pos_u: i64 = 0, pos_v: i64 = 0, height: i32 = HEIGHT0 };
pub const Tube = struct { speed: i32 = 3, roll: i32 = 1, u: u16 = 0, v: u16 = 0, bend: u8 = 0 };

pub const Play = struct {
    photo: bool = false,
    log: u4 = 7, // the photo's side, 2^log (6, 7, 8); the generated texture is 128
    frozen: bool = false,
    roto: Roto = .{},
    floor: Floor = .{},
    tube: Tube = .{},

    /// One frame of motion (not called while paused).
    pub fn step(p: *Play) void {
        p.roto.angle +%= @bitCast(p.roto.spin *% (1 << 22)); // 4: the old t * 2^24
        const f = &p.floor;
        f.heading +%= @bitCast(f.turn *% (1 << 22)); // 2: the old t * 2^23
        if (f.driven) { // along the heading, half a texel a frame a speed step
            f.pos_u += (@as(i64, f.speed) * trig.sin(f.heading)) >> 1;
            f.pos_v += (@as(i64, f.speed) * trig.cos(f.heading)) >> 1;
        } else f.pos_u += 3 << 15; // the old drift, until the arrows take over
        p.tube.u +%= @truncate(@as(u32, @bitCast(p.tube.roll)));
        p.tube.v +%= @truncate(@as(u32, @bitCast(p.tube.speed)));
    }

    /// A key in `mode` (0 ROTOZOOM, 1 MODE 7, 2 TUNNEL); true when it was one of ours.
    pub fn key(p: *Play, mode: u8, cp: u32) bool {
        switch (cp) {
            'p', 'P' => p.photo = !p.photo,
            't', 'T' => p.log = if (p.log >= 8) 6 else p.log + 1,
            'f', 'F' => p.frozen = !p.frozen,
            'x', 'X' => p.reset(mode),
            else => return switch (mode) {
                0 => rotoKey(&p.roto, cp),
                1 => floorKey(&p.floor, cp),
                2 => tubeKey(&p.tube, cp),
                else => false,
            },
        }
        return true;
    }

    /// The mode's speeds, zoom, pan, height and bend back to the defaults; the phases go on.
    fn reset(p: *Play, mode: u8) void {
        switch (mode) {
            0 => p.roto = .{ .angle = p.roto.angle },
            1 => p.floor = .{ .heading = p.floor.heading, .pos_u = p.floor.pos_u, .pos_v = p.floor.pos_v, .driven = p.floor.driven },
            2 => p.tube = .{ .u = p.tube.u, .v = p.tube.v },
            else => {},
        }
    }
};

fn rotoKey(r: *Roto, cp: u32) bool {
    const c: i64 = trig.cos(r.angle);
    const s: i64 = trig.sin(r.angle);
    switch (cp) {
        '+', '=' => r.spin = @min(r.spin + 1, 16),
        '-', '_' => r.spin = @max(r.spin - 1, -16),
        'r', 'R' => r.spin = -r.spin,
        'i', 'I' => r.zoom -|= 1,
        'o', 'O' => r.zoom = @min(r.zoom + 1, ZOOMS.len - 1),
        // 8 texels along the screen's axes: x runs (cos, sin), y runs (-sin, cos)
        K_RIGHT, K_LEFT => pan(r, if (cp == K_RIGHT) 8 else -8, c, s),
        K_DOWN, K_UP => pan(r, if (cp == K_DOWN) 8 else -8, -s, c),
        else => return false,
    }
    return true;
}

fn pan(r: *Roto, n: i64, du: i64, dv: i64) void {
    r.pan_u += n * du;
    r.pan_v += n * dv;
}

fn floorKey(f: *Floor, cp: u32) bool {
    switch (cp) {
        K_LEFT => f.turn = @max(f.turn - 1, -8),
        K_RIGHT => f.turn = @min(f.turn + 1, 8),
        K_UP, K_DOWN => {
            f.driven = true;
            f.speed = if (cp == K_UP) @min(f.speed + 1, 16) else @max(f.speed - 1, -16);
        },
        '+', '=' => f.height = @min(f.height + 8, 160),
        '-', '_' => f.height = @max(f.height - 8, 16),
        else => return false,
    }
    return true;
}

fn tubeKey(t: *Tube, cp: u32) bool {
    switch (cp) {
        K_UP => t.speed = @min(t.speed + 1, 16),
        K_DOWN => t.speed = @max(t.speed - 1, -16),
        K_LEFT => t.roll = @max(t.roll - 1, -8),
        K_RIGHT => t.roll = @min(t.roll + 1, 8),
        'r', 'R' => t.roll = -t.roll,
        'b', 'B' => t.bend = (t.bend + 1) % 4,
        else => return false,
    }
    return true;
}

/// The key list under the mode's name (the cart's header says what each does).
pub fn help(mode: u8) []const u8 {
    return switch (mode) {
        0 => "KEYS P T F X  +- R  I O  ARROWS",
        1 => "KEYS P T F X  ARROWS  +-",
        2 => "KEYS P T F X  ARROWS  R B",
        else => "KEYS F",
    };
}
