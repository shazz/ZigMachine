// --------------------------------------------------------------------------
// Lines 420-450: the rocket in flight (sprite 7, 20 passes of range): its
// sector and layer wrap, what it hits (an enemy: +2000; a vehicle; a ground
// gun at 450 when it comes down). FIRE with the stick right launches it
// (weapons.zig, 380-381).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const hud = @import("hud.zig");
const vehicles = @import("vehicles.zig");
const ground = @import("ground.zig");
const V = @import("vars.zig");
const v = &V.v;

fn rocketOff() void {
    v.rkf = 0;
    S.sprite_(7, 999, 1, 38);
}

/// 450: a gun hit under the rocket.
fn at450() void {
    v.ghx = @min(8, @max(1, B.div(v.rkx, 32)));
    v.csx = v.rksx;
    v.cal = v.rkal;
    ground.gunHit920();
}

/// 420-439
pub fn rocket420() void {
    if (v.rksx == v.sx and v.rkal == v.al) S.sprite_(7, v.rkx, v.rky, 50 + v.rkr) else S.sprite_(7, 999, 1, 38);
    v.rkx += v.rkdx;
    v.rky += v.rkdy;
    v.rkrg += 1;
    if (v.rkx < 0) {
        v.rksx -= 1;
        v.rkx = 320;
        v.rksx = B.mod(v.rksx + 51, 51);
    }
    if (v.rkx > 320) {
        v.rkx = 0;
        v.rksx = B.mod(v.rksx + 1, 51);
    }
    if (v.rky < 0) {
        v.rky = 176;
        v.rkal += 1;
    }
    if (v.rky > 176) {
        v.rky = 0;
        v.rkal -= 1;
        if (v.rkal == -1) {
            at450();
            rocketOff();
        }
    }
    if (v.rkrg > 20) return rocketOff();
    rocketHits426();
}

fn rocketHits426() void {
    v.a = 0;
    while (true) {
        const a = B.ix(2, v.a);
        if (v.rksx == v.esx_a[a] and v.rkal == v.eal_a[a] and v.rkx > v.ex_a[a] - 16 and v.rkx < v.ex_a[a] + 16 and
            v.rky > v.ey_a[a] - 16 and v.rky < v.ey_a[a] + 16)
        {
            v.fre_a[a] += 5;
            v.scre += 2000;
            hud.score();
            rocketOff();
        }
        v.a += 1;
        if (v.a == 2) break;
    }
    rocketVehicles430();
    if (v.rksx == v.sx and v.rkal == v.al and v.al == 0) {
        v.b = S.zone(7);
        if (v.b > 2 and v.b < 60) {
            v.rky = 180;
            v.rkx -= v.rkdx;
            at450();
            rocketOff();
        }
    }
}

fn rocketVehicles430() void {
    v.z = 0;
    while (true) {
        const z = B.ix(7, v.z);
        const w = v.vw_a[z] * 16;
        if (v.rkal == 0 and v.rksx == v.vsx_a[z] and v.rkx > v.vx_a[z] - w and v.rkx < v.vx_a[z] + w and v.rky > 144 and v.rky < 176) {
            v.vh = v.z;
            v.rky = 180;
            vehicles.wreck480();
            v.z = 999;
        }
        v.z += 1;
        if (v.z >= 4) break;
    }
}
