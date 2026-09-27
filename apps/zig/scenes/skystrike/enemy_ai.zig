// --------------------------------------------------------------------------
// Lines 261-279: one enemy's steering a pass (a = gtg4). It wants the
// direction (dx, dy) toward the player -- or up, away from high ground --
// turns its heading er (0-15, di() the heading of each (dx, dy)) one step
// toward it when the dice allow, wanders, shoots when lined up, and is kept
// within a few sectors of the player.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const blast = @import("blast.zig");
const life = @import("enemy_life.zig");
const hud = @import("hud.zig");
const V = @import("vars.zig");
const v = &V.v;

fn ea() usize {
    return B.ix(2, v.a);
}

/// false: 261's early RETURN (the plane is too far to matter this pass).
pub fn steer261() bool {
    const a = ea();
    if (v.gtg2 == 0 and (B.abs(v.eal_a[a] - v.al) > 1 or B.abs(v.esx_a[a] - v.sx) > 1)) return false;
    wish262(a);
    burning272(a);
    turn273(a);
    shoot278(a);
    const e = v.esx_a[a];
    if ((e > v.sx + 5 and e < v.sx + 45) or (e < v.sx - 5 and e > v.sx - 45))
        v.esx_a[a] = B.mod(@max(45, @min(55, e + 50 - v.sx)), 51) + v.sx;
    return true;
}

/// 262-270: dx toward the player's sector / x; dy up over high ground or
/// when low and fast, else toward the player's layer / y.
fn wish262(a: usize) void {
    v.dx = 0;
    v.dy = 0;
    const e = v.esx_a[a];
    if (e < v.sx or (e > 300 and v.sx < 100)) {
        v.dx = 1;
    } else if (e > v.sx or (e < 10 and v.sx > 40)) {
        v.dx = -1;
    } else if (e == v.sx and v.ex_a[a] > v.x) {
        v.dx = -1;
    } else if (e == v.sx and v.ex_a[a] < v.x) v.dx = 1;
    const t = scr.peek(v.sc9 + e);
    if (v.eal_a[a] < 1 and ((t > 9 and t < 20) or (v.ey_a[a] > 20 and v.esp_a[a] > 4))) {
        v.dy = -1;
        v.dx = 0;
        v.pri = 1;
        return;
    }
    v.pri = 0;
    const eal = v.eal_a[a];
    if (eal < v.al or (eal < 0 and v.ey_a[a] > 50 and v.esp_a[a] > 4) or (eal == v.al and v.ey_a[a] > v.y and v.esp_a[a] > 4)) {
        v.dy = -1;
        v.eth_a[a] = 10;
        return;
    }
    if (eal > v.al or (eal == v.al and v.ey_a[a] < v.y)) v.dy = 1;
}

/// 272: on fire it dives; badly on fire it explodes (500 points).
fn burning272(a: usize) void {
    if (v.fre_a[a] <= 2) return;
    v.dy = 1;
    v.dx = S.rnd(2) - 1;
    if (v.fre_a[a] <= 4) return;
    v.ex = v.ex_a[a];
    v.st_a[a] = 10;
    v.ey = v.ey_a[a];
    v.esx = v.esx_a[a];
    v.ew = 0;
    v.esy = v.eal_a[a];
    v.exf = 0;
    v.fre_a[a] = 4;
    blast.scatter405();
    v.esp_a[a] = 0;
    v.scre += 500;
    hud.score();
}

/// 273-277: turn toward the wish (the better the pilot, the likelier),
/// then maybe wander a step (only above the ground layer).
fn turn273(a: usize) void {
    if (S.rnd(18) + v.fre_a[a] < 10 + v.dl or v.pri == 1 or v.ebale_a[a] != 0) {
        v.d = (v.dy + 1) * 3 + v.dx + 1;
        v.d = v.di_a[B.ix(9, v.d)];
        v.rd = v.er_a[a] - v.d;
        if ((v.rd < 0 and v.rd > -8) or v.rd >= 8) {
            v.er_a[a] = B.mod(v.er_a[a] + 1, 16);
            v.eth_a[a] = 4;
        }
        if ((v.rd > 0 and v.rd < 8) or v.rd <= -8) {
            v.er_a[a] = B.mod(v.er_a[a] - 1 + 16, 16);
            v.eth_a[a] = 4;
        }
    }
    if (S.rnd(10) + v.dl > 6 and v.eal_a[a] > 0) {
        v.er_a[a] = B.mod(v.er_a[a] + 1, 16);
        return;
    }
    if (S.rnd(10) + v.dl > 6 and v.eal_a[a] > 0) v.er_a[a] = B.mod(v.er_a[a] - 1 + 16, 16);
}

/// 278: lined up on the player on screen: fire (320). The compiled code
/// evaluates every term of an AND chain, so the RND is always drawn.
fn shoot278(a: usize) void {
    const er = B.ix(16, v.er_a[a]);
    const here = v.esx_a[a] == v.sx and v.eal_a[a] == v.al;
    const lx = B.sgn(B.div(v.x, 16) - B.div(v.ex_a[a], 16)) == B.sgn(v.dx_a[er]);
    const ly = B.sgn(B.div(v.y, 16) - B.div(v.ey_a[a], 16)) == B.sgn(v.dy_a[er][0]);
    const dice = S.rnd(20 + v.dl * 2) > 17;
    if (here and lx and ly and v.fre_a[a] < 3 and dice) life.shoot320();
}
