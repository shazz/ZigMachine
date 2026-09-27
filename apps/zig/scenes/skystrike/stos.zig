// --------------------------------------------------------------------------
// The STOS runtime the game's code calls, in one place: short names for the
// commands, each forwarding to the module that models it. TIMER counts the
// 50 Hz VBLs (the machine's vbl() increments it).
// --------------------------------------------------------------------------
const scr = @import("scr.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const blocks = @import("blocks.zig");
const sprite = @import("sprite.zig");
const zonem = @import("zone.zig");
const pal = @import("pal.zig");
const input = @import("input.zig");
const rndm = @import("rnd.zig");

pub const Id = scr.Id;

pub var timer: i32 = 0;

pub fn rnd(n: i32) i32 {
    return rndm.rnd(n);
}

pub fn sprite_(n: i32, x: i32, y: i32, i: i32) void {
    sprite.set(n, x, y, i);
}
pub fn update() void {
    sprite.update();
}
pub fn putSprite(n: i32) void {
    sprite.put(n);
}
pub fn zone(n: i32) i32 {
    return zonem.zone(n);
}
pub fn setZone(z: i32, x1: i32, y1: i32, x2: i32, y2: i32) void {
    zonem.set(z, x1, y1, x2, y2);
}
pub fn collide(n: i32, w: i32, h: i32) i32 {
    return zonem.collide(n, w, h);
}

pub fn ink(c: i32) void {
    gfx.ink = @intCast(c & 15);
}
pub fn bar(x1: i32, y1: i32, x2: i32, y2: i32) void {
    gfx.bar(x1, y1, x2, y2);
}
pub fn box(x1: i32, y1: i32, x2: i32, y2: i32) void {
    gfx.box(x1, y1, x2, y2);
}
pub fn draw(x1: i32, y1: i32, x2: i32, y2: i32) void {
    gfx.draw(x1, y1, x2, y2);
}
pub fn point(x: i32, y: i32) i32 {
    return gfx.point(x, y);
}

pub fn paper(c: i32) void {
    text.paper = @intCast(c & 15);
}
pub fn pen(c: i32) void {
    text.pen = @intCast(c & 15);
}
pub fn locate(x: i32, y: i32) void {
    text.locate(x, y);
}
pub fn centre(s: []const u8) void {
    text.centre(s);
}
pub fn write(s: []const u8) void {
    text.write(s);
}
pub fn print(s: []const u8) void {
    text.print(s);
}

/// SCREEN COPY src,x1,y1,x2,y2 TO dst,x,y
pub fn copy(src: Id, x1: i32, y1: i32, x2: i32, y2: i32, dst: Id, x: i32, y: i32) void {
    blocks.copy(src, x1, y1, x2, y2, dst, x, y);
}
/// SCREEN$(dst,x,y) = SCREEN$(src,x1,y1 TO x2,y2)
pub fn move(dst: Id, x: i32, y: i32, src: Id, x1: i32, y1: i32, x2: i32, y2: i32) void {
    blocks.move(src, x1, y1, x2, y2, dst, x, y);
}
/// The logical screen's id (LOGIC as a screen argument).
pub fn lg() Id {
    return scr.logic;
}

pub fn fadeBlack(s: i32) void {
    pal.fadeBlack(s);
}
pub fn fadeTo(s: i32, id: Id) void {
    pal.fadeTo(s, id);
}

pub fn jup() i32 {
    return input.jup();
}
pub fn jdown() i32 {
    return input.jdown();
}
pub fn jleft() i32 {
    return input.jleft();
}
pub fn jright() i32 {
    return input.jright();
}
pub fn fire() i32 {
    return input.fire();
}
pub fn mouseKey() i32 {
    return input.mouseKey();
}
