// --------------------------------------------------------------------------
// One frame, in melonJS's z order: parallax_background (z 1), Foreground (z 2),
// the griffin (z 6), then the CODEF OverlayObject (z 999), whose two black
// fillRects cover canvas rows 0..13 and 494..539.
//
// The remake's canvas is 768x540 (me.video.init) holding a 768x480 viewport
// at its top: the tile layer is drawn only inside that viewport, while the
// parallax image (512 rows) and the sprite are drawn on the canvas, so rows
// 480..493 show the background with no tiles over it. Halved, the canvas is
// 384x270, placed at (8, 5) in the 400x280 overscan plane exactly as the
// Parallax Distorter's (ulm_spoon_distorter.zig); everything outside it is black.
//
// Halving follows the art's 2x grid: halved pixel k shows the canvas's EVEN
// column 2k. So the map lands at -floor(view / 2), the parallax image at
// -floor(offset / 2), and the sprite, drawn at ~~(pos - view), at ceil of half.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const Griffin = @import("griffin.zig").Griffin;
const View = @import("view.zig").View;

pub const OX: usize = 8;
pub const OY: usize = 5;
pub const CANVAS_W: usize = 384;
pub const CANVAS_H: usize = 270;
pub const VIEW_H: usize = 240; // the 480-row viewport
pub const TOP_BAR: usize = 7; // fillRect(0, 0, 768, 14)
pub const LOW_BAR: usize = 247; // fillRect(0, 494, 768, 540)
const OFF_CANVAS: f64 = 4096; // canvas px: any sprite this far off is clipped whole

/// The background rows no bar covers, black at the canvas's sides. back.png
/// is 256 rows (512 canvas rows): every row up to the low bar has one.
pub fn background(fb: *LogicalFB, offset: i32) void {
    const off: usize = @intCast(@divFloor(offset, 2));
    for (TOP_BAR..LOW_BAR) |y| {
        const row = fb.fb[(OY + y) * fb.stride ..][0..fb.fb_w];
        @memset(row[0..OX], A.BLACK);
        @memcpy(row[OX..][0..CANVAS_W], A.back_rows[y * A.BACK_ROW + off ..][0..CANVAS_W]);
        @memset(row[OX + CANVAS_W ..], A.BLACK);
    }
}

/// The Foreground layer through the viewport, in its visible rows only.
pub fn foreground(fb: *LogicalFB, view: *const View) void {
    const dst = blit.Dst.plane(fb).window(OX, OY + TOP_BAR, CANVAS_W, VIEW_H - TOP_BAR);
    const cx: i32 = @intFromFloat(@divFloor(view.x, 2));
    const cy: i32 = @as(i32, @intFromFloat(@divFloor(view.y, 2))) + TOP_BAR;
    const t: i32 = @intCast(A.TILE);
    const c0: usize = @intCast(@max(@divFloor(cx, t), 0));
    const r0: usize = @intCast(@max(@divFloor(cy, t), 0));
    const c1: usize = @min(@as(usize, @intCast(@divFloor(cx + @as(i32, @intCast(dst.w)) - 1, t))) + 1, A.map.COLS);
    const r1: usize = @min(@as(usize, @intCast(@divFloor(cy + @as(i32, @intCast(dst.h)) - 1, t))) + 1, A.map.DATA_ROWS);
    for (r0..r1) |r| {
        for (c0..c1) |c| {
            const gid = A.foreground[r * A.map.COLS + c];
            if (gid == 0) continue;
            const tile: usize = gid - 1;
            const part = blit.Rect{ .x = (tile % A.SHEET_COLS) * A.TILE, .y = (tile / A.SHEET_COLS) * A.TILE, .w = A.TILE, .h = A.TILE };
            blit.blit(dst, A.tileset, part, @as(i32, @intCast(c)) * t - cx, @as(i32, @intCast(r)) * t - cy, 0, .copy);
        }
    }
}

/// The griffin's frame at ~~(pos - view), anywhere on the canvas.
pub fn griffin(fb: *LogicalFB, g: *const Griffin, view: *const View) void {
    const dst = blit.Dst.plane(fb).window(OX, OY, CANVAS_W, CANVAS_H);
    const s: usize = g.sprite();
    const part = blit.Rect{ .x = (s % 4) * A.FRAME, .y = (s / 4) * A.FRAME, .w = A.FRAME, .h = A.FRAME };
    // Past the floor's end (column 663) nothing stops a fall, so y has no
    // bound: clamp before the cast, which is not checked in ReleaseSmall.
    const sx: i32 = @intFromFloat(@trunc(std.math.clamp(g.x - view.x, -OFF_CANVAS, OFF_CANVAS)));
    const sy: i32 = @intFromFloat(@trunc(std.math.clamp(g.y - view.y, -OFF_CANVAS, OFF_CANVAS)));
    blit.blit(dst, if (g.flip) A.griffin_flip else A.griffin, part, halfCeil(sx), halfCeil(sy), 0, .copy);
}

/// The overlay's bars and the plane outside the canvas.
pub fn bars(fb: *LogicalFB) void {
    @memset(fb.fb[0 .. (OY + TOP_BAR) * fb.stride], A.BLACK);
    @memset(fb.fb[(OY + LOW_BAR) * fb.stride .. @as(usize, fb.fb_h) * fb.stride], A.BLACK); // u16 * u16 overflows
}

/// Where a canvas coordinate lands on the halved screen (see the header).
fn halfCeil(v: i32) i32 {
    return @divFloor(v + 1, 2);
}
