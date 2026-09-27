// --------------------------------------------------------------------------
// Lines 1670-1685 of a mission's briefing (mission.zig runs it): the record's
// eight 36-character lines centred, the mission / start / end bonuses, and
// the goal counter set from what the world already says.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const text = @import("text.zig");
const B = @import("basic.zig");
const boot = @import("boot.zig");
const V = @import("vars.zig");
const v = &V.v;

/// prefix + STR$(n) + suffix
pub fn join(buf: []u8, pre: []const u8, n: i32, post: []const u8) []const u8 {
    var nb: [12]u8 = undefined;
    const s = text.str(&nb, n);
    @memcpy(buf[0..pre.len], pre);
    @memcpy(buf[pre.len..][0..s.len], s);
    @memcpy(buf[pre.len + s.len ..][0..post.len], post);
    return buf[0 .. pre.len + s.len + post.len];
}

/// 1670-1674: the text's lines (36 characters each), the bonuses.
pub fn brief1670(md: []const u8) void {
    S.fadeTo(5, .b5);
    v.a = 0;
    while (v.a < 8) : (v.a += 1) {
        const l = md[@intCast(v.a * 36)..][0..36];
        if (!allSpaces(l)) {
            S.locate(0, v.a + 6);
            S.centre(l);
        }
    }
    v.tao = 999;
    S.locate(1, 3);
    var buf: [40]u8 = undefined;
    S.centre(join(&buf, "Mission Bonus ", v.bonus * 1000, ""));
    if (v.msb != 0) {
        S.locate(3, 4);
        S.print("Start Bonus");
        v.yy = text.ygraphic(4);
        S.sprite_(14, 180, v.yy, v.bns_a[B.ix(16, v.msb - 1)]);
    }
    if (v.meb != 0) {
        S.locate(3, 5);
        S.print("End Bonus");
        v.yy = text.ygraphic(5);
        S.sprite_(15, 180, v.yy, v.bns_a[B.ix(16, v.meb - 1)]);
    }
}

fn allSpaces(l: []const u8) bool {
    for (l) |c| if (c != ' ') return false;
    return true;
}

/// 1675-1685: the goal's counter, and what the world already says.
pub fn goals1675() void {
    const m = B.ix(31, v.mission);
    v.mif_a[m] = v.misf;
    v.md_s.len = 0;
    const base = v.bse_a[B.ix(42, B.div(v.tgtx, 10))];
    if (v.mission == 6 and base < 1) v.mif_a[6] = 1;
    if (v.mission == 7 and base == -1) v.mif_a[7] = 1;
    if (v.mission == 4 and v.btlsnk != 0) v.mif_a[4] = 1;
    if (v.mission == 11) {
        v.trksx = v.tgtx;
        v.trkf = 1;
        for (0..4) |a| {
            boot.truck(a);
            v.vsx_a[a] = v.tgtx;
            v.vx_a[a] = 40 + 80 * @as(i32, @intCast(a));
        }
        v.a = 4;
        v.mif_a[11] = 0;
    }
}
