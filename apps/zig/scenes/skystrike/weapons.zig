// --------------------------------------------------------------------------
// FIRE (mouse key 2): 350-359 the guns (stick left: a bomb, 360-361; stick
// right: a rocket, 380-381), 390-391 an enemy hit; 365-379 the bomb falling
// (sprite 6; a cluster bomb hits three places), 550 a ground gun hit where
// it lands. The rocket in flight (420-450) is rocket.zig.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const hud = @import("hud.zig");
const sfx = @import("sfx.zig");
const vehicles = @import("vehicles.zig");
const ground = @import("ground.zig");
const V = @import("vars.zig");
const v = &V.v;

fn dxr() i32 {
    return v.dx_a[B.ix(16, v.r)];
}
fn dyr() i32 {
    return v.dy_a[B.ix(16, v.r)][0];
}

/// 350-359
pub fn fire350() void {
    if (S.jleft() != 0) return bomb360();
    if (S.jright() != 0) return rocket380();
    v.ammo -= 1;
    if (v.ammo < 0) {
        v.ammo = 0;
        return;
    }
    sfx.guns();
    v.a = 0;
    while (true) {
        const a = B.ix(2, v.a);
        if (v.esx_a[a] == v.sx and v.eal_a[a] == v.al and B.sgn(dxr()) == B.sgn(B.div(v.ex_a[a], 16) - B.div(v.x, 16)) and
            B.sgn(dyr()) == B.sgn(B.div(v.ey_a[a], 16) - B.div(v.y, 16))) hit390();
        v.a += 1;
        if (v.a >= 2) break;
    }
    if (v.al == 0 and v.r > 8) vehicles.strafe1510();
    // "brdf and brd < 4 and al and ...": AND is bitwise, so brdf & al
    if ((v.brdf & v.al) != 0 and v.brd < 4 and B.sgn(dxr()) == B.sgn(B.div(v.brx, 16) - B.div(v.x, 16)) and
        B.sgn(dyr()) == B.sgn(B.div(v.bry, 16) - B.div(v.y, 16)))
    {
        v.brd = 4;
        v.brdx = 0;
        v.mif_a[3] += 1;
        v.scre += 1;
        hud.score();
    }
}

/// 390-391: a hit, unless the dice say miss (better guns: b(0), b(1)).
fn hit390() void {
    if (S.rnd(100) < 70 - v.b_a[0]) return;
    sfx.bang();
    v.nso = 1;
    v.scre += 200;
    hud.score();
    const a = B.ix(2, v.a);
    v.fre_a[a] += 1 + v.b_a[1];
    v.a = 99;
}

/// 360-361
fn bomb360() void {
    if (v.bf != 0 or v.b_a[3] <= 0) return;
    v.bf = 1;
    v.b_a[3] -= 1;
    v.bdy = dyr();
    v.bdx = dxr();
    v.br = B.sgn(dxr());
    v.bx = v.x;
    v.by = v.y;
    v.bsx = v.sx;
    v.bal = v.al;
}

/// 380-381
fn rocket380() void {
    if (v.rkf != 0 or v.b_a[4] <= 0) return;
    v.rkf = 1;
    v.b_a[4] -= 1;
    v.rky = v.y;
    v.rkx = v.x;
    v.rkdx = dxr() * 4;
    v.rkdy = dyr() * 4;
    v.rkr = B.div(v.r, 2);
    v.rksx = v.sx;
    v.rkal = v.al;
    v.rkrg = 0;
}

fn bombOff() void {
    v.bf = 0;
    S.sprite_(6, 999, 1, 38);
}

/// 550: a gun hit under the bomb.
fn at550() void {
    v.ghx = @min(8, @max(1, B.div(v.bx, 32)));
    v.csx = v.bsx;
    v.cal = v.bal;
    ground.gunHit920();
}

/// 365-379
pub fn bomb365() void {
    if (v.bsx == v.sx and v.bal == v.al) S.sprite_(6, v.bx, v.by, 22 + v.br) else S.sprite_(6, 999, 1, 38);
    v.bdy = @min(8, v.bdy + 1);
    if (v.bdy == 8) v.br = 0;
    v.bx += v.bdx;
    v.by += v.bdy;
    if (v.bx < 0) {
        v.bsx -= 1;
        v.bx = 320;
        v.bsx = B.mod(v.bsx + 51, 51);
    }
    if (v.bx > 320) {
        v.bx = 0;
        v.bsx = B.mod(v.bsx + 1, 51);
    }
    if (v.by > 160) {
        v.bal -= 1;
        v.by = 0;
        if (v.bal < 0) {
            bombOff();
            at550();
            if (v.clus != 0) cluster(-32, 64);
        }
    }
    bombVehicles370();
    bombGround372();
}

fn cluster(first: i32, second: i32) void {
    v.bx += first;
    at550();
    v.bx += second;
    at550();
    v.clus = 0;
}

fn bombVehicles370() void {
    v.z = 0;
    while (true) {
        const z = B.ix(7, v.z);
        const w = v.vw_a[z] * 16;
        if (v.bal == 0 and v.bsx == v.vsx_a[z] and v.bx > v.vx_a[z] - w and v.bx < v.vx_a[z] + w and v.by > 144 and v.by < 176) {
            v.vh = v.z;
            v.by = 170;
            vehicles.wreck480();
            v.z = 999;
        }
        v.z += 1;
        if (v.z >= 4) break;
    }
}

fn bombGround372() void {
    if (!(v.bal == v.al and v.bal == 0 and v.bsx == v.sx)) return;
    v.b = S.zone(6);
    if (!(v.b > 2 and v.b < 61)) return;
    v.esy = 0;
    v.exf = 0;
    v.esx = v.bsx;
    v.ex = v.bx;
    v.ey = v.by;
    v.bx -= v.bdx;
    bombOff();
    at550();
    if (v.clus == 1) cluster(-32, 32);
}
