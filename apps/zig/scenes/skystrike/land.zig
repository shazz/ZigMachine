// --------------------------------------------------------------------------
// The main loop, lines 68-89: a crash-landing stopped (68), hitting the
// ground (70-71, zone 1), a belly landing (72-73, zone 2), the wreck's fire
// (74-75), fuel (77-78), ground fire (79, zones 3-60 / 124+), the stick
// (80-83), FIRE (84), the engine note (85-87), the carrier (88-89).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const blast = @import("blast.zig");
const damage = @import("damage.zig");
const weapons = @import("weapons.zig");
const vehicles = @import("vehicles.zig");
const hud = @import("hud.zig");
const scene = @import("scene.zig");
const sfx = @import("sfx.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const Next = enum { on, to34, to56, to225, wait88 };

/// 68-71
pub fn ground68() Next {
    if (v.cl == 1 and v.sp_f < 1 and v.crsh == 0) {
        v.planes -= 1;
        vehicles.ownWreck980();
        return if (v.planes > 0) .to34 else .to225;
    }
    if (v.al < 0 and v.crsh != 0) v.al = 0;
    if (v.cl == 0 and v.crsh == 0) {
        v.c = S.zone(1);
        if (v.c == 1 or (v.al < 0 and v.crsh == 0)) {
            v.crsh = 1;
            v.nf = 0;
            sfx.crash();
            v.al = 0;
            v.s3 = 0;
            v.y = 160;
            v.yo = v.y;
            v.dy = 0;
            v.nso = 2;
            return .to56;
        }
    }
    return crashing71();
}

fn crashing71() Next {
    if (v.crsh == 0) return .on;
    v.al = 0;
    v.fuel = 0;
    v.th = 0;
    v.th2 = 0;
    v.y = 154;
    v.jd = 1;
    blast.burn205();
    v.crsh += 1;
    if (v.crsh > 16) {
        v.dx = 0;
        if (v.bale == 0) return .to225;
    }
    return .on;
}

/// 74: while crashing, now and then a fireball thrown off (en of them, at
/// most 4). "crsh and rnd(5) and en < 4" is bitwise: RND is always drawn.
fn debris() void {
    const r5 = S.rnd(5);
    if ((v.crsh & r5 & B.t(v.en < 4)) == 0) return;
    v.en += 1;
    const e = B.ix(5, v.en);
    v.exx_a[e] = v.x;
    v.exy_a[e] = v.y;
    v.exdx_a[e] = -v.dx + S.rnd(16) - 8;
    v.exdy_a[e] = -S.rnd(32);
}

/// 72-79
pub fn touch72() void {
    v.cl = 0;
    v.c = S.zone(1);
    const nose = v.r < 2 or v.r == 7 or v.r == 8;
    if (v.c == 2 and nose and v.al == 0 and v.uc == 0 and v.crsh == 0 and v.sp_f < 7) {
        v.cl = 1;
        v.sp_f -= B.F0_2;
        v.y = v.yo;
        v.fre += 1;
        S.sprite_(15, v.x, v.y, 67);
        S.update();
        S.putSprite(15);
        if (S.rnd(1) != 0) {
            sfx.hit();
            v.nso = 1;
        }
    }
    if (v.c == 2 and v.al == 0 and v.uc == 0 and v.crsh == 0 and (v.sp_f >= 7 or (v.r > 1 and v.r != 7 and v.r != 8))) v.crsh = 1;
    debris();
    if (v.en != 0) blast.fireballs200();
    if (v.fre > 3 and v.cl == 0 and v.ld == 0) {
        if (v.r > 4 and v.r < 12) v.jd = 1 else v.ju = 1;
    }
    fuel77();
    shotAt79();
}

/// 77-78
fn fuel77() void {
    v.fuel = v.fuel - B.ftoi(@floor(B.fl(v.th) / 2.0 + 0.5)) - v.leak;
    if (v.fuel <= 0) {
        v.fuel = 0;
        v.th = 0;
        if (v.fw == 0) {
            v.fw = 1;
            S.ink(1);
            S.bar(160, 188, 168, 192);
        }
    }
    v.fuxo = v.fux;
    v.fux = B.div(v.fuel, 200);
    if (v.fux != v.fuxo) hud.fuel();
}

/// 79: low over the ground layer inside a gun's zone: three hits.
fn shotAt79() void {
    if (!(v.nf == 0 and v.al == 0 and v.crsh == 0)) return;
    v.cz = S.zone(1);
    if ((v.cz > 2 and v.cz < 61) or v.cz > 123) {
        v.kz = v.cz;
        v.fre += 1;
        damage.hit600();
        damage.hit600();
        damage.hit600();
    }
}

/// 80-87
pub fn stick80() void {
    const free_ = v.bale == 0 and v.steam == 0;
    if (((free_ and S.jup() != 0) or v.ju != 0) and v.gtg == 0) {
        v.ju = 0;
        v.r2 -= 1;
        if (v.r2 < 0) {
            v.r2 = 15;
            v.r = 15;
        } else v.r = v.r2;
    }
    if (((free_ and S.jdown() != 0) or v.jd != 0) and v.gtg == 0) {
        v.jd = 0;
        v.r2 = B.mod(v.r2 + 1, 16);
        v.r = v.r2;
    }
    if (S.jleft() != 0 and v.bale == 1 and v.pr == 63) v.px = @max(0, v.px - 4);
    if (S.jright() != 0 and v.bale == 1 and v.pr == 63) v.px = @min(319, v.px + 4);
    if (S.mouseKey() == 2 and v.bale == 0) weapons.fire350();
    v.oen = v.eng;
    v.eng = (10 - B.div(v.th, 2)) * 8 - B.ftoi(@floor(v.sp_f));
    if (v.eng != v.oen or v.nso == 1) sfx.engine();
    if (v.nso != 0) v.nso -= 1;
    if (v.steam != 0) {
        v.steam -= 1;
        sfx.hit();
    }
}

/// 88: caught by the carrier's wire (zone 62): 1000 points, then WAIT 5.
pub fn caught88() bool {
    if (!(v.cz == 62 and v.r == 1 and v.ld == 1 and v.arr == 0)) return false;
    v.arr = 1;
    v.sp_f -= 3;
    v.scre += 1000;
    v.mes_s.set("CAUGHT ! BONUS 1000");
    scene.message1505();
    v.mif_a[5] = 1;
    v.sp_f = @max(0.0, v.sp_f);
    return true;
}

/// 88 (after the wait), 89
pub fn after88(waited: bool) void {
    if (waited) {
        v.mes_s.set("<--- TAXI LEFT FOR LAUNCH.");
        scene.message1500();
    }
    if (v.cz == 62 and v.ld == 1 and v.r > 1) {
        v.mes_s.set("BAD LANDING !");
        v.arr = -1;
        scene.message1505();
        v.scre -= 500;
        hud.score();
    }
}
