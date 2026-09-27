// --------------------------------------------------------------------------
// Ground guns (8 a sector, bits of ghx9 + sector): 920-929 one destroyed
// by a bomb, rocket or falling plane at column ghx of sector csx; 1950-1958
// the screen's objects redrawn round the wreck; 820-822 a base repaired.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const scene = @import("scene.zig");
const types = @import("scenetypes.zig");
const damage = @import("damage.zig");
const blast = @import("blast.zig");
const sfx = @import("sfx.zig");
const hud = @import("hud.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 920-929
pub fn gunHit920() void {
    v.az = v.a;
    v.ghx = @max(0, v.ghx - 1);
    v.g = scr.peek(v.ghx9 + v.csx);
    v.g |= @as(i32, 1) << @intCast(v.ghx & 31);
    scr.poke(v.ghx9 + v.csx, v.g);
    O.countBits();
    v.x1 = (v.ghx + 1) * 40;
    v.x2 = v.x1 + 32;
    v.y1 = 152;
    v.y2 = 170;
    O.zone800();
    v.ex = v.x1;
    v.ey = 160;
    v.esx = v.csx;
    v.esy = 0;
    damage.water650();
    blast.explode400();
    gunHit921();
    v.a = v.az;
}

fn gunHit921() void {
    if (v.csx == v.sx and v.cal == v.al) {
        v.xx = (v.ghx + 1) * 40;
        v.yy = 160;
        v.ss = 73;
        O.stamp();
    }
    if (scr.peek(v.sc9 + v.csx) == 1 and v.bc == 3) {
        v.bse = v.bse_a[B.ix(42, B.div(v.csx, 10))];
        v.bse_a[B.ix(42, B.div(v.csx, 10))] = 0;
        v.scre += 5000 * v.bse;
        hud.score();
    }
    if (v.csx == v.sx and v.nf == 0) {
        redraw1950();
        @import("groundguns.zig").offGround1580();
    }
    if (v.csx == v.tgtx and v.bc >= 3) v.mif_a[6] = 1;
}

/// 1950-1958: hide the pointer, OFF, the splash / crash sound, the
/// screen's objects again (no fresh sky), back = logic, REDRAW.
fn redraw1950() void {
    sprite.mouse(false, sprite.spr[0].img, sprite.spr[0].x, sprite.spr[0].y);
    v.g = scr.peek(v.ghx9 + v.sx);
    v.a9 = v.a;
    scene.off();
    sfx.splash();
    v.go = 0;
    const t = scr.peek(v.sc9 + v.sx);
    if (v.al == 0 and t < 20) types.onTypeRedraw(t);
    if (v.al == 0 and t >= 20 and t <= 35) types.t1070();
    const guns = scr.peek(v.ghx9 + v.sx) != 0;
    if (v.al == 0 and guns and v.sea == 0) @import("groundguns.zig").guns1030();
    if (v.al == 0 and guns and v.sea == 1) @import("groundguns.zig").guns1570();
    scene.toBack();
    sprite.dirty = true;
    S.update();
    v.a = v.a9;
}

/// 820-822: repairs at base rqsx run rqt passes; a captured base is ours.
pub fn repair820() void {
    v.rqt -= 1;
    if (v.rqt > 0) return;
    if (B.mod(v.rqsx, 10) == 0 and v.bse_a[B.ix(42, B.div(v.rqsx, 10))] == 0) {
        v.scre += 5000;
        v.bse_a[B.ix(42, B.div(v.rqsx, 10))] = -1;
    }
    scr.poke(v.lc9 + v.rqsx, 0);
    scr.poke(v.ghx9 + v.rqsx, 0);
    scr.poke(v.sno9 + v.rqsx, 0);
    v.rqsx = -1;
}
