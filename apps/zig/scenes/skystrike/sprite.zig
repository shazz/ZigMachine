// --------------------------------------------------------------------------
// STOS's 15 sprites and the mouse pointer, over the bank-1 images.
//
// Each sprite is an image number and the screen position of its HOT SPOT.
// The engine draws on the PHYSICAL screen only: when anything changed (at the
// next VBL, or at once on UPDATE) it restores the old areas from the back
// screen and draws every sprite again, sprite 15 first and sprite 1 last,
// the mouse pointer over all (the ST's priority list $3A986 holds 15..1, 0).
// PUT SPRITE n stamps sprite n's image into the back screen, so it stays
// when the sprite moves on (the game draws its HUD digits and smoke trails
// this way). CHANGE MOUSE n (n > 3) makes the pointer sprite image n - 3:
// the bridge screen's arch is the pointer, image 79, fixed by LIMIT MOUSE.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const assets = @import("assets.zig");
const scr = @import("scr.zig");

pub const Img = struct { w: i32 = 0, h: i32 = 0, hx: i32 = 0, hy: i32 = 0, off: usize = 0 };
pub const Spr = struct { on: bool = false, x: i32 = 0, y: i32 = 0, img: i32 = 0 };
const Rect = struct { x0: i32 = 0, y0: i32 = 0, x1: i32 = -1, y1: i32 = -1 };

pub const NIMG: usize = 124;
pub var imgs: [NIMG]Img = [_]Img{.{}} ** NIMG;
comptime {
    // load() puts image i at imgs[i + 1]: the bank's count must leave room.
    if (be(16, u16) >= NIMG) @compileError("sprites.bnk has more images than imgs holds");
}
var pool: []u8 = &.{};
pub const CLEAR: u8 = 0xFF;

/// 0 is the mouse pointer, 1..15 the sprites.
pub var spr: [16]Spr = [_]Spr{.{}} ** 16;
var drawn: [16]Rect = [_]Rect{.{}} ** 16;
pub var dirty: bool = false;

fn be(o: usize, comptime T: type) T {
    return std.mem.readInt(T, assets.SPRITES[o..][0..@sizeOf(T)], .big);
}

/// Decode the bank once: per image, the mask (a set bit = clear) and then
/// the 4 planes, a word a 16 pixels, line by line; CLEAR marks a hole.
pub fn load() void {
    if (pool.len != 0) return;
    const lo: usize = 4 + be(4, u32);
    const n: usize = be(16, u16);
    var total: usize = 0;
    for (0..n) |i| total += @as(usize, assets.SPRITES[lo + i * 8 + 4]) * 16 * assets.SPRITES[lo + i * 8 + 5];
    pool = zg.mem.mustAlloc(u8, total);
    var at: usize = 0;
    for (0..n) |i| {
        const e = lo + i * 8;
        const w: usize = assets.SPRITES[e + 4];
        const h: usize = assets.SPRITES[e + 5];
        imgs[i + 1] = .{ .w = @intCast(w * 16), .h = @intCast(h), .hx = assets.SPRITES[e + 6], .hy = assets.SPRITES[e + 7], .off = at };
        decode(lo + be(e, u32), w, h, pool[at..][0 .. w * 16 * h]);
        at += w * 16 * h;
    }
}

fn decode(src: usize, w: usize, h: usize, out: []u8) void {
    const planes = src + w * h * 2;
    for (0..h * w) |k| {
        const m = be(src + k * 2, u16);
        for (0..16) |b| {
            const bit: u4 = @intCast(15 - b);
            var v: u8 = 0;
            for (0..4) |p| v |= @as(u8, @intCast(be(planes + k * 8 + p * 2, u16) >> bit & 1)) << @intCast(p);
            out[k * 16 + b] = if (m >> bit & 1 != 0) CLEAR else v;
        }
    }
}

pub fn reset() void {
    spr = [_]Spr{.{}} ** 16;
    drawn = [_]Rect{.{}} ** 16;
    dirty = false;
}

/// SPRITE n,x,y,i.
pub fn set(n: i32, x: i32, y: i32, img: i32) void {
    const s = &spr[@intCast(n & 15)];
    s.* = .{ .on = true, .x = x, .y = y, .img = img };
    dirty = true;
}

/// dreg(0)=7 : dreg(2)=0 : trap 5 -- the sprite trap's function 7 ($3D0E0):
/// every movement and animation cleared ($3D0A6, $3D078), then every sprite
/// off.
pub fn allOff() void {
    @import("move.zig").reset();
    for (spr[1..]) |*s| s.on = false;
    dirty = true;
}

fn rectOf(s: Spr) Rect {
    if (!s.on or s.img <= 0 or s.img >= NIMG) return .{};
    const im = imgs[@intCast(s.img)];
    const x0 = s.x - im.hx;
    const y0 = s.y - im.hy;
    return .{ .x0 = @max(0, x0), .y0 = @max(0, y0), .x1 = @min(319, x0 + im.w - 1), .y1 = @min(199, y0 + im.h - 1) };
}

fn restore(r: Rect) void {
    const p = scr.get(.physic);
    const b = scr.get(.back);
    const n: usize = @intCast(r.x1 - r.x0 + 1);
    var y = r.y0;
    while (y <= r.y1) : (y += 1) {
        const o: usize = @intCast(y * 320 + r.x0);
        @memcpy(p[o..][0..n], b[o..][0..n]);
    }
}

/// Draw image `img` with its hot spot at (x, y) into `dst`.
pub fn blit(dst: []u8, img: i32, x: i32, y: i32) void {
    if (img <= 0 or img >= NIMG) return;
    const im = imgs[@intCast(img)];
    const src = pool[im.off..][0..@intCast(im.w * im.h)];
    var j: i32 = 0;
    while (j < im.h) : (j += 1) {
        const ty = y - im.hy + j;
        if (ty < 0 or ty > 199) continue;
        var i: i32 = 0;
        while (i < im.w) : (i += 1) {
            const tx = x - im.hx + i;
            const v = src[@intCast(j * im.w + i)];
            if (tx >= 0 and tx <= 319 and v != CLEAR) dst[@intCast(ty * 320 + tx)] = v;
        }
    }
}

/// UPDATE: the old areas restored from back, every sprite drawn again.
pub fn update() void {
    if (!dirty) return;
    dirty = false;
    for (drawn) |r| if (r.x1 >= r.x0) restore(r);
    const p = scr.get(.physic);
    var n: usize = 15;
    while (true) : (n -= 1) {
        const s = spr[n];
        drawn[n] = rectOf(s);
        if (drawn[n].x1 >= drawn[n].x0) blit(p, s.img, s.x, s.y);
        if (n == 0) break;
    }
}

/// PUT SPRITE n: its image into the back screen.
pub fn put(n: i32) void {
    const s = spr[@intCast(n & 15)];
    if (s.on) blit(scr.get(.back), s.img, s.x, s.y);
}

/// The mouse pointer is sprite 0: SHOW ON / HIDE ON, CHANGE MOUSE, LIMIT MOUSE.
pub fn mouse(show: bool, img: i32, x: i32, y: i32) void {
    spr[0] = .{ .on = show, .x = x, .y = y, .img = img };
    dirty = true;
}
