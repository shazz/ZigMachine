// --------------------------------------------------------------------------
// The main loop's flight part, lines 50-67: the plane's sprite (or the
// pilot's parachute and the empty plane), the enemies, explosions, vehicles,
// then the plane's motion. sp# is the airspeed (a float); r the heading
// (0-15, 0 = left, 8 = right, dx() / dy() its direction); dx, dy integer
// steps (truncated) in pixels; x 0-319 across sectors sx 0-50; y 0-160 in
// layers al (0 = the ground layer).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const blast = @import("blast.zig");
const enemy = @import("enemy.zig");
const vehicles = @import("vehicles.zig");
const ground = @import("ground.zig");
const V = @import("vars.zig");
const v = &V.v;

fn ri() usize {
    return B.ix(16, v.r);
}

/// 50-54
pub fn sprites50() void {
    if (v.uc == 1 or (v.r != 0 and v.r != 8)) {
        v.wd = 0;
        v.wd2 = 0;
        v.wdx = 0;
    }
    v.s5 = 0;
    v.s14 = 0;
    if (v.bale == 0) {
        blast.smoke195();
        const img = v.s_a[ri()][B.ix(2, v.uc)] + v.wd_a[B.ix(2, B.div(v.r, 8))] * v.wd2 + v.wd;
        S.sprite_(1, v.x, v.y, img);
    } else {
        S.sprite_(1, v.px, v.py, v.pr);
        if (v.sx == v.psx and v.al == v.pal) {
            blast.smoke195();
            S.sprite_(2, v.x, v.y, v.s_a[ri()][B.ix(2, v.uc)]);
        } else S.sprite_(2, 999, 1, 38);
    }
    enemy.fly250();
    if (v.exf != 0 and v.gtg != 0) blast.pieces410();
    vehicles.show460();
    if (v.rqsx >= 0) ground.repair820();
    if (v.gtg2 != 0 and v.wd2 != 0) {
        v.wd += v.wdx;
        v.wd2 = B.sgn(v.wd);
        if (v.wd == 2) v.wdx = -1;
    }
}

/// 55: the step. Crashed, the plane keeps its last dx.
pub fn move55() void {
    v.xo2 = v.xo;
    v.yo2 = v.yo;
    v.xo = v.x;
    v.yo = v.y;
    const up = B.fl(B.abs(B.t(v.crsh == 0)));
    v.dx = B.ftoi(v.sp_f * B.fl(v.dx_a[ri()]) * B.F0_14 * up + B.fl(v.dxo * B.sgn(v.crsh)));
    v.dxo = v.dx;
    const fr = @max(0, @min(2, v.fre * v.gtg));
    const dyv = v.dy_a[ri()][B.ix(2, v.ld)];
    v.dy = B.ftoi((v.sp_f * B.fl(dyv) * B.F0_14 + B.fl(v.st) * 0.5 + B.fl(fr)) * up);
    v.x += v.dx;
    v.y += v.dy;
    if (v.y < 0) {
        v.y += 160;
        v.s2 = v.sx;
        v.nf = 1;
        v.al += 1;
        v.s3 = v.al;
    }
}

/// 56-58: across the screen edges.
pub fn wrap56() void {
    if (v.x > 319) {
        v.x -= 320;
        v.sx += 1;
        v.s2 = v.sx;
        v.s3 = v.al;
        v.nf = 1;
        if (v.sx > 50) {
            v.sx = 0;
            v.s2 = v.sx;
        }
    }
    if (v.x < 0) {
        v.x += 320;
        v.sx -= 1;
        v.s2 = v.sx;
        v.nf = 1;
        v.s3 = v.al;
        if (v.sx < 0) {
            v.sx = 50;
            v.s2 = v.sx;
        }
    }
    if (v.y > 160) {
        v.y = 0;
        v.s2 = v.sx;
        v.nf = 1;
        v.al -= 1;
        v.s3 = v.al;
    }
}

/// 60: airspeed: throttle, attitude, height, wheels, fire drag, the ground.
pub fn speed60() void {
    const dy0 = v.dy_a[ri()][0];
    var s = v.sp_f + B.fl(v.turbo * 2) + B.fl(v.th) * B.F0_1 + B.fl(dy0) * B.F0_15 - B.F0_1;
    s -= ((16.0 - B.fl(v.y) * B.F0_1) + B.fl(v.al * 16)) * B.F0_01;
    s -= B.fl(v.uc) * B.F0_03;
    s -= B.fl(B.div(@max(0, v.fre), 4));
    s += B.tf(v.al == 0 and v.y >= 154 and v.sp_f < 4) * B.F0_4;
    s += B.fl(v.steam);
    v.sp_f = s;
    const cap = v.mxsp + B.div(v.th, 3) + @max(0, B.div(dy0, 3)) + v.turbo * 2 - v.uc;
    v.sp_f = @max(0.0, @min(B.fl(cap), v.sp_f));
    if (v.sp_f < B.F0_3 and v.ld == 0 and v.cl == 0) v.st = 16;
}

/// 61-65: a stall drops the nose; slow flight sinks; landing gear down on
/// the runway over the ground (not water) sets ld.
pub fn stall61() void {
    if (v.st > 0) {
        v.st = B.ftoi(B.fl(v.st - 1) - v.sp_f / 4.0);
        v.st = @max(0, v.st);
        if (v.r < 4 or v.r > 12) v.ju = 1 else v.jd = 1;
    }
    if (v.sp_f < 9 and v.ld == 0) v.y = B.ftoi(B.fl(v.y) - v.sp_f / 4.5 + 2.0);
    if (v.ld == 1 and v.steam == 0 and (v.r == 1 or v.r == 7) and v.sp_f > 10) v.y -= 1;
    v.ld = 0;
    const on_strip = v.y >= v.gry - 1 and v.y < v.gry + 6 and v.x >= v.grlx and v.x <= v.grhx;
    const pt = S.point(v.x, v.y + 8);
    if (v.al == 0 and v.uc == 1 and on_strip and v.st == 0 and pt != 4 and (v.r < 2 or v.r == 7 or v.r == 8)) {
        v.ld = 1;
        v.st = 0;
    }
}

/// 67: bailed out: the plane stalls, the pilot drifts (210).
pub fn bale67() bool {
    if (v.bale == 0) return false;
    v.st = 16;
    return @import("pilot.zig").drift210();
}
