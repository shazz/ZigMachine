// --------------------------------------------------------------------------
// Line 1000: a screen of the world drawn afresh (sector sx, altitude layer
// al) -- the sky, what stands on the ground by screen type, the wrecks, the
// zones (the ground guns, 1030 / 1570-1581, are groundguns.zig); 1400-1421
// the grass and the panel; 1500-1506 the three message styles.
// --------------------------------------------------------------------------
const S = @import("stos.zig");
const scr = @import("scr.zig");
const text = @import("text.zig");
const sprite = @import("sprite.zig");
const zone = @import("zone.zig");
const clock = @import("clock.zig");
const B = @import("basic.zig");
const O = @import("objects.zig");
const T = @import("scenetypes.zig");
const guns = @import("groundguns.zig");
const V = @import("vars.zig");
const v = &V.v;

fn sc(o: i32) i32 {
    return scr.peek(v.sc9 + o);
}

/// 1000-1029
pub fn draw() void {
    clock.spend(clock.REDRAW);
    v.g = scr.peek(v.ghx9 + v.sx);
    O.countBits();
    sprite.mouse(false, sprite.spr[0].img, sprite.spr[0].x, sprite.spr[0].y);
    v.ms = 0;
    zone.resetAll();
    v.al = @max(0, v.al);
    v.xo = v.x;
    v.yo = v.y;
    v.xo2 = v.x;
    v.yo2 = v.y;
    v.scrb = 0;
    resetFlags();
    sprite.allOff();
    S.ink(14);
    S.bar(0, 0, 319, 175);
    if (v.al == 0 and sc(0) < 20) T.onType(sc(v.sx));
    if (v.al == 0 and sc(v.sx) >= 20 and sc(v.sx) <= 35) T.t1070();
    draw1008();
}

fn resetFlags() void {
    inline for (.{ "net", "arr", "shrk", "sea", "gtg3", "flf", "fl", "flgf", "go", "brdg", "sglf" }) |n| @field(v.*, n) = 0;
    v.nso = 1;
    v.gry = 154;
    v.grlx = 0;
    v.grhx = 320;
}

/// 1008-1029
fn draw1008() void {
    v.nf = 0;
    v.g = scr.peek(v.ghx9 + v.sx);
    O.countBits();
    if (v.al == 0 and v.bc != 0 and v.sea == 0) guns.guns1030();
    if (v.al == 0 and v.bc != 0 and v.sea == 1) guns.guns1570();
    if (v.al != 0) T.clouds1052();
    toBack();
    clock.waitVbl();
    if (v.ms != 0) {
        sprite.mouse(true, sprite.spr[0].img, sprite.spr[0].x, sprite.spr[0].y);
        v.ms = 0;
    }
    if (v.al == 0 and scr.peek(v.sno9 + v.sx) > 0) O.wreckZones();
    @import("hud.zig").bonusBar();
    v.gtg1 = 0;
    v.gtg3 = 0;
}

/// 192: screen copy logic to back
pub fn toBack() void {
    @import("blocks.zig").copyAll(scr.logic, .back);
}

/// 193: screen copy back to logic
pub fn toLogic() void {
    @import("blocks.zig").copyAll(.back, scr.logic);
}

/// 1400-1404: the grass strip, and on an empty sector one decoration.
pub fn grass() void {
    var a: i32 = 0;
    while (a < 5) : (a += 1) S.move(S.lg(), a * 64, 160, .b6, 0, 0, 64, 16);
    v.a = 5;
    if (!(v.sx > 1 and sc(v.sx) == 0)) return;
    v.q = B.mod(B.div(B.mod(v.sx * 43, 35) * 3, 10), 6);
    if (v.q >= 1 and v.q <= 3) {
        v.a = B.mod(v.sx, 8);
        S.move(S.lg(), v.a * 32 + 32, 160, .b6, (v.q - 1) * 64 + 128, 0, v.q * 64 + 128, 16);
    } else if (v.q >= 4 and v.q <= 5) {
        v.a = B.mod(v.sx, 8);
        S.move(S.lg(), v.a * 32 + 32, 160, .b6, (v.q - 4) * 64 + 64, 16, (v.q - 3) * 64 + 64, 32);
    }
}

/// 1420-1421: the panel's two rows, then onto the back screen.
pub fn panel() void {
    S.copy(.b6, 192, 16, 240, 24, S.lg(), 0, 176);
    v.a = 48;
    while (v.a < 224) : (v.a += 32) S.copy(.b6, 192, 24, 224, 32, S.lg(), v.a, 176);
    S.copy(.b6, 240, 16, 256, 24, S.lg(), 224, 176);
    S.copy(.b6, 224, 24, 256, 32, S.lg(), 96, 176);
    S.copy(.b6, 256, 16, 272, 32, S.lg(), 0, 184);
    v.a = 16;
    while (v.a < 224) : (v.a += 32) S.copy(.b6, 288, 16, 320, 32, S.lg(), v.a, 184);
    S.copy(.b6, 272, 16, 288, 32, S.lg(), 224, 184);
    S.copy(S.lg(), 0, 176, 240, 200, .back, 0, 176);
}

fn say(y: i32, pen: i32) void {
    S.locate(1, y);
    S.paper(14);
    S.pen(pen);
    var buf: [320]u8 = undefined;
    const m = v.mes_s.get();
    buf[0] = ' ';
    @memcpy(buf[1 .. m.len + 1], m);
    buf[m.len + 1] = ' ';
    S.centre(buf[0 .. m.len + 2]);
    v.mes_s.len = 0;
}

/// 1500: the message on line 5, pen 13
pub fn message1500() void {
    say(5, 13);
}

/// 1505: the message on line 3, pen 1
pub fn message1505() void {
    say(3, 1);
}

/// 1506: the message boxed on line 9
pub fn message1506() void {
    S.paper(14);
    S.pen(1);
    const n: i32 = @intCast(v.mes_s.len);
    v.xx = 19 - B.div(n, 2);
    S.locate(v.xx, 8);
    text.square(n + 2, 3, 1);
    S.pen(0);
    S.locate(v.xx + 1, 9);
    S.write(v.mes_s.get());
    v.mes_s.len = 0;
}

/// OFF: every sprite switched off and every movement stopped (the ST's
/// sprite table after 34's OFF: all fifteen inactive, their places kept).
pub fn off() void {
    sprite.allOff();
}
