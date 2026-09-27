// --------------------------------------------------------------------------
// The panel: 590-593 the score (digit sprites 109-118 stamped into back),
// 700-737 the fuel gauge, the planes left, the kill tally, the bonus bar,
// 740-744 the target arrow.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const bonus = @import("bonus.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 590: the eight score digits, redrawn.
pub fn score() void {
    S.copy(.b6, 192, 24, 224, 32, .back, 32, 176);
    S.copy(.b6, 192, 24, 224, 32, .back, 64, 176);
    S.copy(.b6, 192, 16, 240, 24, .back, 0, 176);
    v.scre = @max(0, v.scre);
    var sbuf: [12]u8 = undefined;
    const s = text.str(&sbuf, v.scre);
    var all: [20]u8 = [_]u8{'0'} ** 20;
    @memcpy(all[8..][0..s.len], s);
    const digits = all[s.len..][0..8];
    v.q = 1;
    while (v.q <= 8) : (v.q += 1) {
        v.xx = 34 + v.q * 6;
        v.yy = 177;
        const c = digits[@intCast(v.q - 1)];
        v.ss = (if (c >= '0' and c <= '9') @as(i32, c - '0') else 0) + 109;
        O.stamp();
    }
    S.copy(.back, 0, 176, 96, 184, S.lg(), 0, 176);
}

/// 591-593: dl from the score; a pending bonus parachute count drops one.
pub fn level591() void {
    v.dl = @min(8, B.div(v.scre, 50000));
    if (v.bns > 0) {
        v.bns -= 1;
        bonus.award575();
    }
}

/// 700-705: the fuel gauge follows fux.
pub fn fuel() void {
    if (v.fux > v.fuxo) {
        panel710();
        v.fuxo = 99;
    }
    if (v.leak != 0 and v.lk2 == 0) {
        S.ink(1);
        S.bar(128, 194, v.fux + 128, 196);
        v.lk2 = 1;
        return;
    }
    if (v.leak != 0) return;
    S.ink(0);
    S.bar(v.fux + 129, 194, v.fuxo + 128, 196);
    if (v.fux < 5 and v.fuxo >= 5) {
        S.ink(1);
        S.bar(129, 194, v.fux + 128, 196);
    }
}

/// 710-712: gauge, FUEL, the bonus bar, the pilot card, the planes left.
pub fn panel710() void {
    S.ink(15);
    S.box(128, 193, 229, 197);
    S.ink(2);
    S.bar(129, 194, 228, 196);
    score();
    v.xx = 128;
    v.yy = 187;
    v.ss = 27;
    S.ink(13);
    S.bar(160, 188, 168, 192);
    v.fw = 0;
    O.stamp();
    bonusString();
    bonusBar();
    S.copy(.b6, 96, 97, 176, 124, S.lg(), 240, 176);
    S.copy(.b6, 96, 97, 176, 124, .back, 240, 176);
    v.a = 1;
    while (v.a <= @min(5, v.planes)) : (v.a += 1) {
        S.sprite_(15, 120 + 8 * v.a, 176, 31);
        S.update();
        S.putSprite(15);
    }
    v.ta = 99;
}

fn icon(s: i32) void {
    v.s = s;
    icon730();
}

/// 730: sprite 15 at the next kill place : put sprite 15
fn icon730() void {
    S.sprite_(15, v.p * 8 + 4, 188, v.s);
    v.p += 1;
    S.update();
    S.putSprite(15);
}

/// 720-726: the kills as icons: 100s (37), 50 (36), 20s (35), 10 (34),
/// 5s (33), ones (32).
pub fn kills720() void {
    v.p = 0;
    v.k2 = v.kls;
    S.ink(13);
    S.bar(4, 188, 117, 196);
    while (v.k2 >= 100) {
        v.k2 -= 100;
        icon(37);
        v.p += 1;
    }
    if (v.k2 >= 50) {
        v.k2 -= 50;
        icon(36);
    }
    while (v.k2 >= 20) : (v.k2 -= 20) icon(35);
    if (v.k2 >= 10) {
        v.k2 -= 10;
        icon(34);
    }
    while (v.k2 >= 5) : (v.k2 -= 5) icon(33);
    while (v.k2 > 0) : (v.k2 -= 1) icon(32);
}

/// 734-736: the bonus bar across the top: frame, checkered, the icons.
pub fn bonusBar() void {
    S.ink(13);
    S.box(14, 2, 306, 12);
    gfx.writing = 2;
    gfx.paint_style = 2;
    gfx.paint_index = 4;
    S.bar(16, 4, 304, 10);
    gfx.writing = 1;
    gfx.paint_style = 1;
    gfx.paint_index = 1;
    const b = v.bon_s.get();
    if (b.len == 0) return;
    v.a = 1;
    v.l = 160 - @as(i32, @intCast(b.len)) * 8;
    v.p = 0;
    while (true) {
        S.sprite_(15, v.l + v.p * 16 + 8, 4, @as(i32, b[@intCast(v.a - 1)]) + 39);
        S.update();
        S.putSprite(15);
        v.a += 1;
        v.p += 1;
        if (v.a > b.len) return;
    }
}

/// 737: bon$ = one character per bonus held, at most 18.
pub fn bonusString() void {
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    const parts = [_]struct { c: u8, k: i32 }{
        .{ .c = 1, .k = B.div(v.b_a[7], 5000) }, .{ .c = 2, .k = v.b_a[1] },
        .{ .c = 3, .k = B.div(v.b_a[2], 50) },   .{ .c = 4, .k = @max(0, v.b_a[6]) },
        .{ .c = 5, .k = @max(0, v.b_a[5]) },     .{ .c = 61, .k = v.b_a[8] },
        .{ .c = 66, .k = v.b_a[10] },            .{ .c = 69, .k = v.b_a[9] },
    };
    for (parts) |pt| {
        var k: i32 = 0;
        while (k < pt.k and n < buf.len) : (k += 1) {
            buf[n] = pt.c;
            n += 1;
        }
    }
    v.bon_s.set(buf[0..@min(n, 18)]);
}

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

