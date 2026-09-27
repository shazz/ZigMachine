// --------------------------------------------------------------------------
// Lines 1220-1234: the hill screens -- a slope of 32-pixel steps climbing
// to the right (1220) or to the left (1230), each step two zones deep, the
// ground under them filled with rock, the crest along y = 64.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scene = @import("scene.zig");
const types = @import("scenetypes.zig");
const V = @import("vars.zig");
const v = &V.v;

fn zone(x1: i32, y1: i32, x2: i32, y2: i32) void {
    v.go += 1;
    S.setZone(v.go + 2, x1, y1, x2, y2);
}

/// 1222 / 1232: five crest blocks, alternating, from x0 by dx.
fn crest(x0: i32, dx: i32) void {
    v.a = 0;
    while (v.a < 5) : (v.a += 1) {
        S.move(S.lg(), x0 + v.a * dx, 64, .b5, 256 + v.t * 32, 48 - v.t * 16, 288 + v.t * 32, 80 - v.t * 16);
        v.t = 1 - v.t;
    }
}

pub fn t1220() void {
    scene.grass();
    types.clouds1052();
    v.t = 0;
    v.a = 0;
    while (v.a < 3) : (v.a += 1) {
        S.move(S.lg(), 64 + v.a * 32, 128 - v.a * 32, .b5, 288, v.t * 128, 320, v.t * 128 + 32);
        zone(96 + v.a * 32, 144 - v.a * 32, 319, 160 - v.a * 32);
        zone(112 + v.a * 32, 128 - v.a * 32, 319, 144 - v.a * 32);
        v.t = 1 - v.t;
    }
    v.b = 0;
    while (v.b < 6) : (v.b += 1) {
        S.copy(.b5, 288, 64, 320, 96, S.lg(), 128 + v.b * 32, 96);
        S.copy(.b5, 288, 64, 320, 96, S.lg(), 96 + v.b * 32, 128);
    }
    crest(160, 32);
    S.copy(.b5, 288, 64, 320, 96, S.lg(), 288, 128);
}

pub fn t1230() void {
    scene.grass();
    types.clouds1052();
    v.t = 0;
    v.a = 0;
    while (v.a < 3) : (v.a += 1) {
        S.move(S.lg(), 224 - v.a * 32, 128 - v.a * 32, .b5, 288, 96 + v.t * 64, 320, 128 + v.t * 64);
        zone(0, 144 - v.a * 32, 224 - v.a * 32, 160 - v.a * 32);
        zone(0, 128 - v.a * 32, 208 - v.a * 32, 144 - v.a * 32);
        v.t = 1 - v.t;
    }
    v.b = 0;
    while (v.b < 7) : (v.b += 1) {
        S.copy(.b5, 288, 64, 320, 96, S.lg(), 160 - v.b * 32, 96);
        S.copy(.b5, 288, 64, 320, 96, S.lg(), 160 - v.b * 32, 128);
    }
    crest(128, -32);
    S.copy(.b5, 288, 64, 320, 96, S.lg(), 192, 128);
}
