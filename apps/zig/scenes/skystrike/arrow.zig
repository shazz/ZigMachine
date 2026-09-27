// --------------------------------------------------------------------------
// Lines 740-744: the panel's arrow to the mission's target sector (98 right,
// 99 left -- the other way round past 20 sectors, the world wraps -- 119
// here, 28 home once the mission is done).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 740-744: the arrow to the target (98 right, 99 left, 119 here, 28 home).
pub fn arrow() void {
    v.ta = 119;
    if (v.tgtx > v.sx) {
        v.ta = 98;
        if (B.abs(v.sx - v.tgtx) > 20) v.ta = 99;
    }
    if (v.tgtx < v.sx) {
        v.ta = 99;
        if (B.abs(v.sx - v.tgtx) > 20) v.ta = 98;
    }
    if (v.mif_a[B.ix(31, v.mission)] >= v.mfin or v.lvl == 999) {
        v.ta = 28;
        if (v.tao != 28 and (v.r == 0 or v.r == 8) and v.uc == 0) {
            v.wd = 1;
            v.wdx = 1;
            v.wd2 = 1;
        }
    }
    if (v.ta != v.tao) {
        S.ink(13);
        S.bar(180, 177, 196, 182);
        v.xx = 180;
        v.yy = 177;
        v.ss = v.ta;
        O.stamp();
        v.tao = v.ta;
    }
}

