// --------------------------------------------------------------------------
// Bailing out (Esc): 153 the pilot leaves the plane (images 59-62 falling,
// 63 the open parachute), 154 Enter pulls the ripcord, 155 Space lands him
// at once; 210-215 the fall, down through the layers to the ground (220);
// 750-755 an enemy pilot's parachute.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const scene = @import("scene.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 210-215; true: 211's "goto 220" (he reached the ground layer's floor).
pub fn drift210() bool {
    v.nf = 0;
    v.py = v.py + 8 - v.pr + 59;
    if (v.pr == 63) v.py -= 2;
    if (v.py > 160) {
        v.py = 0;
        v.s2 = v.sx;
        v.s3 = v.al;
        v.sx = v.psx;
        v.pal -= 1;
        v.al = v.pal;
        if (v.pal < 0) return true;
        scene.draw();
        v.sx = v.s2;
        v.al = v.s3;
    }
    const dice = S.rnd(15) > 11;
    if (v.rc == 1 and dice) v.pr = @min(63, v.pr + 1);
    return false;
}

/// 750-755: the enemy pilot's parachute (sprite 14, images 59-63).
pub fn enemyChute750() void {
    v.shrk = 0;
    v.brdf = 0;
    v.epv = @min(4, v.epv + B.div(S.rnd(6), 5));
    if (v.epsx == v.sx and v.epal == v.al and v.s14 == 0) {
        S.sprite_(14, v.epx, v.epy, 59 + v.epv);
        v.s14 = 1;
    }
    v.epy = v.epy + 8 - v.epv;
    if (v.epv == 4) v.epy -= 2;
    if (v.epy > 160) {
        v.epal -= 1;
        v.epy = 0;
        if (v.epal < 0) {
            v.epcf = 0;
            if (v.al == 0 and v.epsx == v.sx and v.epv < 4) {
                v.ss = 58;
                v.yy = 160;
                v.xx = v.epx;
                O.stamp();
            }
        }
    }
}
