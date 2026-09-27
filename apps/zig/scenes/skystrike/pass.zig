// --------------------------------------------------------------------------
// The main loop's end, lines 91-147 (90's keys and 101's landing are the
// flow's, loop.zig): taxiing, the ships settling, the bridge dare, flak,
// the flag, bombs / crates / rockets, the frame counters, W, the arrester
// net, the enemy pilot, the arrow, throttle, repairs, cluster, turbo, TIMER.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const keys = @import("keys.zig");
const seas = @import("seatypes.zig");
const damage = @import("damage.zig");
const weapons = @import("weapons.zig");
const bonus = @import("bonus.zig");
const pilot = @import("pilot.zig");
const hud = @import("hud.zig");
const scene = @import("scene.zig");
const net = @import("net.zig");
const V = @import("vars.zig");
const v = &V.v;

fn k(s: []const u8) bool {
    return v.k_s.eql(s);
}

/// 92 / 116: taxiing slowly the plane sits level on the runway.
fn taxi92() void {
    if (!(v.ld == 1 and v.sp_f < 7)) return;
    v.y = v.gry;
    if (v.r < 4) {
        v.r = 1;
        v.r2 = 1;
    } else if (v.r >= 4) {
        v.r = 7;
        v.r2 = 7;
    }
}

/// 91-99
pub fn part91() void {
    if (S.rnd(1) != 0) keys.flak165();
    taxi92();
    if (v.carsnk > 0 and v.carsnk < 16) seas.settle(&v.carsnk, 12, 13, 13);
    if (v.btlsnk > 0 and v.btlsnk < 16) seas.settle(&v.btlsnk, 2, 3, 4);
    if (v.mission == 20) {
        if (scr.peek(v.sc9 + v.sx) == 8 and v.y > 140 and v.ld == 0 and v.x > 140 and v.x < 180) v.mif_a[20] = 1;
    }
    if (v.cz == 60 and v.r > 1) {
        v.mes_s.set("BAD LANDING !");
        scene.message1505();
        v.scre -= 500;
        hud.score();
    }
    if (v.flf != 0) damage.flak505();
}

/// 101's test: stopped on our airfield (or on the carrier types 13/14).
pub fn atBase101() bool {
    const t = scr.peek(v.sc9 + v.sx);
    const home = (t == 1 and v.bse_a[B.ix(42, B.div(v.sx, 10))] == -1) or t == 13 or t == 14;
    return v.ld != 0 and v.sp_f <= 0 and home;
}

/// 102-118
pub fn part102() void {
    if (v.flgf != 0) {
        if (S.rnd(1) != 0) v.flgf = 3 - v.flgf;
        S.sprite_(5, 50, 112, v.flg - 1 + v.flgf);
        v.s5 = 1;
    }
    if (v.bf != 0) weapons.bomb365();
    if (v.bnf != 0) bonus.crate();
    if (v.rkf != 0) weapons.rocket420();
    v.gtg = 1 - v.gtg;
    if ((k("W") or v.sk == 65) and v.wd == 0 and v.uc == 0 and (v.r == 0 or v.r == 8)) {
        v.wd2 = 1;
        v.wdx = 1;
        v.wd = 1;
    }
    if (v.gtg == 0) v.gtg2 = 1 - v.gtg2;
    if (v.cz == 61 and v.sp_f < 1 and v.r == 1 and v.ld == 1 and v.mes_s.len == 0) {
        v.mes_s.set("Press 'S' to Launch");
        scene.message1500();
    }
    if (v.cz != 61 and v.steam != 0) v.steam = @max(0, v.steam - 2);
    if (v.epcf != 0) pilot.enemyChute750();
    if (v.net != 0) net.net540();
    taxi92();
    if (v.gtg2 == 1) v.gtg4 = 1 - v.gtg4;
    if (v.tgtx != 0 or v.mission == 17) hud.arrow();
}

/// 120-127
pub fn part120() void {
    v.fps_f = 50.0 / B.fl(v.z2);
    if (S.jleft() != 0 and S.mouseKey() == 0 and v.fuel > 0 and v.th > 4) v.th -= 1;
    if (k("R")) {
        v.rqsx = v.sx;
        v.rqt = 200;
        v.mes_s.set("Repairing");
        scene.message1505();
    }
    if ((k("C") or v.sk == 67) and v.clus == 0 and v.b_a[10] > 0) {
        v.b_a[10] -= 1;
        v.clus = 1;
        hud.bonusString();
        hud.bonusBar();
        v.mes_s.set("Cluster Bomb Set");
        scene.message1500();
    }
    if ((k("B") or v.sk == 63) and v.turbo == 0 and v.b_a[9] > 0) {
        v.b_a[9] -= 1;
        v.turbo = 1;
        v.turbt = 20;
        v.smk = 106;
        v.smkt = 20;
        hud.bonusString();
        hud.bonusBar();
    }
    if (v.turbt != 0) {
        v.turbt -= 1;
        if (v.turbt == 0) v.turbo = 0;
    }
    if (v.mif_a[B.ix(31, v.mission)] >= v.mfin and v.ta != 28 and (v.r == 0 or v.r == 8) and v.uc == 0) {
        v.wd = 1;
        v.wdx = 1;
        v.wd2 = 1;
        v.ta = 28;
    }
}

/// 128-129: z2 = the VBLs this pass took; TIMER = 0 (zm is never set, so
/// its busy loop never runs); the stick right opens the throttle.
pub fn timer128() void {
    v.z2 = S.timer;
    v.t = S.timer;
    while (v.t < v.zm) v.t += 1;
    S.timer = 0;
    if (S.jright() != 0 and S.mouseKey() == 0 and v.fuel > 0 and v.th < 9) v.th += 1;
}

/// 131-147
pub fn part131() void {
    if (v.al == 0 and v.bale == 0 and scr.peek(v.sno9 + v.sx) > 0) @import("vehicles.zig").wrecks490();
    if (v.sea != 0 and v.al == 0) net.sea940();
    if (v.s5 == 0 and v.s5o != 0) S.sprite_(5, 999, 1, 38);
    if (v.s14 == 0 and v.s14o != 0) S.sprite_(14, 999, 1, 38);
    v.s14o = v.s14;
    v.s5o = v.s5;
}
