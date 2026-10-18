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

/// What the plane holds, so a frame whose camera and parallax stand still
/// redraws only under the griffin (every store is a blocking bus write on the
/// board; the 384x240 background and tiles used to be rewritten whole).
pub const Cache = struct {
    valid: bool = false,
    cx: i32 = 0,
    cy: i32 = 0,
    off: i32 = 0,
    box: Box = .{},
};

/// A canvas rectangle, half-open.
const Box = struct { x0: i32 = 0, y0: i32 = 0, x1: i32 = 0, y1: i32 = 0 };

/// One frame: background, Foreground, griffin. The bars are the plane's black
/// from clearFrameBuffer(BLACK) and nothing draws on them: the background keeps
/// to rows TOP_BAR..LOW_BAR, the Foreground to TOP_BAR..VIEW_H, the griffin is
/// clipped to TOP_BAR..LOW_BAR (the bars used to be drawn over it).
pub fn frame(fb: *LogicalFB, view: *const View, offset: i32, g: *const Griffin, c: *Cache) void {
    const cx: i32 = @intFromFloat(@divFloor(view.x, 2));
    const cy: i32 = @as(i32, @intFromFloat(@divFloor(view.y, 2))) + TOP_BAR;
    if (c.valid and c.cx == cx and c.cy == cy and c.off == offset) {
        restore(fb, cx, cy, offset, c.box);
    } else {
        background(fb, offset);
        foregroundIn(blit.Dst.plane(fb).window(OX, OY + TOP_BAR, CANVAS_W, VIEW_H - TOP_BAR), cx, cy);
        c.* = .{ .valid = true, .cx = cx, .cy = cy, .off = offset };
    }
    c.box = griffin(fb, g, view);
}

/// The layers back over the rectangle the griffin was drawn in.
fn restore(fb: *LogicalFB, cx: i32, cy: i32, offset: i32, b: Box) void {
    if (b.x1 <= b.x0 or b.y1 <= b.y0) return;
    const off: usize = @intCast(@divFloor(offset, 2));
    const x0: usize = @intCast(b.x0);
    const w: usize = @intCast(b.x1 - b.x0);
    for (@as(usize, @intCast(b.y0))..@as(usize, @intCast(b.y1))) |y| {
        @memcpy(fb.fb[(OY + y) * fb.stride + OX + x0 ..][0..w], A.back_rows[y * A.BACK_ROW + off + x0 ..][0..w]);
    }
    const fy1 = @min(b.y1, VIEW_H);
    if (fy1 <= b.y0) return;
    const win = blit.Dst.plane(fb).window(OX + x0, OY + @as(usize, @intCast(b.y0)), w, @intCast(fy1 - b.y0));
    foregroundIn(win, cx + b.x0, cy + b.y0 - TOP_BAR);
}

/// The Foreground layer into `dst`, whose top-left shows map pixel (cx, cy).
fn foregroundIn(dst: blit.Dst, cx: i32, cy: i32) void {
    const t: i32 = @intCast(A.TILE);
    const c0 = firstTile(cx);
    const r0 = firstTile(cy);
    const c1 = @min(tilesTo(cx, dst.w), A.map.COLS);
    const r1 = @min(tilesTo(cy, dst.h), A.map.DATA_ROWS);
    for (r0..r1) |r| {
        for (c0..c1) |c| {
            const gid = A.foreground[r * A.map.COLS + c];
            if (gid == 0) continue;
            const tile: usize = gid - 1;
            const part = blit.Rect{ .x = (tile % A.SHEET_COLS) * A.TILE, .y = (tile / A.SHEET_COLS) * A.TILE, .w = A.TILE, .h = A.TILE };
            // A tile with no transparent texel is the same drawn unkeyed: row copies
            // (word stores) instead of a test and a byte store per pixel.
            const key: ?u8 = if (OPAQUE[tile]) null else 0;
            blit.blit(dst, A.tileset, part, @as(i32, @intCast(c)) * t - cx, @as(i32, @intCast(r)) * t - cy, key, .copy);
        }
    }
}

/// OPAQUE[t]: tileset tile t has no index-0 (transparent) texel. Built at compile
/// time from tileset.raw; 68 of its 160 tiles, 55% of the foreground's placements.
const OPAQUE: [A.tileset.h / A.TILE * A.SHEET_COLS]bool = blk: {
    @setEvalBranchQuota(4 * A.tileset.data.len);
    var o: [A.tileset.h / A.TILE * A.SHEET_COLS]bool = undefined;
    for (&o, 0..) |*f, tile| {
        const x0 = (tile % A.SHEET_COLS) * A.TILE;
        const y0 = (tile / A.SHEET_COLS) * A.TILE;
        f.* = true;
        for (0..A.TILE) |y| {
            for (A.tileset.data[(y0 + y) * A.tileset.w + x0 ..][0..A.TILE]) |p| {
                if (p == 0) f.* = false;
            }
        }
    }
    break :blk o;
};

/// The griffin's frame at ~~(pos - view), clipped to the canvas between the
/// bars; returns the rectangle it covers.
fn griffin(fb: *LogicalFB, g: *const Griffin, view: *const View) Box {
    const dst = blit.Dst.plane(fb).window(OX, OY + TOP_BAR, CANVAS_W, LOW_BAR - TOP_BAR);
    const s: usize = g.sprite();
    const part = blit.Rect{ .x = (s % 4) * A.FRAME, .y = (s / 4) * A.FRAME, .w = A.FRAME, .h = A.FRAME };
    // Past the floor's end (column 663) nothing stops a fall, so y has no
    // bound: clamp before the cast, which is not checked in ReleaseSmall.
    const sx: i32 = @intFromFloat(@trunc(std.math.clamp(g.x - view.x, -OFF_CANVAS, OFF_CANVAS)));
    const sy: i32 = @intFromFloat(@trunc(std.math.clamp(g.y - view.y, -OFF_CANVAS, OFF_CANVAS)));
    const hx = halfCeil(sx);
    const hy = halfCeil(sy);
    blit.blit(dst, if (g.flip) A.griffin_flip else A.griffin, part, hx, hy - TOP_BAR, 0, .copy);
    const f: i32 = @intCast(A.FRAME);
    return .{ .x0 = @max(hx, 0), .y0 = @max(hy, TOP_BAR), .x1 = @min(hx + f, CANVAS_W), .y1 = @min(hy + f, LOW_BAR) };
}

/// The tile under screen pixel `at` (the view's edge), or 0 above/left of the map.
fn firstTile(at: i32) usize {
    return @intCast(@max(@divFloor(at, @as(i32, @intCast(A.TILE))), 0));
}

/// One past the last tile a `len`-pixel span from `at` touches, ceil((at + len)
/// / TILE). The usual floor((at + len - 1) / TILE) + 1 casts -1 to usize, which
/// ReleaseSmall does not check, when an empty span starts at 0.
fn tilesTo(at: i32, len: usize) usize {
    const end: i32 = at + @as(i32, @intCast(len)) + @as(i32, @intCast(A.TILE)) - 1;
    return @intCast(@max(@divFloor(end, @as(i32, @intCast(A.TILE))), 0));
}

/// Where a canvas coordinate lands on the halved screen (see the header).
fn halfCeil(v: i32) i32 {
    return @divFloor(v + 1, 2);
}
