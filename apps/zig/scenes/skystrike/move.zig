// --------------------------------------------------------------------------
// STOS's interrupt-driven sprite programs, run in the system VBL ($3D2C2):
//
//   MOVE X n,"(speed,step,count)...L"   every `speed` VBLs the sprite's x
//        moves by `step`, `count` times, then the next group; L loops
//   ANIM n,"(image,delay)...L"          each image held `delay` VBLs
//   MOVE ON / ANIM ON start them, OFF (and the sprite reset) stops them.
//
// The game uses three: the title plane's flight (sprite 2), its image
// changes, and the waving base flag (sprite 1) on the title screen.
// --------------------------------------------------------------------------
const sprite = @import("sprite.zig");

const MAXS = 8;
pub const Prog = struct {
    a: [MAXS]i32 = undefined, // move: speed / anim: image
    b: [MAXS]i32 = undefined, // move: step  / anim: delay
    c: [MAXS]i32 = undefined, // move: count
    n: usize = 0,
    loop: bool = false,
};

const Run = struct {
    prog: Prog = .{},
    set: bool = false,
    on: bool = false,
    i: usize = 0,
    left: i32 = 0, // VBLs to the next step
    times: i32 = 0, // steps left in this group (move)
};

var mv: [16]Run = [_]Run{.{}} ** 16;
var an: [16]Run = [_]Run{.{}} ** 16;

pub fn reset() void {
    mv = [_]Run{.{}} ** 16;
    an = [_]Run{.{}} ** 16;
}

pub fn moveX(n: usize, p: Prog) void {
    mv[n] = .{ .prog = p, .set = true };
}

pub fn anim(n: usize, p: Prog) void {
    an[n] = .{ .prog = p, .set = true };
    an[n].on = true; // ANIM n starts at once (ANIM ON is for all)
    an[n].left = 0;
}

pub fn moveOn() void {
    for (&mv) |*r| if (r.set and !r.on) {
        r.on = true;
        r.i = 0;
        r.left = r.prog.a[0];
        r.times = r.prog.c[0];
    };
}

pub fn animOn() void {
    for (&an) |*r| if (r.set) {
        r.on = true;
    };
}

/// OFF: every movement and animation stopped.
pub fn off() void {
    for (&mv) |*r| r.on = false;
    for (&an) |*r| r.on = false;
}

fn stepMove(n: usize, r: *Run) void {
    r.left -= 1;
    if (r.left > 0) return;
    const s = &sprite.spr[n];
    s.x += r.prog.b[r.i];
    sprite.dirty = true;
    r.times -= 1;
    if (r.times <= 0) {
        r.i += 1;
        if (r.i >= r.prog.n) {
            if (!r.prog.loop) {
                r.on = false;
                return;
            }
            r.i = 0;
        }
        r.times = r.prog.c[r.i];
    }
    r.left = r.prog.a[r.i];
}

fn stepAnim(n: usize, r: *Run) void {
    r.left -= 1;
    if (r.left > 0) return;
    if (r.i >= r.prog.n) {
        if (!r.prog.loop) {
            r.on = false;
            return;
        }
        r.i = 0;
    }
    sprite.spr[n].img = r.prog.a[r.i];
    sprite.dirty = true;
    r.left = r.prog.b[r.i];
    r.i += 1;
}

pub fn vbl() void {
    for (&mv, 0..) |*r, n| if (r.on) stepMove(n, r);
    for (&an, 0..) |*r, n| if (r.on) stepAnim(n, r);
}
