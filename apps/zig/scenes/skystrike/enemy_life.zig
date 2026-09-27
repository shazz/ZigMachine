// --------------------------------------------------------------------------
// An enemy's life: 300-315 (take off from the enemy airfield nearest the
// player, 870-879), 316-317 (crashed: the kill, its wreck, maybe a ground
// gun smashed where it fell, then a new one), 320 (it fires: the gun sample,
// and it may hit), 330-332 (the kill: points, a bonus crate now and then).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const blast = @import("blast.zig");
const damage = @import("damage.zig");
const vehicles = @import("vehicles.zig");
const ground = @import("ground.zig");
const hud = @import("hud.zig");
const sfx = @import("sfx.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 300: both enemies anew.
pub fn both300() void {
    v.a = 0;
    while (v.a <= 1) : (v.a += 1) spawn310();
}

/// 310-315: from a base (870), level, engine off, heading 0, images 80+.
pub fn spawn310() void {
    base870();
    const a = B.ix(2, v.a);
    v.st_a[a] = 0;
    v.eth_a[a] = 0;
    v.fre_a[a] = 0;
    v.ex_a[a] = 270;
    v.ey_a[a] = 154;
    v.er_a[a] = 0;
    v.esp_a[a] = 0;
    v.ea_a[a] = 80;
    v.ebale_a[a] = 0;
    v.brk = 0;
}

/// 870-879: the nearest enemy airfield (bse = 1) whose first two guns
/// stand, searched both ways; none: in the air near the player.
fn base870() void {
    v.a1 = B.div(v.sx, 10);
    v.a2 = v.a1;
    v.f = 0;
    while (true) {
        probe(v.a1);
        probe(v.a2);
        if (v.f == 0) {
            v.a2 += 1;
            v.a1 -= 1;
            v.a1 = B.mod(v.a1 + 6, 6);
            v.a2 = B.mod(v.a2, 51);
        }
        if (v.f == 0 and v.a1 == B.div(v.sx, 10)) v.f = 999;
        if (v.f != 0) break;
    }
    v.a = @max(0, @min(1, v.a));
    place875();
}

fn probe(i: i32) void {
    if (v.bse_a[B.ix(42, i)] != 1) return;
    v.g = scr.peek(v.ghx9 + i * 10);
    if (v.g & 192 == 0) v.f = i;
}

fn place875() void {
    const a = B.ix(2, v.a);
    if (v.f == 999) {
        v.mif_a[24] = 1;
        v.esx_a[a] = v.sx + S.rnd(4) - S.rnd(4);
        v.eal_a[a] = S.rnd(3);
    }
    if (v.f <= 40) {
        v.esx_a[a] = v.f * 10;
        v.eal_a[a] = 0;
    }
    if (v.esx_a[a] < v.sx - 15) v.esx_a[a] = @max(0, v.sx - 15);
    if (v.esx_a[a] > v.sx + 15) v.esx_a[a] = @min(50, v.sx + 15);
}

/// 316-317: enemy a hit the ground.
pub fn crashed316() void {
    v.tta = v.a;
    v.brk = 1;
    kill330();
    const a = B.ix(2, v.a);
    v.esy = 0;
    v.esx = v.esx_a[a];
    v.ex = v.ex_a[a];
    v.ey = v.eyo_a[a];
    damage.water650();
    blast.explode400();
    const dice = S.rnd(10) > 7;
    if (dice and v.ew == 0) {
        v.csx = v.esx;
        v.cal = 0;
        v.ghx = @max(1, @min(8, B.div(v.ex, 32) + S.rnd(1) - S.rnd(1)));
        ground.gunHit920();
        vehicles.planeWreck930();
    }
    v.a = v.tta;
    spawn310();
}

/// 320: the guns fire; maybe a hit.
pub fn shoot320() void {
    sfx.guns();
    if (S.rnd(100 + v.dl * 7) > 85) damage.hit600();
}

/// 330-332: a kill (it was burning): 2000 points, maybe a crate.
fn kill330() void {
    const a = B.ix(2, v.a);
    if (v.fre_a[a] > 0) {
        v.kls += 1;
        v.mif_a[2] += 1;
        hud.kills720();
        v.scre += 2000;
        hud.score();
        if (S.rnd(4) <= 2 and v.bnf == 0) crate(S.rnd(8) + 2);
    }
    if (B.mod(v.kls, 100) == 0 and v.kls > 0) {
        startCrate();
        v.bns = 11;
    }
}

fn startCrate() void {
    v.bnf = 1;
    v.bosx = v.sx;
    v.boal = v.al;
    v.bnx = 160;
    v.bny = 0;
}

fn crate(kind: i32) void {
    startCrate();
    v.bns = kind;
    if (S.rnd(8) >= 6) {
        v.bns = 13 + S.rnd(2);
        if (S.rnd(4) == 1) v.bns = 12;
    }
}
