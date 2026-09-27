// --------------------------------------------------------------------------
// Lines 150-165: the keyboard (and F-key scancodes): 0-9 throttle, P pause
// (151, a flow of its own), U / F10 wheels, Esc bail out, Enter ripcord,
// Space land the parachute, F / F8 refuel stop, A autoland, M / F2 move the
// main base, E / F4 extinguisher, S steam catapult, T / F3 turn round; 165
// flak now and then where there is flak.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const text = @import("text.zig");
const B = @import("basic.zig");
const scene = @import("scene.zig");
const hud = @import("hud.zig");
const damage = @import("damage.zig");
const V = @import("vars.zig");
const v = &V.v;

fn k(s: []const u8) bool {
    return v.k_s.eql(s);
}

/// 150; true: P pressed (151's pause is the caller's flow).
pub fn keys150() bool {
    const kk = v.k_s.get();
    if (kk.len == 1 and kk[0] >= '0' and kk[0] <= '9' and v.fuel > 0) v.th = kk[0] - '0';
    return k("P");
}

/// 152-163 (after the pause, if any).
pub fn keys152() void {
    if ((k("U") or v.sk == 68) and (v.ld == 0 or v.sp_f > 4) and v.ufail == 0) v.uc = 1 - v.uc;
    if (k("\x1b") and v.crsh == 0 and v.ld == 0 and v.fre < 5 and v.bale == 0) {
        v.bale = 1;
        v.px = v.x;
        v.py = v.y;
        v.pal = v.al;
        v.psx = v.sx;
        v.pr = 59;
    }
    if (v.bale != 0 and v.rc == 0 and k("\r")) v.rc = 1;
    if (v.bale != 0 and v.pr == 63 and k(" ") and (v.pal > 0 or v.py < 158)) {
        v.pal = 0;
        v.py = 158;
        v.nf = 1;
    }
    if (v.bale == 0 and v.ld == 1 and v.sp_f == 0 and (k("F") or v.sk == 66)) v.cl = 1;
    autoland157();
    base158();
    keys160();
}

/// 157: A -- autoland at an airfield sector, for 500 x 4^lvl points.
fn autoland157() void {
    if (!(k("A") and v.bale == 0 and v.ld == 0 and B.mod(v.sx, 10) == 0 and v.bse_a[B.ix(42, B.mod(v.sx, 10))] == -1 and v.atlf == 1)) return;
    const cost = 500 * B.ipow(4, v.lvl);
    var buf: [48]u8 = undefined;
    var nb: [12]u8 = undefined;
    const s = text.str(&nb, cost);
    const pre = "Autolanding -";
    @memcpy(buf[0..pre.len], pre);
    @memcpy(buf[pre.len..][0..s.len], s);
    @memcpy(buf[pre.len + s.len ..][0..7], " Points");
    v.mes_s.set(buf[0 .. pre.len + s.len + 7]);
    scene.message1505();
    v.scre -= cost;
    hud.score();
    autoland1600();
}

/// 1600-1602: the plane put back over the runway, level, at 5.5.
fn autoland1600() void {
    v.st = 0;
    v.sp_f = @max(v.sp_f, 5.5);
    v.nf = 1;
    v.al = 0;
    v.r2 = 0;
    v.r = 0;
    v.x = 260;
    v.y = 144;
    v.th = 0;
    v.xo = v.x;
    v.yo = v.y;
    v.s2 = v.sx;
    v.s3 = v.al;
    if (v.ufail == 0) v.uc = 1;
}

/// 158: M / F2 -- this airfield becomes the main base.
fn base158() void {
    if ((k("M") or v.sk == 60) and v.ld == 1 and v.sp_f <= 0 and scr.peek(v.sc9 + v.sx) == 1 and v.bse_a[B.ix(42, B.div(v.sx, 10))] == -1) {
        v.main = v.sx;
        v.mes_s.set("Main Base Re-Located");
        scene.message1500();
    }
}

/// 160-162
fn keys160() void {
    if ((k("E") or v.sk == 62) and v.b_a[5] > 0 and v.fre > 0) {
        v.b_a[5] -= 1;
        v.fre = @max(0, v.fre - 1);
        hud.bonusString();
        hud.bonusBar();
        v.mes_s.set("Putting fire out!");
        scene.message1505();
    }
    if (k("S") and v.cz == 61 and v.r == 1 and v.ld == 1 and v.sp_f < 1) v.steam = 16;
    if ((k("T") or v.sk == 61) and v.ld == 1 and v.sp_f == 0 and (v.r == 1 or v.r == 7)) {
        v.r = 8 - v.r;
        v.r2 = v.r * 2;
    }
}

/// 165: flak where fl is set, likelier as the score (dl) rises.
pub fn flak165() void {
    const dice = S.rnd(10) + v.dl > 9;
    if (v.fl != 0 and v.flf == 0 and dice) damage.flak500();
}
