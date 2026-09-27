// --------------------------------------------------------------------------
// Ground vehicles (6 slots: 0-3 the trucks and their like, sprites 10-13;
// 6 is the wreck record of a crashed plane): 460-471 drive and draw, 480-489
// a wreck left in its sector (up to 4, with a fire 77/78), 490-491 the
// wrecks drawn, 930 / 980 a plane's wreck, 1510-1516 the guns' ground hits.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const hud = @import("hud.zig");
const sfx = @import("sfx.zig");
const boot = @import("boot.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 460-461: the vehicles in this sector, drawn and zoned (zones 126-123).
pub fn show460() void {
    v.a = 0;
    v.nvs = 0;
    while (true) {
        const a = B.ix(7, v.a);
        if (v.vsx_a[a] == v.sx and v.al == 0 and v.vs_a[a] > 0 and v.nvs < 4 and v.bale == 0) {
            S.sprite_(10 + v.nvs, v.vx_a[a], 160, v.vs_a[a]);
            v.nvs += 1;
            const w = v.vw_a[a] * 16;
            if (v.a < 4) S.setZone(127 - v.nvs, @max(0, @min(318, v.vx_a[a] - w)), 142, @min(319, @max(1, v.vx_a[a] + w)), 160);
        }
        v.a += 1;
        if (v.a == 6) break;
    }
    drive462();
}

/// 462-470: every vehicle moves; a truck reaching its depot costs 5000.
fn drive462() void {
    v.a = 0;
    while (v.a < 6) : (v.a += 1) {
        const a: usize = @intCast(v.a);
        if (v.vsx_a[a] == 999) continue;
        v.vx_a[a] += B.div(v.vdx_a[a], 2);
        if (v.vx_a[a] < 0) {
            v.vsx_a[a] -= 1;
            v.vx_a[a] += 320;
            if (v.vsx_a[a] < 0) v.vsx_a[a] = 400;
        }
        if (v.vx_a[a] > 319) {
            v.vsx_a[a] += 1;
            v.vx_a[a] -= 320;
            if (v.vsx_a[a] > 400) v.vsx_a[a] = 0;
        }
        v.vs_a[a] = v.vt_a[a] - v.vs_a[a];
        depot465(a);
    }
    park470();
}

fn depot465(a: usize) void {
    const t = scr.peek(v.sc9 + v.vsx_a[a] - 1);
    if (v.vt_a[a] == 150 and v.vx_a[a] < 40 + 80 * v.a and t > 8 and t < 18) {
        v.scre -= 5000;
        hud.score();
        boot.truck(a);
        v.vsx_a[a] = v.trksx;
    }
}

/// 470-471: the sprites left over parked; a hunted truck is the target.
fn park470() void {
    v.a = v.nvs;
    while (v.a < 4) : (v.a += 1) {
        S.sprite_(10 + v.a, 999, 1, 38);
        S.setZone(127 - v.a, 318, 198, 319, 199);
    }
    const m = v.mission;
    if (v.vs_a[0] > 0 and v.vsx_a[0] != 999 and (m == 11 or m == 10 or (m > 24 and m < 29))) v.tgtx = v.vsx_a[0];
}

/// 480-489: vehicle vh destroyed: points, its wreck and a fire recorded.
pub fn wreck480() void {
    const vh = B.ix(7, v.vh);
    v.scre += v.vpt_a[vh];
    hud.score();
    v.vsx = @min(400, v.vsx_a[vh]);
    addWreck(v.vb_a[vh], @max(32, @min(300, v.vx_a[vh])));
    addWreck(77 + S.rnd(1), 0);
    v.snox_a[B.ix(52, v.vsx)][B.ix(4, v.sn)] = @max(32, @min(300, v.vx_a[vh] + S.rnd(8) - S.rnd(8)));
    v.vsx_a[vh] = 999;
    v.vdx_a[vh] = 0;
    v.vcp_a[vh] = 0;
    if (v.vh < 4) {
        v.mif_a[11] += 1;
        v.mif_a[9] += 1;
    }
}

/// One wreck slot: the count in sno9, the image in so9, the x in snox.
fn addWreck(img: i32, x: i32) void {
    scr.poke(v.sno9 + v.vsx, @max(1, @min(4, scr.peek(v.sno9 + v.vsx) + 1)));
    v.sn = scr.peek(v.sno9 + v.vsx) - 1;
    scr.poke(v.so9 + v.vsx * 4 + v.sn, img);
    if (x != 0) v.snox_a[B.ix(52, v.vsx)][B.ix(4, v.sn)] = x;
}

/// 490-491: the wrecks of this sector (the fires flicker 77 <-> 78).
pub fn wrecks490() void {
    v.a = 0;
    while (true) {
        const at = v.so9 + v.sx * 4 + v.a;
        const img = scr.peek(at);
        if (img == 77 or img == 78 or v.gtg3 == 0) {
            S.sprite_(15, v.snox_a[B.ix(52, v.sx)][B.ix(4, v.a)], 160, img);
            S.update();
            S.putSprite(15);
            if (img == 77 or img == 78) scr.poke(at, 207 - img);
        }
        v.a += 1;
        if (v.a >= scr.peek(v.sno9 + v.sx)) break;
    }
    v.gtg3 = 1;
}

/// 930: an enemy crashed: its wreck (90-94) where it fell.
pub fn planeWreck930() void {
    const a = B.ix(2, v.a);
    v.vpt_a[6] = 0;
    v.vsx_a[6] = v.esx_a[a];
    v.vh = 6;
    v.vb_a[6] = 90 + S.rnd(4);
    v.vx_a[6] = v.ex_a[a];
    wreck480();
}

/// 980: the player's plane wrecked where it stands (image r + 1).
pub fn ownWreck980() void {
    v.vsx_a[6] = v.sx;
    v.vx_a[6] = v.x;
    v.vpt_a[6] = 0;
    v.vb_a[6] = v.r + 1;
    v.vh = 6;
    wreck480();
}

/// 1510-1516: a burst at the ground: its strike marks, and vehicles hit.
pub fn strafe1510() void {
    v.vy = v.gry + 4 - v.y;
    v.vx = B.div(v.vy, v.dy_a[B.ix(16, v.r)][0]) * v.dx_a[B.ix(16, v.r)];
    v.vx = B.ftoi(@as(f64, @floatFromInt(v.vx)) - @as(f64, @floatFromInt(B.sgn(v.vx) * (v.vy - 60))) * 1.5);
    v.xx = v.x + v.vx + S.rnd(8) - S.rnd(8);
    if (v.xx > v.grlx and v.xx < v.grhx) {
        v.ss = 29 + S.rnd(1);
        v.yy = v.gry + 4;
        O.stamp();
    }
    v.a = 0;
    while (v.a <= 3) : (v.a += 1) {
        const a: usize = @intCast(v.a);
        if (v.vs_a[a] > 0 and v.sx == v.vsx_a[a] and v.xx > v.vx_a[a] - 20 and v.xx < v.vx_a[a] + 20 and S.rnd(100) > 60) {
            v.vh_a[a] -= 1;
            v.ss = 77 + S.rnd(1);
            O.stamp();
            sfx.crash();
            v.nsa = 3;
            if (v.vh_a[a] <= 0) {
                v.vh = v.a;
                wreck480();
                v.a = 99;
            }
        }
    }
}
