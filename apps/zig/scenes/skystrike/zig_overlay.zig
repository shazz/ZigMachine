// --------------------------------------------------------------------------
// ZIG mode's sprites, on the overlay plane over the scrolled world.
//
// The live screen's sprites are the sprite table as the last UPDATE drew it
// (sprite.shown), each at its place in the world, in STOS's order: 15 first,
// 1 last, the pointer (the bridge's arch) over all. Sprite 15 is skipped: the
// game only ever uses it as a stamp (put sprite 15 into back), so its pixels
// are in the world already -- in the HUD they would be drawn twice.
//
// The NEIGHBOURING sectors' sprites. The original shows only the current
// screen, but it moves the enemies, the vehicles, the bomb, the rocket, the
// crate and the enemy pilot everywhere, every pass (they carry their own
// sector and layer): those are drawn where they are now. What line 1000
// makes a sprite on arrival -- an airfield's flag, the bridge's arch -- is
// drawn as the ring's sandboxed draw left it, and a sector's wrecks as its
// wreck table (so9, snox) holds them: frozen, as the sector was last drawn.
// Nothing here changes any game state.
// --------------------------------------------------------------------------
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const ring = @import("zig_ring.zig");
const hooks = @import("zig_hooks.zig");
const scroll = @import("zig_scroll.zig");
const V = @import("vars.zig");
const v = &V.v;

pub const CLEAR: u8 = 255;
const W: i32 = scroll.WIN_W;

var view: []u8 = &.{};
var cam: [2]i32 = .{ 0, 0 };

/// An index clamped into 0..len-1 WITHOUT counting it: basic.ix() bumps the
/// game's bad_index (a harness check), which a picture must never touch.
pub fn quiet(len: usize, i: i32) usize {
    return @intCast(@max(0, @min(@as(i32, @intCast(len)) - 1, i)));
}

/// Image `img` with its hot spot at line y, column x of layer l, sector s.
fn put(s: i32, l: i32, x: i32, y: i32, img: i32) void {
    const px = ring.wrapDelta(ring.seat(s) * ring.SEC + x - cam[0]);
    const py = -l * ring.LAYER + y - cam[1];
    sprite.blitClip(view, W, scroll.VIEW_H, img, px, py);
}

/// In the ring and not the live screen (whose own sprites show it).
fn away(s: i32, l: i32) bool {
    if (ring.colOf(s) == null or ring.rowOf(l) == null) return false;
    return !(s == hooks.live_sx and l == hooks.live_al);
}

pub fn draw(ov: []u8, at: [2]i32) void {
    view = ov[0..@intCast(W * scroll.VIEW_H)];
    cam = at;
    @memset(view, CLEAR);
    wrecks();
    frozen();
    moving();
    live();
}

/// 490: each ground sector's wrecks, where its table puts them.
fn wrecks() void {
    for (0..3) |c| {
        const s = ring.sectorOf(c);
        if (!away(s, 0)) continue;
        const n = @min(4, scr.peek(v.sno9 + s));
        var a: i32 = 0;
        while (a < n) : (a += 1) put(s, 0, v.snox_a[quiet(52, s)][quiet(4, a)], 160, scr.peek(v.so9 + s * 4 + a));
    }
}

/// 102 / 1300: the flags and arches of the other slots' draws.
fn frozen() void {
    for (0..3) |r| for (0..3) |c| {
        const s = ring.sectorOf(c);
        const l = ring.layerOf(r);
        if (!away(s, l)) continue;
        const f = ring.frozenAt(r, c);
        if (f.flag) |e| put(s, l, e.x, e.y, e.img);
        if (f.arch) |e| put(s, l, e.x, e.y, e.img);
    };
}

/// What the game moves everywhere, in sprite order 14 .. 2.
fn moving() void {
    if (v.epcf != 0 and away(v.epsx, v.epal)) put(v.epsx, v.epal, v.epx, v.epy, 59 + v.epv);
    var a: usize = 6;
    while (a > 0) {
        a -= 1;
        if (v.vs_a[a] > 0 and v.bale == 0 and away(v.vsx_a[a], 0)) put(v.vsx_a[a], 0, v.vx_a[a], 160, v.vs_a[a]);
    }
    if (v.bnf != 0 and away(v.bosx, v.boal)) {
        put(v.bosx, v.boal, v.bnx, v.bny, 74);
        put(v.bosx, v.boal, v.bnx, v.bny + 10, v.bns_a[quiet(16, v.bns)]);
    }
    if (v.rkf != 0 and away(v.rksx, v.rkal)) put(v.rksx, v.rkal, v.rkx, v.rky, 50 + v.rkr);
    if (v.bf != 0 and away(v.bsx, v.bal)) put(v.bsx, v.bal, v.bx, v.by, 22 + v.br);
    for (0..2) |i| {
        const e = 1 - i;
        if (away(v.esx_a[e], v.eal_a[e])) put(v.esx_a[e], v.eal_a[e], v.ex_a[e], v.ey_a[e], v.er_a[e] + v.ea_a[e]);
    }
    if (v.bale != 0 and away(v.psx, v.pal)) put(v.psx, v.pal, v.x, v.y, v.s_a[quiet(16, v.r)][quiet(2, v.uc)]);
}

/// The live screen's sprites 14 .. 1, then the pointer.
fn live() void {
    var n: usize = 14;
    while (n >= 1) : (n -= 1) one(sprite.shown[n]);
    one(sprite.shown[0]);
}

fn one(s: sprite.Spr) void {
    if (s.on) put(s.fx, s.fy, s.x, s.y, s.img);
}
