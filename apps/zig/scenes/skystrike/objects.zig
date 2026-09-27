// --------------------------------------------------------------------------
// The screen builders' common routines: 800-810 (zones), 900 (a stamp),
// 945 (count the gun bits), 1900-1920 (the bank-8 object table: one screen
// type's objects, their zones, the guns standing on them), 1960-1980 (16 x 16
// tiles from bank 5 by number, row after row from a digit string).
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const B = @import("basic.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 900: sprite 15,xx,yy,ss : update : put sprite 15
pub fn stamp() void {
    S.sprite_(15, v.xx, v.yy, v.ss);
    S.update();
    S.putSprite(15);
}

/// 945: bc = the number of bits set in g (the loop leaves a = 8).
pub fn countBits() void {
    v.bc = 0;
    v.a = 0;
    while (true) {
        v.bc -= B.t(v.g >> @intCast(v.a & 31) & 1 != 0);
        v.a += 1;
        if (v.a == 8) break;
    }
}

/// 800-809: zone go + 2 over x1,y1 to x2,y2, clipped.
pub fn zone800() void {
    v.x1 = @max(0, @min(318, v.x1));
    v.x2 = @max(0, @min(319, v.x2));
    v.go = @min(127, v.go + 1);
    S.setZone(v.go + 2, v.x1, @max(0, v.y1), v.x2, @min(175, v.y2));
}

/// 810: the zones of this screen's vehicle wrecks.
pub fn wreckZones() void {
    v.a = 0;
    while (true) {
        const sx = B.ix(52, v.sx);
        v.x1 = v.snox_a[sx][B.ix(4, v.a)] - 16;
        v.x2 = v.snox_a[sx][B.ix(4, v.a)] + 16;
        v.y1 = 146;
        v.y2 = 160;
        zone800();
        v.a += 1;
        if (v.a >= @min(3, scr.peek(v.sno9 + v.sx))) break;
    }
}

fn pk(p: i32, o: i32) i32 {
    return scr.peek(p + o);
}

/// 1900-1920: the objects of screen type s, from column lx, with AUTO BACK
/// off while they are drawn.
pub fn objects() void {
    v.ex = 0;
    scr.auto_back = false;
    v.a = 0;
    v.bc = scr.peek(v.lc9 + v.sx);
    v.gh = 0;
    while (scr.peek(scr.start(8) + v.s * 160 + v.a * 8) > 0 and v.a < 10) {
        v.p = scr.start(8) + v.s * 160 + v.a * 8;
        v.xx = (v.lx + pk(v.p, 5)) * 16;
        v.yy = pk(v.p, 6);
        v.rp = pk(v.p, 7);
        v.rp2 = v.rp;
        gunOn();
        if (v.hf != 0) damaged();
        object();
        v.a += 1;
    }
    scr.auto_back = true;
    if (v.gh > v.bc) {
        v.scre += (v.gh - v.bc) * v.scrb;
        @import("hud.zig").score();
    }
    scr.poke(v.lc9 + v.sx, @max(v.gh, v.bc));
}

/// 1903: does a gun stand on this object?
fn gunOn() void {
    v.z = 0;
    v.hf = 0;
    v.g = scr.peek(v.ghx9 + v.sx);
    while (v.z < 8 and v.hf == 0) {
        const w = (pk(v.p, 3) - pk(v.p, 1)) * 16 * (v.rp2 + 1);
        if (v.g >> @intCast(v.z) & 1 != 0 and v.z * 32 + 64 >= v.xx and v.z * 32 + 32 <= v.xx + w) {
            v.hf = 1;
            v.gh += 1;
            v.z = 99;
        }
        v.z += 1;
    }
}

/// 1904: a gun stood on it: the object's wrecked form, 80 bytes on.
fn damaged() void {
    v.p += 80;
    v.xx = (v.lx + pk(v.p, 5)) * 16;
    v.yy = pk(v.p, 6);
    v.rp = pk(v.p, 7);
}

/// 1905-1912: the object, repeated rp more times to its right.
fn object() void {
    if (pk(v.p, 0) == 0) return;
    const src: scr.Id = if (pk(v.p, 0) == 5) .b5 else .b6;
    const w = pk(v.p, 3) * 16 - pk(v.p, 1) * 16;
    while (true) {
        S.move(S.lg(), v.xx, v.yy, src, pk(v.p, 1) * 16, pk(v.p, 2), pk(v.p, 3) * 16, pk(v.p, 4));
        v.go += 1;
        S.setZone(v.go + 2, v.xx, v.yy, @min(319, v.xx + w), v.yy + pk(v.p, 4) - pk(v.p, 2));
        if (v.rp <= 0) return;
        v.rp -= 1;
        v.xx += w;
    }
}

/// 1960: tile s of bank 5 (20 a row from y = 96) at xx,yy.
pub fn tile() void {
    const x1 = B.mod(v.s, 20) * 16;
    const y1 = B.div(v.s, 20) * 16 + 96;
    v.x1 = x1;
    v.y1 = y1;
    S.move(S.lg(), v.xx, v.yy, .b5, x1, y1, x1 + 16, y1 + 16);
}

/// 1970: the tiles of m$ (two digits each) from lx, ly.
pub fn tiles() void {
    const m = v.m_s.get();
    v.a = 0;
    while (true) {
        const i: usize = @intCast(v.a * 2);
        v.s = if (i + 2 <= m.len) (m[i] - '0') * 10 + (m[i + 1] - '0') else 0;
        v.xx = v.lx * 16 + v.a * 16;
        v.yy = v.ly;
        tile();
        v.a += 1;
        if (v.a * 2 >= m.len) break;
    }
}

/// 1980: tiles() and a zone over them.
pub fn tilesZone() void {
    tiles();
    v.go += 1;
    S.setZone(v.go + 2, v.lx * 16, v.ly, @min(319, v.lx * 16 + v.a * 16), v.ly + 16);
}

/// 1975: ink 14 : auto back off : bar under the tile : auto back on : tile
pub fn clearedTile() void {
    S.ink(14);
    scr.auto_back = false;
    S.bar(@max(0, @min(319, v.xx)), v.yy, @max(0, @min(319, v.xx + 15)), v.yy + 15);
    scr.auto_back = true;
    tile();
}

/// m$ = s ; lx ; ly
pub fn setM(s: []const u8, lx: i32, ly: i32) void {
    v.m_s.set(s);
    v.lx = lx;
    v.ly = ly;
}
