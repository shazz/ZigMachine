// --------------------------------------------------------------------------
// ZIG mode: a sector of the world drawn OFF SCREEN by the game's own line
// 1000 (scene.draw), so the ring around the plane (zig_ring.zig) shows each
// sector exactly as the original would draw it on arrival -- its type, its
// craters, its wrecked buildings, who holds its airfield.
//
// Line 1000 is not a pure function: it sets zones, sprites, flags, scores a
// building found destroyed, pokes the gun bits, spends clock cycles. So the
// draw runs in a sandbox: every piece of state it can touch is saved, the
// physic and back screens are swapped for two scratch screens, the draw
// runs for (sx, al), and everything is put back. The game never sees it: the
// harness proves it with a CRC of the logic state (apps/skystrike_zig.mjs).
// The bonus bar is left out (zig_hooks.sandbox), since in ZIG it is HUD.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const scr = @import("scr.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const sprite = @import("sprite.zig");
const move = @import("move.zig");
const zone = @import("zone.zig");
const rnd = @import("rnd.zig");
const clock = @import("clock.zig");
const sound = @import("sound.zig");
const B = @import("basic.zig");
const scene = @import("scene.zig");
const hooks = @import("zig_hooks.zig");
const V = @import("vars.zig");
const v = &V.v;

const Saved = struct {
    v: V.V,
    e5: @TypeOf(scr.extra5),
    e6: @TypeOf(scr.extra6),
    b7: @TypeOf(scr.bank7),
    spal: [4][16]u16,
    pix: [4][]u8,
    logic: scr.Id,
    auto_back: bool,
    oob: u32,
    gfx: [4]i32,
    text: [5]i32,
    spr: [16]sprite.Spr,
    drawn: [16]sprite.Rect,
    shown: [16]sprite.Spr,
    dirty: bool,
    move: move.State,
    zone: zone.State,
    rnd: rnd.State,
    clock: clock.State,
    bad: [2]u32,
    sounds: u32,
};

/// A sprite image standing in a sector: the flag, the bridge's arch.
pub const Ent = struct { img: i32, x: i32, y: i32 };
/// What line 1000 leaves as SPRITES rather than pixels, frozen.
pub const Frozen = struct { arch: ?Ent = null, flag: ?Ent = null };

var saved: *Saved = undefined;
var scratch: [2][]u8 = .{ &.{}, &.{} };
/// Sandboxed draws, and the sound commands one made (checked 0).
pub var renders: u32 = 0;
pub var leaks: u32 = 0;

/// Once per cart load, from zg.mem.
pub fn alloc() void {
    if (scratch[0].len != 0) return;
    saved = &zg.mem.mustAlloc(Saved, 1)[0];
    for (&scratch) |*s| s.* = zg.mem.mustAlloc(u8, scr.PIX);
}

fn save() void {
    const s = saved;
    s.v = v.*;
    s.e5 = scr.extra5;
    s.e6 = scr.extra6;
    s.b7 = scr.bank7;
    s.spal = scr.pal;
    s.pix = scr.pix;
    s.logic = scr.logic;
    s.auto_back = scr.auto_back;
    s.oob = scr.oob;
    s.gfx = .{ gfx.ink, gfx.writing, gfx.paint_style, gfx.paint_index };
    s.text = .{ text.cx, text.cy, text.pen, text.paper, @intFromBool(text.under) };
    s.spr = sprite.spr;
    s.drawn = sprite.drawn;
    s.shown = sprite.shown;
    s.dirty = sprite.dirty;
    s.move = move.save();
    s.zone = zone.save();
    s.rnd = rnd.save();
    s.clock = clock.save();
    s.bad = .{ B.bad_index, B.div_zero };
    s.sounds = sound.log_total;
}

fn load() void {
    const s = saved;
    v.* = s.v;
    scr.extra5 = s.e5;
    scr.extra6 = s.e6;
    scr.bank7 = s.b7;
    scr.pal = s.spal;
    scr.pix = s.pix;
    scr.logic = s.logic;
    scr.auto_back = s.auto_back;
    scr.oob = s.oob;
    gfx.ink = @intCast(s.gfx[0]);
    gfx.writing = @intCast(s.gfx[1]);
    gfx.paint_style = s.gfx[2];
    gfx.paint_index = s.gfx[3];
    loadRest(s);
}

fn loadRest(s: *const Saved) void {
    text.cx = s.text[0];
    text.cy = s.text[1];
    text.pen = @intCast(s.text[2]);
    text.paper = @intCast(s.text[3]);
    text.under = s.text[4] != 0;
    sprite.spr = s.spr;
    sprite.drawn = s.drawn;
    sprite.shown = s.shown;
    sprite.dirty = s.dirty;
    move.load(s.move);
    zone.load(s.zone);
    rnd.load(s.rnd);
    clock.load(s.clock);
    B.bad_index = s.bad[0];
    B.div_zero = s.bad[1];
}

/// Sector sx of layer al as line 1000 draws it arriving there (nf = 1, a
/// fresh screen). Its pixels are back() until the next render.
pub fn render(sx: i32, al: i32) Frozen {
    save();
    scr.pix[@intFromEnum(scr.Id.physic)] = scratch[0];
    scr.pix[@intFromEnum(scr.Id.back)] = scratch[1];
    scr.logic = .physic;
    scr.auto_back = true;
    hooks.sandbox = true;
    v.sx = sx;
    v.al = al;
    v.nf = 1;
    scene.draw();
    const f = frozen();
    if (sound.log_total != saved.sounds) leaks += 1;
    hooks.sandbox = false;
    load();
    renders +%= 1;
    return f;
}

/// The arch is the mouse pointer (1300); the airfield's flag is sprite 5
/// (102), first shown as image flg.
fn frozen() Frozen {
    var f: Frozen = .{};
    const m = sprite.spr[0];
    if (m.on) f.arch = .{ .img = m.img, .x = m.x, .y = m.y };
    if (v.flgf != 0) f.flag = .{ .img = v.flg - 1 + v.flgf, .x = 50, .y = 112 };
    return f;
}

pub fn back() []const u8 {
    return scratch[1];
}
