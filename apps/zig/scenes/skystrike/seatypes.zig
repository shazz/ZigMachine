// --------------------------------------------------------------------------
// The sea screens: 1090 / 1100 the battleship Grafmark (bow, stern),
// 1180 / 1190 the aircraft carrier, 1150-1153 the sea and its clouds,
// 1200-1234 the tower and hill screens, 1560-1568 a ship settling a line.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const types = @import("scenetypes.zig");
const hud = @import("hud.zig");
const V = @import("vars.zig");
const v = &V.v;

fn tz(s: []const u8, lx: i32, ly: i32) void {
    O.setM(s, lx, ly);
    O.tilesZone();
}

fn t(s: []const u8, lx: i32, ly: i32) void {
    O.setM(s, lx, ly);
    O.tiles();
}

/// 1092 / 1108 / 1183 / 1195: 3 guns down sinks the ship.
fn sunk(snk: *i32, pts: i32, mission4: bool) void {
    if (v.bc >= 3 and snk.* == 0) {
        snk.* = 1;
        if (mission4) {
            v.fl = 0;
            v.mif_a[4] = 1;
        }
        v.scre += pts;
        hud.score();
    }
}

/// 1090-1099: the battleship's bow.
pub fn t1090() void {
    const k = v.btlsnk;
    v.gry = 124 + k;
    v.grlx = 80;
    v.grhx = 320;
    if (k == 0) v.fl = 1;
    if (scr.peek(v.ghx9 + v.sx) > 0) @import("groundguns.zig").offGround1580();
    sunk(&v.btlsnk, 10000, true);
    tz("2425", 13, 112 + k);
    tz("808182", 9, 116 + k);
    tz("808182", 12, 108 + k);
    tz("6163636363", 15, 112 + k);
    tz("000102200202200202200202200202", 5, 128 + k);
    tz("22232323232323232323232323", 7, 144 + k);
    tz("4142430506", 15, 96 + k);
    tz("21", 16, 80 + k);
    t1150();
}

/// 1100-1109: the battleship's stern.
pub fn t1100() void {
    const k = v.btlsnk;
    v.grlx = 0;
    v.gry = 124 + k;
    v.grhx = 256;
    if (k == 0) v.fl = 1;
    if (scr.peek(v.ghx9 + v.sx) > 0) @import("groundguns.zig").offGround1580();
    tz("20020220020220020220020220020240", 0, 128 + k);
    tz("23232323232323232323232323232360", 0, 144 + k);
    tz("434204242504", 0, 96 + k);
    tz("63622062636363", 0, 112 + k);
    tz("21", 1, 80 + k);
    tz("2425", 7, 112 + k);
    S.move(S.lg(), 112, 112 + k, .b5, 0, 182, 48, 192);
    S.move(S.lg(), 160, 118 + k, .b5, 0, 182, 48, 192);
    sunk(&v.btlsnk, 10000, true);
    t1150();
}

/// 1150-1151: five sea blocks, zones 1 and 2 for the water.
pub fn t1150() void {
    v.sea = 1;
    v.a = 0;
    while (true) {
        S.move(S.lg(), v.a * 64, 160, .b6, 0, 16, 64, 32);
        v.a += 1;
        if (v.a == 5) break;
    }
    S.setZone(1, 0, 168, 319, 176);
    S.setZone(2, 0, 156, 319, 168);
    clouds1152();
}

/// 1152-1153: two cloud bands over the sea.
pub fn clouds1152() void {
    v.a = 0;
    while (true) {
        S.move(S.lg(), v.a * 100 + 10, 8, .b6, 192, 65, 320, 103);
        S.move(S.lg(), v.a * 100 + 10, 45, .b6, 192, 103, 320, 130);
        v.a += 1;
        if (v.a == 3) return;
    }
}

/// 1180-1189: the carrier's bow (its deck zone 61 catches the plane).
pub fn t1180() void {
    const k = v.carsnk;
    v.gry = 124 + k;
    v.grlx = 80;
    v.grhx = 320;
    S.setZone(60, 90, 126 + k, 319, 168);
    if (scr.peek(v.ghx9 + v.sx) > 0) @import("groundguns.zig").offGround1580();
    S.setZone(61, 80, 120 + k, 170, 130 + k);
    sunk(&v.carsnk, -10000, false);
    t("000102030202030202030202030202", 5, 128 + k);
    t("22232323232323232323232323", 7, 144 + k);
    v.s = 21;
    v.xx = 256;
    v.yy = 80 + k;
    O.tile();
    t("414243", 15, 96 + k);
    t("616263", 15, 112 + k);
    t1150();
}

