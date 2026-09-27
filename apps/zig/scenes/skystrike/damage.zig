// --------------------------------------------------------------------------
// Lines 500-520 (flak: a burst of smoke puffs near the plane), 600-645
// (a hit: one of 19 damages at random, its message on line 3), 650-656 (is
// an explosion over water? colour 4 under it).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const scene = @import("scene.zig");
const sfx = @import("sfx.zig");
const blast = @import("blast.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 500-502: a flak burst appears (the "fy > fy - 2" test is the original's).
pub fn flak500() void {
    sfx.bang();
    v.fx = S.rnd(200) + 60;
    v.fy = S.rnd(100) + 10 + v.al * 10;
    v.flf = 1;
    v.fv = 0;
    v.fdv = 1;
    if (v.fx > v.x - 2 and v.fx < v.x + 2 and v.fy > v.fy - 2 and v.fy < v.y + 2) hit600();
}

fn puff(img: i32) void {
    v.xx = v.fx;
    v.yy = v.fy;
    v.ss = img;
    O.stamp();
}

/// 505-520: the burst's two puffs, then it hurts if close.
pub fn flak505() void {
    puff(66 + v.fv);
    v.fx += S.rnd(6) - 3;
    v.fy += -S.rnd(7) + 2;
    v.fv += 1;
    S.putSprite(15);
    if (v.fv >= 2) {
        v.fv = 1;
        S.sprite_(15, 999, 1, 38);
        v.flf = 0;
    }
    puff(66 + v.fv);
    v.fv += 1;
    if (v.fv >= 2) {
        puff(67);
        v.flf = 0;
    }
    if (v.fx >= v.x - 4 and v.fx <= v.x + 4 and v.fy >= v.y - 4 and v.fy < v.y + 4) hit600();
    if (v.fx >= v.x - 32 and v.fx <= v.x + 32 and v.fy >= v.y - 32 and v.fy < v.y + 32 and S.rnd(100) > 67) hit600();
}

/// 600-602
pub fn hit600() void {
    sfx.bang();
    v.nso = 2;
    v.h = S.rnd(18);
    const table = [19]u8{ 0, 0, 0, 6, 6, 0, 0, 6, 1, 2, 3, 5, 6, 7, 8, 4, 2, 1, 6 };
    damage(table[@intCast(v.h)]);
    scene.message1505();
    if (v.fre > 4) {
        v.esx = v.sx;
        v.esy = v.al;
        v.ex = v.x;
        v.ey = v.y;
        v.esf = 0;
        blast.explode400();
    }
}

/// 605 fire, 610 guns, 615 fuel, 620 guns damaged, 625 fire, 630 wheels,
/// 635 engine, 640 bombs, 645 rockets.
fn damage(k: u8) void {
    switch (k) {
        0 => {
            v.fre += 1;
            v.mes_s.set("On Fire !");
        },
        1 => {
            v.ammo = 0;
            v.mes_s.set("Guns Destroyed !");
        },
        2 => {
            v.leak += 50;
            v.mes_s.set("Fuel Hit !");
        },
        3 => {
            v.b_a[0] -= 5;
            v.mes_s.set("Guns Damaged !");
        },
        4 => {
            v.fre += S.rnd(2);
            v.mes_s.set("On Fire !");
        },
        5 => {
            v.ufail = 1;
            v.uc = 0;
            v.mes_s.set("Wheels Hit !");
        },
        6 => {
            v.mxsp -= 1;
            v.mes_s.set("Engine Hit !");
        },
        7 => {
            v.b_a[3] = 0;
            v.mes_s.set("Bombs Lost !");
        },
        else => {
            v.b_a[4] = 0;
            v.mes_s.set("Rockets Lost !");
        },
    }
}

/// 650-656: ew = 1 when the explosion at ex (sector esx) is over water.
pub fn water650() void {
    v.ew = 0;
    if (!(v.al == 0 and v.sx == v.esx)) {
        if (scr.peek(v.sc9 + v.esx) == 10) v.ew = 1;
        if (v.al != 0 or v.sx != v.esx) return;
    }
    if (S.point(v.ex, 167) == 4 or S.point(v.ex, 162) == 4) v.ew = 1;
}

