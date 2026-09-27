// --------------------------------------------------------------------------
// Lines 570-596: the bonus crate drifting down under its parachute (sprites
// 8 and 9) and what catching it gives: bns is the crate's kind, bm$(bns)
// its name, bns(bns) its image.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const hud = @import("hud.zig");
const scene = @import("scene.zig");
const V = @import("vars.zig");
const v = &V.v;

fn park() void {
    S.sprite_(8, 999, 1, 38);
    S.sprite_(9, 999, 1, 38);
}

/// 570-574
pub fn crate() void {
    if (v.sx == v.bosx and v.al == v.boal) {
        S.sprite_(8, v.bnx, v.bny, 74);
        S.sprite_(9, v.bnx, v.bny + 10, v.bns_a[B.ix(16, v.bns)]);
    }
    v.bny += 2;
    if (v.bny > 160) {
        v.bnf = 0;
        park();
    }
    v.c2 = S.collide(9, 32, 32);
    v.cc = B.t(v.c2 >> 1 & 1 != 0);
    if (v.cc != 0) {
        award575();
        v.bnf = 0;
        park();
    }
}

/// 575: the name on line 5, the gift, the bonus bar redrawn (goto 734).
pub fn award575() void {
    v.mes_s.set(v.bm_s_a[B.ix(16, v.bns)].get());
    scene.message1500();
    gift(v.bns);
    hud.bonusString();
    hud.bonusBar();
}

fn points(n: i32) void {
    v.scre += n;
    hud.score();
}

/// ON bns + 1 GOSUB 576,577,578,579,586,580,581,582,583,584,585,587,588,589,595,596
fn gift(k: i32) void {
    const b = &v.b_a;
    switch (k) {
        0 => b[3] = 4,
        1 => b[4] = 8,
        2 => {
            b[7] += 5000;
            v.fuel = @min(20000, v.fuel + 5000);
            b[7] = @min(15000, b[7]);
        },
        3 => {
            b[0] = @min(20, b[0] + 10);
            b[1] = @min(2, b[1] + 1);
        },
        4 => {
            b[2] += 50;
            v.ammo += 50;
            b[2] = @min(150, b[2]);
        },
        5 => b[6] = @min(3, b[6] + 1),
        6 => b[5] += 1,
        7 => points(5000),
        8 => points(10000),
        9 => points(20000),
        10 => points(50000),
        11 => v.planes += 1,
        12 => b[8] += 1,
        13 => b[9] = @min(b[9] + 1, 4),
        14 => b[10] = @min(3, b[10] + 1),
        15 => {
            v.fre = 0;
            v.leak = 0;
            v.ufail = 0;
        },
        else => {},
    }
}
