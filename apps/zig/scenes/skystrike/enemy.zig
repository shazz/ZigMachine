// --------------------------------------------------------------------------
// The two enemy fighters (sprites 3 and 4): 250-260 their flight, 280-289
// ground hits, fire and bailing out; the steering of one of them a pass
// (a = gtg4) is enemy_ai.zig (261-279).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const blast = @import("blast.zig");
const sfx = @import("sfx.zig");
const life = @import("enemy_life.zig");
const ai = @import("enemy_ai.zig");
const V = @import("vars.zig");
const v = &V.v;

fn ea() usize {
    return B.ix(2, v.a);
}

/// 250-260, then 261-279 (the steering; far away it returns at once,
/// skipping 280-289 too).
pub fn fly250() void {
    v.a = 0;
    while (true) {
        const a = ea();
        if (v.esx_a[a] == v.sx and v.eal_a[a] == v.al) {
            blast.smoke198();
            S.sprite_(3 + v.a, v.ex_a[a], v.ey_a[a], v.er_a[a] + v.ea_a[a]);
        } else S.sprite_(3 + v.a, 999, 0, 38);
        speed252(a);
        move255(a);
        v.a += 1;
        if (v.a >= 2) break;
    }
    v.a = v.gtg4;
    v.swp = 0;
    if (ai.steer261()) hurt280();
}

/// 252-254: speed from throttle, attitude and height; stalls below 2.
fn speed252(a: usize) void {
    const er = B.ix(16, v.er_a[a]);
    // eth(a) / 3.0 and dy / 4.0 are float divisions, eal(a) / 2 an integer one
    const f = B.fl(v.esp_a[a]) + B.fl(v.eth_a[a]) / 3.0 + B.fl(v.dy_a[er][0]) / 4.0 - B.fl(B.div(v.eal_a[a], 2)) - B.F0_1;
    v.esp_a[a] = B.ftoi(f);
    v.esp_a[a] = @min(10, v.esp_a[a]);
    if (v.esp_a[a] < 2 and (v.eal_a[a] > 0 or v.ey_a[a] < 154)) v.st_a[a] = 16;
    v.st_a[a] += B.t(v.st_a[a] > 0);
    v.eth_a[a] = if (v.esp_a[a] < 11) 10 else 4;
}

/// 255-259: move; wrap across sectors (0..400) and layers; below the
/// ground layer the plane has crashed (316).
fn move255(a: usize) void {
    const er = B.ix(16, v.er_a[a]);
    v.exo_a[a] = v.ex_a[a];
    v.eyo_a[a] = v.ey_a[a];
    v.ex_a[a] = B.ftoi(B.fl(v.ex_a[a]) + B.fl(v.dx_a[er] * v.esp_a[a]) / 6.0);
    v.ey_a[a] = B.ftoi(B.fl(v.ey_a[a]) + B.fl(v.dy_a[er][0] * v.esp_a[a]) / 6.0 + B.fl(v.fre_a[a] + v.st_a[a]));
    if (v.ex_a[a] < 0) {
        v.ex_a[a] += 320;
        v.esx_a[a] -= 1;
        if (v.esx_a[a] < 0) v.esx_a[a] = 400;
    }
    if (v.ex_a[a] > 319) {
        v.ex_a[a] -= 320;
        v.esx_a[a] += 1;
        if (v.esx_a[a] > 400) v.esx_a[a] = 0;
    }
    if (v.ey_a[a] < 0) {
        v.ey_a[a] = 160;
        v.eal_a[a] += 1;
    }
    if (v.ey_a[a] > 160) {
        v.eal_a[a] -= 1;
        v.ey_a[a] = 0;
        if (v.eal_a[a] < 0) life.crashed316();
    }
}

/// 280-289: for both: ground zones set them on fire; burning planes veer
/// down; a pilot may bail out.
fn hurt280() void {
    v.a = 0;
    while (true) {
        const a = ea();
        if (v.esx_a[a] == v.sx and v.eal_a[a] == v.al) {
            v.c = S.zone(3 + v.a);
            if (v.c > 2) {
                v.fre_a[a] += S.rnd(3) + 1;
                sfx.crash();
                v.nso = 2;
            }
        }
        veer281(a);
        if (v.swp == 1) {
            v.x = v.xt;
            v.y = v.yt;
            v.sx = v.sxt;
            v.al = v.alt;
        }
        bail283(a);
        v.a += 1;
        if (v.a == 2) break;
    }
}

fn veer281(a: usize) void {
    if (v.fre_a[a] <= 3) return;
    if (v.er_a[a] > 4 and v.er_a[a] < 12) {
        v.er_a[a] += 1;
    } else {
        v.er_a[a] -= 1;
        if (v.er_a[a] < 0) v.er_a[a] = 15;
    }
}

fn bail283(a: usize) void {
    const dice = S.rnd(100) > 90; // every AND term is evaluated
    if (v.fre_a[a] > 2 and v.fre_a[a] < 5 and v.eal_a[a] * 160 + 160 - v.ey_a[a] > 90 and v.epcf == 0 and
        v.ebale_a[a] == 0 and dice)
    {
        v.epcf = 1;
        v.epsx = v.esx_a[a];
        v.epal = v.eal_a[a];
        v.epy = v.ey_a[a];
        v.epx = v.ex_a[a];
        v.epv = 0;
        v.ebale_a[a] = 1;
        v.brdf = 0;
    }
    if (v.fre_a[a] > 4) v.ebale_a[a] = 1;
}
