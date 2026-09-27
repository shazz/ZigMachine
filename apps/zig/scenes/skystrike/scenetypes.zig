// --------------------------------------------------------------------------
// The screen types (peek(sc9 + sx)), lines 1004 / 1950's ON ... GOSUB:
//   0, 4-7   1050 grass, hills, clouds           1   1060 an airfield
//   2, 3     1090 / 1100 the battleship           8   1300 the bridge
//   9        1150 the sea                         10, 11  1160 / 1170 the coast
//   12, 13   1180 / 1190 the carrier              14-17   1200-1230 towers, hills
//   20-35    1070 the bank-8 object screens (s = type - 20)
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const scene = @import("scene.zig");
const sea = @import("seatypes.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 1004's ON peek(sc9 + sx) + 1 GOSUB (types past 17: none).
pub fn onType(t: i32) void {
    switch (t) {
        0, 4, 5, 6, 7 => t1050(),
        1 => t1060(),
        2 => sea.t1090(),
        3 => sea.t1100(),
        8 => t1300(),
        9 => sea.t1150(),
        10 => t1160(),
        11 => t1170(),
        12 => sea.t1180(),
        13 => sea.t1190(),
        14 => sea.t1200(),
        15 => sea.t1210(),
        16 => sea.t1220(),
        17 => sea.t1230(),
        else => {},
    }
}

/// 1950's list: 1959 (the bonus bar only) where 1004 has 1050 / 1150-1170.
pub fn onTypeRedraw(t: i32) void {
    switch (t) {
        0, 4, 5, 6, 7, 9, 10, 11 => @import("hud.zig").bonusBar(),
        else => onType(t),
    }
}

/// 1050: grass, zones 1 (the ground) and 2 (just above); on a fresh
/// screen (nf) the clouds and the hills.
pub fn t1050() void {
    scene.grass();
    S.setZone(1, 0, 162, 319, 176);
    S.setZone(2, 0, 156, 319, 168);
    if (v.nf == 0) return;
    clouds1052();
}

/// 1052-1059: the cloud bands three times across, then (on the ground
/// layer, with the memory to spare) the hills.
pub fn clouds1052() void {
    bands();
    if (v.al > 0) return;
    hills1058();
}

fn bands() void {
    v.a = 0;
    while (true) {
        const x = v.a * 100 + 10;
        S.move(S.lg(), x, 8, .b6, 192, 64, 320, 99);
        S.move(S.lg(), x, 45, .b6, 192, 100, 320, 120);
        S.move(S.lg(), x, 73, .b6, 192, 121, 320, 137);
        S.move(S.lg(), x, 100, .b6, 192, 138, 320, 153);
        S.move(S.lg(), x, 125, .b6, 192, 154, 320, 164);
        v.a += 1;
        if (v.a == 3) return;
    }
}

/// 1058-1059: 20 columns of hills, from the sector's own place in the strip.
fn hills1058() void {
    v.z = B.mod(v.sx, 10);
    v.yy = B.div(v.z, 5);
    v.xx = B.mod(v.z, 5);
    v.z = 0;
    while (true) {
        S.move(S.lg(), v.z * 16, 136 - v.yy * 19, .b6, v.xx * 16, 129 + v.yy * 27, v.xx * 16 + 16, 153 + v.yy * 46);
        v.xx += 1;
        if (v.xx > 10) {
            v.xx = 0;
            v.yy = 1 - v.yy;
        }
        v.z += 1;
        if (v.z == 20) return;
    }
}

/// 1060-1065: an airfield: the officers' mess (burnt from 3 guns down),
/// the flag of whoever holds it, HQ at the main base.
fn t1060() void {
    t1050();
    scene.toBack();
    const burnt = v.bc >= 3;
    const x0: i32 = if (burnt) 96 else 0;
    S.move(S.lg(), 144, 140, .b6, x0, 76, x0 + 96, 96);
    S.move(.back, 144, 140, .b6, x0, 76, x0 + 96, 96);
    v.b = v.bse_a[B.ix(42, B.div(v.sx, 10))];
    if (v.b == 1 or v.b == -1) {
        S.ink(12);
        S.bar(50, 128, 51, 160);
        v.flg = if (v.b == 1) 70 else 68;
        const y0: i32 = if (v.b == 1) 104 else 96;
        S.move(S.lg(), 144, 133, .b6, 0, y0, 96, y0 + if (v.b == 1) @as(i32, 10) else 9);
        v.flgf = 1;
    }
    if (v.b == -1 and v.sx == v.main and v.tsc == 0) {
        v.xx = 52;
        v.yy = 144;
        v.ss = 72;
        O.stamp();
    }
}

/// 1070-1074: a bank-8 screen (34: the coast first), its guns counted.
pub fn t1070() void {
    if (scr.peek(v.sc9 + v.sx) != 34) t1050() else sea.t1210();
    v.s = scr.peek(v.sc9 + v.sx) - 20;
    v.lx = 0;
    v.scrb = v.scrb_a[B.ix(16, v.s)];
    O.objects();
    v.fl = 0;
    if (v.gh < v.fl_a[B.ix(16, v.s)]) v.fl = 1;
    v.s += 20;
    if (v.s == 26 and v.fl == 0) {
        v.dbl = 0;
        v.mif_a[15] = 1;
    }
    const m = v.mission;
    if (v.fl == 0 and v.sx == v.tgtx and m > 2 and m != 16 and m != 19 and m != 20 and m != 1 and m != 11)
        v.mif_a[B.ix(31, m)] = v.mfin;
}

/// 1160-1164: the coast, sea to the right.
pub fn t1160() void {
    S.move(S.lg(), 0, 160, .b6, 0, 33, 320, 48);
    S.setZone(1, 0, 168, 319, 176);
    S.setZone(2, 0, 156, 319, 168);
    v.grlx = 0;
    v.grhx = 160;
    S.move(S.lg(), 48, 148, .b6, 0, 116, 96, 132);
    if (v.nght == 0) sea.clouds1152();
}

/// 1170-1174: the coast, sea to the left.
pub fn t1170() void {
    S.move(S.lg(), 0, 160, .b6, 0, 48, 320, 64);
    S.setZone(1, 0, 168, 319, 176);
    S.setZone(2, 0, 156, 319, 168);
    v.grlx = 160;
    v.grhx = 319;
    S.move(S.lg(), 208, 144, .b5, 160, 144, 224, 160);
    if (v.nght == 0) sea.clouds1152();
}

/// 1300-1302: the bridge. Its arch is the mouse pointer (CHANGE MOUSE 82:
/// sprite image 79), fixed at 144,129 and shown over every sprite.
fn t1300() void {
    t1050();
    v.s = 11;
    v.lx = 0;
    O.objects();
    S.move(S.lg(), 48, 129, .b5, 96, 112, 160, 144);
    S.move(S.lg(), 112, 160, .b5, 64, 144, 160, 160);
    S.move(S.lg(), 112, 129, .b5, 256, 16, 288, 48);
    v.brdg = 1;
    v.go += 1;
    S.setZone(v.go + 2, 112, 128, 190, 140);
    scene.toBack();
    sprite.mouse(true, 82 - 3, 144, 129);
}
