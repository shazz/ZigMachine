// --------------------------------------------------------------------------
// Lines 1030-1032 / 1570-1571: a sector's surviving ground guns stamped onto
// the new screen (image 73 on land; on the sea tile 103 on a cleared square)
// with a zone each, and 1580-1581 the gun bits that fall off this screen's
// ground cleared from the world.
// --------------------------------------------------------------------------
const scr = @import("scr.zig");
const scene = @import("scene.zig");
const O = @import("objects.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 1030-1032: the wrecked ground guns (image 73) and their zones.
pub fn guns1030() void {
    scene.toBack();
    v.z = 0;
    v.g = scr.peek(v.ghx9 + v.sx);
    while (v.z < 8) : (v.z += 1) {
        if (v.g >> @intCast(v.z) & 1 == 0) continue;
        v.xx = v.z * 32 + 32;
        v.yy = 160;
        if (v.xx > v.grlx and v.xx + 32 < v.grhx) {
            v.ss = 73;
            O.stamp();
            setZone(v.xx, v.xx + 32, 154, 170);
        }
    }
}

fn setZone(x1: i32, x2: i32, y1: i32, y2: i32) void {
    v.x1 = x1;
    v.x2 = x2;
    v.y1 = y1;
    v.y2 = y2;
    O.zone800();
}

/// 1570-1571: on the sea, the guns as tiles on cleared squares.
pub fn guns1570() void {
    scene.toBack();
    v.z = 0;
    v.g = scr.peek(v.ghx9 + v.sx);
    while (v.z < 8) : (v.z += 1) {
        if (!(v.g >> @intCast(v.z) & 1 != 0 and v.gry < 150)) continue;
        v.xx = v.z * 32 + 32;
        v.yy = @min(144, v.gry + 4);
        if (v.xx >= v.grlx and v.xx + 16 < v.grhx) {
            v.s = 103;
            O.clearedTile();
            setZone(v.xx, v.xx + 32, v.gry, v.gry + 16);
        }
    }
}

/// 1580-1581: a gun bit whose place is off this screen's ground is cleared.
pub fn offGround1580() void {
    v.z = 0;
    while (true) {
        v.xx = 32 + v.z * 32;
        const on = v.g >> @intCast(v.z) & 1 != 0;
        if ((on and v.xx < v.grlx) or v.xx + 32 > v.grhx) {
            v.g &= ~(@as(i32, 1) << @intCast(v.z));
            scr.poke(v.ghx9 + v.sx, v.g);
        }
        v.z += 1;
        if (v.z > 7) return;
    }
}
