// --------------------------------------------------------------------------
// ZIG mode's hall of fame and its name entry (hiscore.zig, histable.zig):
// the picture scaled to fill the open frame, the text over it 1:1, in the
// game's font at its own size, the 320 x 200 layout kept whole and centred
// (screen_x, screen_y).
//
// The two layers are kept apart as the game makes them:
//   the picture  HIPIC.PAC as it stands on the physic screen at 2260, before
//                the table is pasted on (hooks.shows(.hall));
//   the text     every character cell the game draws from then on (text.zig's
//                PRINT, via hooks.textCell): its ink in the pen, its paper in
//                the paper -- except paper 0, which the table's paste (2274,
//                a transparent SCREEN$) leaves out. The name entry's cells
//                (paper 3, the cursor's paper 15) are opaque, as drawn.
// A text pixel is shown where the physic screen holds it, so the APPEAR that
// brings the table in (2280) brings it in here too, pixel by pixel.
//
// Only what changed is redrawn (every overlay store is a bus write on the
// board): the frame is drawn whole once, then a text cell is redrawn only
// when the game wrote it again or the physic screen under it changed. A
// pixel outside every written cell is the scaled picture whatever the physic
// screen holds, so those cells are never looked at again. Byte-identical to
// drawing the whole frame every frame.
// Nothing here writes game state.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const scr = @import("scr.zig");
const text = @import("text.zig");
const screens = @import("zig_screens.zig");
const set = @import("zig_settings.zig");

pub const CLEAR: u8 = 255;
const W: usize = 400;
const CW: usize = scr.W / 8;
const CH: usize = scr.H / 8;
comptime {
    if (CW * 8 != scr.W or CH * 8 != scr.H) @compileError("the screen must be whole cells");
    // The 1:1 screen lies inside the scaled picture (no top/bottom fill under it).
    if (set.screen_y < screens.Y0 or set.screen_y + scr.H > screens.Y0 + screens.SH) @compileError("the screen must lie on the scaled picture");
}

/// The picture, and the text (CLEAR where there is none), 320 x 200 each.
pub var pic: []u8 = &.{};
pub var layer: []u8 = &.{};
/// The physic screen as the overlay last showed it (whole cells only).
var shadow: []u32 = &.{};
/// Cells the game has drawn since the picture was shown, and those drawn
/// since the overlay last showed them.
var written = [_]bool{false} ** (CW * CH);
var dirty = [_]bool{false} ** (CW * CH);
/// The overlay holds a whole hall frame (nothing else has written it since).
var painted: bool = false;

/// Once per cart load, from zg.mem.
pub fn alloc() void {
    if (pic.len == 0) pic = zg.mem.mustAlloc(u8, scr.PIX);
    if (layer.len == 0) layer = zg.mem.mustAlloc(u8, scr.PIX);
    if (shadow.len == 0) shadow = zg.mem.mustAlloc(u32, scr.PIX / 4);
    painted = false;
}

/// Whoever else draws on the overlay calls this: the next hall frame is drawn whole.
pub fn invalidate() void {
    painted = false;
}

/// hooks.shows(.hall): the physic screen is the bare picture.
pub fn shown() void {
    const p = scr.get(.physic);
    if (pic.len == 0 or p.len == 0) return;
    @memcpy(pic, p);
    @memset(layer, CLEAR);
    @memset(&written, false);
    painted = false;
}

/// Cell col, row as text.zig draws it now (pen, paper, UNDER).
pub fn cell(c: u8, col: i32, row: i32) void {
    if (layer.len == 0) return;
    const paper: u8 = if (text.paper == 0) CLEAR else text.paper;
    for (0..8) |j| {
        const bits = text.cellBits(c, j);
        const o: usize = @intCast((row * 8 + @as(i32, @intCast(j))) * 320 + col * 8);
        for (0..8) |i| layer[o + i] = if (bits >> @intCast(7 - i) & 1 != 0) text.pen else paper;
        const k = o / scr.W / 8 * CW + o % scr.W / 8;
        written[k] = true;
        dirty[k] = true;
    }
}

pub fn draw(ov: []u8) void {
    if (pic.len == 0) return;
    const p = scr.get(.physic);
    if (!painted or shadow.len == 0 or @intFromPtr(p.ptr) % 4 != 0) return whole(ov, p);
    for (0..CW * CH) |k| {
        if (written[k] and (dirty[k] or !same(p, k))) redraw(ov, p, k);
    }
}

fn whole(ov: []u8, p: []const u8) void {
    screens.scaled(ov, pic);
    for (0..scr.H) |y| {
        const to = ov[(set.screen_y + y) * W + set.screen_x ..][0..scr.W];
        for (0..scr.W) |x| {
            const t = layer[y * scr.W + x];
            if (t != CLEAR and p[y * scr.W + x] == t) to[x] = t;
        }
    }
    if (shadow.len == 0) return;
    @memcpy(std.mem.sliceAsBytes(shadow), p);
    @memset(&dirty, false);
    painted = true;
}

/// The physic screen's 8 x 8 pixels of cell k, two words a line.
fn words(k: usize, j: usize) usize {
    return ((k / CW * 8 + j) * scr.W + k % CW * 8) / 4;
}

fn same(p: []const u8, k: usize) bool {
    const pw: [*]const u32 = @ptrCast(@alignCast(p.ptr));
    for (0..8) |j| {
        const w = words(k, j);
        if (pw[w] != shadow[w] or pw[w + 1] != shadow[w + 1]) return false;
    }
    return true;
}

/// Cell k from scratch: the scaled picture under it, the text over it.
fn redraw(ov: []u8, p: []const u8, k: usize) void {
    const pw: [*]const u32 = @ptrCast(@alignCast(p.ptr));
    const x0 = k % CW * 8;
    for (0..8) |j| {
        const y = k / CW * 8 + j;
        const from = pic[screens.src(set.screen_y + y - screens.Y0) * scr.W ..][0..scr.W];
        const to = ov[(set.screen_y + y) * W + set.screen_x + x0 ..][0..8];
        for (0..8) |i| {
            const t = layer[y * scr.W + x0 + i];
            to[i] = if (t != CLEAR and p[y * scr.W + x0 + i] == t) t else from[screens.src(set.screen_x + x0 + i)];
        }
        const w = words(k, j);
        shadow[w] = pw[w];
        shadow[w + 1] = pw[w + 1];
    }
    dirty[k] = false;
}