/// 1190-1199: the carrier's stern (zone 62: the arrester net).
pub fn t1190() void {
    const k = v.carsnk;
    v.grlx = 0;
    v.gry = 124 + k;
    v.grhx = 256;
    S.setZone(60, 0, 126 + k, 240, 168);
    if (scr.peek(v.ghx9 + v.sx) > 0) @import("groundguns.zig").offGround1580();
    t("03020203020203020203020203020240", 0, 128 + k);
    t("23232323232323232323232323232360", 0, 144 + k);
    S.setZone(62, 50, 120 + k, 230, 128 + k);
    sunk(&v.carsnk, -10000, false);
    v.net = 1;
    t1150();
}

/// 1200-1205
pub fn t1200() void {
    types.t1160();
    S.move(S.lg(), 112, 64, .b5, 256, 144, 288, 192);
    S.move(S.lg(), 128, 112, .b5, 256, 144, 288, 176);
    S.move(S.lg(), 128, 144, .b5, 224, 144, 256, 160);
    v.a = 0;
    while (v.a < 2) : (v.a += 1) {
        v.b = 0;
        while (v.b < 4 - v.a) : (v.b += 1) S.move(S.lg(), v.b * 32, 128 - v.a * 32, .b5, 288, 64, 320, 96);
    }
    v.b = 0;
    v.t = 0;
    while (v.b < 3) : (v.b += 1) {
        S.move(S.lg(), v.b * 32, 64, .b5, 256 + v.t * 32, 48 - v.t * 16, 288 + v.t * 32, 80 - v.t * 16);
        v.t = 1 - v.t;
    }
    v.a = 0;
    while (v.a < 3) : (v.a += 1) {
        v.go += 1;
        S.setZone(v.go + 2, 0, v.a * 32 + 64, 128, v.a * 32 + 96);
    }
    v.go += 1;
    S.setZone(v.go + 2, 128, 112, 144, 160);
    S.move(S.lg(), 96, 64, .b5, 304, 32, 320, 80);
    S.copy(.b5, 288, 48, 320, 64, S.lg(), 96, 112);
}

/// 1210-1219
pub fn t1210() void {
    types.t1170();
    S.move(S.lg(), 224, 64, .b5, 256, 80, 288, 144);
    S.move(S.lg(), 224, 128, .b5, 256, 112, 288, 144);
    v.a = 0;
    while (v.a < 2) : (v.a += 1) {
        v.b = 0;
        while (v.b < 2) : (v.b += 1) S.copy(.b5, 288, 64, 320, 96, S.lg(), 256 + v.b * 32, 128 - v.a * 32);
    }
    v.a = 0;
    v.t = 0;
    while (v.a < 2) : (v.a += 1) S.move(S.lg(), 256 + v.a * 32, 64, .b5, 256 + v.t * 32, 48 - v.t * 16, 288 + v.t * 32, 80 - v.t * 16);
    v.go += 1;
    S.setZone(v.go + 2, 230, 68, 319, 160);
}

/// 1560-1563 / 1565-1568: the carrier (types 12, 13) or the battleship
/// (2, 3) settles one line; `snk` counts the lines.
pub fn settle(snk: *i32, a: i32, b: i32, bow: i32) void {
    snk.* += 1;
    const t0 = scr.peek(v.sc9 + v.sx);
    if ((t0 != a and t0 != b) or v.al != 0) return;
    const k = snk.*;
    S.ink(14);
    S.draw(0, 77 + k, 319, 77 + k);
    S.copy(.back, 0, 77 + k, 320, 158, .back, 0, 78 + k);
    S.copy(.back, 0, 77 + k, 320, 159, S.lg(), 0, 77 + k);
    if (t0 == bow) S.setZone(60, 90, 126 + k, 319, 168) else S.setZone(60, 0, 126 + k, 240, 168);
}

