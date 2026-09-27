// --------------------------------------------------------------------------
// Lines 540-544: the carrier's arrester net (sprite 14, images 101-104, the
// higher the closer the plane comes); touching it is a bad landing. 940-942
// the sea's shimmer: two of its lines swapped at random each pass.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const blocks = @import("blocks.zig");
const B = @import("basic.zig");
const scene = @import("scene.zig");
const hud = @import("hud.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 540-544
pub fn net540() void {
    if (v.y < 50 or v.x < 16 or v.arr != 0) {
        v.nv = 0;
    } else {
        v.nv = B.div(320 - v.x, 60);
        if (v.x < 80) v.nv = 3;
    }
    v.nv = @max(0, @min(3, v.nv));
    S.sprite_(14, 48, 128 + v.carsnk, 101 + v.nv);
    v.s14 = 1;
    if (v.nv == 0) return;
    v.c2 = S.collide(14, 16, 8 + v.nv * 2);
    v.c = B.t(v.c2 >> 1 & 1 != 0);
    if (v.c == 0) return;
    v.scre -= 500;
    v.sp_f = v.sp_f - 3 + B.fl(B.div(128 - v.y, 8));
    v.mes_s.set("BAD LANDING !");
    v.arr = -1;
    scene.message1505();
    hud.score();
    v.y = v.gry;
}

/// 940-942: s$ = screen$(logic,0,a1+163 to 320,a1+164) and so on.
pub fn sea940() void {
    v.a1 = S.rnd(12);
    v.a2 = S.rnd(12);
    blocks.get(&blocks.aux, S.lg(), 0, v.a1 + 163, 320, v.a1 + 164);
    S.move(S.lg(), 0, v.a1 + 163, S.lg(), 0, v.a2 + 163, 320, v.a2 + 164);
    blocks.put(&blocks.aux, S.lg(), 0, v.a2 + 163);
}
