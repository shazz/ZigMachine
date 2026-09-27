// --------------------------------------------------------------------------
// ZIG mode's title-style screen (tscreen.zig, line 2350: the title, the
// difficulty menu, every briefing): the ST's 320 x 200 screen 1:1 at
// screen_x, screen_y of the open frame, and the world extended round it the
// way the flight's ring extends the live screen (zig_ring.zig).
//
// That screen IS a world scene: line 1000's draw of one sector on the ground
// layer (sector 0 on the title and the menu, the player's on a briefing),
// its lines 24-175 moved down 24 lines (so lines 0-47 are the scene's 0-47,
// lines 48-199 its 24-175), the logos and the text written over it, the
// plane and the flag as sprites. So the borders are drawn by the same
// sandboxed line 1000 (zig_sandbox.zig): the left and right ones from the
// neighbouring sectors (sx - 1, sx + 1) of the ground layer, with the same
// 24-line move; the top one from the sky layer above (al = 1) over all three,
// its last 40 lines, which run on into the scene's line 0. The sprites that
// cross the screen's edge (the plane flying across) run on into the borders.
//
// The title's credits scroller is not at its place (80,40 to 256,48) in ZIG:
// what the scene held there before the first letter is put back, and the
// scroller runs in the bottom border instead (zig_scroller.zig).
// Nothing here writes game state; the sandbox puts back all it touches.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const sandbox = @import("zig_sandbox.zig");
const ring = @import("zig_ring.zig");
const hooks = @import("zig_hooks.zig");
const scroller = @import("zig_scroller.zig");
const set = @import("zig_settings.zig");

const W: usize = 400;
const X0: usize = set.screen_x;
const Y0: usize = set.screen_y;
/// The frame above the bottom border: the top border and the screen.
pub const H: usize = Y0 + scr.H;
/// tscreen 2350: the scene's lines 24-175 moved down to 48-199.
const MOVED: usize = 48;
const BY: usize = 24;
/// The title's SCROLL 1 zone (title.zig: 80,40 to 256,48).
pub const ZX: usize = 80;
pub const ZY: usize = 40;
pub const ZW: usize = 176;
pub const ZH: usize = 8;

comptime {
    if (X0 + scr.W > W or X0 > 320) @compileError("the screen must fit the frame, the left border in one sector");
    if (Y0 > ring.LAYER) @compileError("the top border must fit in one sky layer");
}

/// The borders as drawn (400 x H; the screen's own place is not used).
pub var tiles: []u8 = &.{};
/// The scroller's zone as the scene held it before the first letter.
pub var zone: [ZW * ZH]u8 = [_]u8{0} ** (ZW * ZH);
var sector: i32 = 0;
var built: u32 = 0;
var ok: bool = false;

/// Once per cart load, from zg.mem.
pub fn alloc() void {
    if (tiles.len == 0) tiles = zg.mem.mustAlloc(u8, W * H);
}

/// hooks.shows(.scene): the sector line 1000 last drew live is this one;
/// the zone under the scroller is kept before any letter is written in it.
pub fn shown() void {
    sector = hooks.live_sx;
    ok = false;
    const p = scr.get(.physic);
    if (p.len == 0) return;
    for (0..ZH) |j| @memcpy(zone[j * ZW ..][0..ZW], p[(ZY + j) * scr.W + ZX ..][0..ZW]);
}

pub fn draw(ov: []u8) void {
    if (tiles.len == 0) return;
    if (!ok or built != hooks.screen_gen) build();
    const p = scr.get(.physic);
    @memcpy(ov[0 .. W * H], tiles);
    sprites(ov);
    for (0..scr.H) |y| @memcpy(ov[(Y0 + y) * W + X0 ..][0..scr.W], p[y * scr.W ..][0..scr.W]);
    if (scroller.running()) {
        for (0..ZH) |j| @memcpy(ov[(Y0 + ZY + j) * W + X0 + ZX ..][0..ZW], zone[j * ZW ..][0..ZW]);
    }
}

/// The sprites as the last UPDATE drew them, 15 first, the pointer last,
/// over the whole frame (the screen's own pixels then go on top).
fn sprites(ov: []u8) void {
    var n: usize = 16;
    while (n > 0) {
        n -= 1;
        const s = sprite.shown[n];
        if (s.on) sprite.blitClip(ov[0 .. W * H], W, H, s.img, s.x + X0, s.y + Y0);
    }
}

/// The five neighbours, each by line 1000 in the sandbox.
fn build() void {
    for (0..3) |c| sky(c);
    ground(0);
    ground(2);
    built = hooks.screen_gen;
    ok = true;
}

fn sectorAt(c: usize) i32 {
    return ring.wrapSec(sector - 1 + @as(i32, @intCast(c)));
}

/// Column c's part of a frame line, from a 320-wide line of its sector.
fn span(c: usize, dst: []u8, src: []const u8) void {
    switch (c) {
        0 => @memcpy(dst[0..X0], src[scr.W - X0 .. scr.W]),
        1 => @memcpy(dst[X0..][0..scr.W], src[0..scr.W]),
        else => @memcpy(dst[X0 + scr.W .. W], src[0 .. W - X0 - scr.W]),
    }
}

/// The top border: the sky layer's last Y0 lines.
fn sky(c: usize) void {
    _ = sandbox.render(sectorAt(c), 1);
    const b = sandbox.back();
    const top: usize = @as(usize, @intCast(ring.LAYER)) - Y0;
    for (0..Y0) |y| span(c, tiles[y * W ..][0..W], b[(top + y) * scr.W ..][0..scr.W]);
}

/// A side border: the ground layer, moved as tscreen moves its scene.
fn ground(c: usize) void {
    const f = sandbox.render(sectorAt(c), 0);
    const b = sandbox.back();
    for (0..scr.H) |y| {
        const from = if (y < MOVED) y else y - BY;
        span(c, tiles[(Y0 + y) * W ..][0..W], b[from * scr.W ..][0..scr.W]);
    }
    const dx: i32 = if (c == 0) @as(i32, X0) - 320 else @as(i32, X0) + 320;
    inline for (.{ f.flag, f.arch }) |e| if (e) |s| {
        sprite.blitClip(tiles, W, H, s.img, dx + s.x, @as(i32, @intCast(Y0 + BY)) + s.y);
    };
}
