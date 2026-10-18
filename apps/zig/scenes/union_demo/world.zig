// --------------------------------------------------------------------------
// The playfield, drawn in melonJS's z order (lowest first): the door-rasters
// band and plx_banner (both z 1, rasters first), the Foreground layer (z 2),
// then Charly. Nothing is cleared, as in the remake: these layers and the HUD
// cover all 200 rows every frame.
//
// Positions are the original's 640-space values, halved at the last moment by
// ONE rule for every layer: halved pixel k shows the original's EVEN column 2k.
// So something drawn at 640-space X lands at ceil(X / 2) (measured against the
// remake in Chrome: odd cameras and odd heights were a pixel off with a floor).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const Charly = @import("charly.zig").Charly;
const raster = @import("raster.zig");
const gpu = @import("../union_common/gpu.zig");

pub const RASTER_ROWS: usize = 60; // ScrollingBackgroundLayer: 640x120 at the top (main.js:426-427)
pub const RASTER_STEP: u32 = 12; // pos.y += 12 per update (main.js:436)
pub const RASTER_WRAP: u32 = 2400; // doorrasters.png height

// Every fill and copy below goes to CHISEL (~1 clock a pixel) instead of the
// CPU's per-pixel loops: the hub's frame is nearly all full-width bands and
// 16x8 tiles, which the soft blit paid ~10 cycles a pixel for. The machine
// clips to the plane (stride x 200), as the soft blit clipped to fb_w x fb_h.
pub const put = gpu.put;

/// Fill whole rows y0..y1 with a colour.
pub fn fillRows(fb: *LogicalFB, y0: usize, y1: usize, idx: u8) void {
    gpu.fill(fb, 0, @intCast(y0), @intCast(fb.fb_w), @intCast(y1 - y0), idx);
}

/// doorrasters.png scrolled `pos_y` rows (640 space). Halved row i pairs the
/// image's rows (2i+1, 2i+2), so screen row k shows row k + pos_y/2 - 1. Each
/// row is one colour, so the band is ONE ink whose register is rewritten on
/// each of its lines (raster.zig): `ink` gets this frame's colour per line.
pub fn drawRasters(fb: *LogicalFB, pos_y: u32, ink: *[zg.HEIGHT]u32) void {
    const base = pos_y / 2 + A.door_rows.len - 1;
    fillRows(fb, 0, RASTER_ROWS, raster.DOOR_INK);
    for (0..RASTER_ROWS) |k| {
        ink[k] = A.palette[A.door_rows[(k + base) % A.door_rows.len]].toRGBA();
    }
}

/// plx_banner (repeat-x, ratio 0.5) with `scroll` its layer pos.x. banner.raw
/// pairs columns from 1, so image column c lands in halved column (c-1)/2.
pub fn drawBanner(fb: *LogicalFB, scroll: f32) void {
    const sx: i32 = @intFromFloat(@trunc(scroll));
    const off = @mod(@divFloor(sx - 1, 2), @as(i32, @intCast(A.banner.w)));
    put(fb, A.banner, null, -off, 0, null);
    put(fb, A.banner, null, @as(i32, @intCast(A.banner.w)) - off, 0, null);
}

/// The Foreground layer with the viewport at `cam` (640 space): a tile at x
/// lands at ceil((x - cam) / 2) = x/2 - floor(cam/2). The street wraps, so a
/// view across the seam draws the map twice, one street-length apart.
pub fn drawForeground(fb: *LogicalFB, cam: i32) void {
    const span: i32 = @intCast(A.foreground.cols * A.tileset.tw);
    const sx = @mod(@divFloor(cam, 2), span);
    drawGrid(fb, sx);
    if (sx + @as(i32, fb.fb_w) > span) drawGrid(fb, sx - span);
}

// Tile id -> its origin in the sheet, filled once: the sheet's width in tiles
// is a run-time value, so `% cols` and `/ cols` were two software divides a tile
// (ZIGGY has no divider).
var tile_x: [256]u16 = undefined;
var tile_y: [256]u16 = undefined;
var tiles_for: ?*const u8 = null;

fn indexTiles() void {
    const t = A.tileset;
    for (0..256) |i| {
        tile_x[i] = @intCast((i % t.cols) * t.tw);
        tile_y[i] = @intCast((i / t.cols) * t.th);
    }
    tiles_for = &t.raw[0];
}

/// zg.tilemap.drawGrid(fb, foreground, tileset, cam_x, 0, 1, 0) on CHISEL: the
/// same visible columns, id_base 1, tile pixels 0 stay clear.
fn drawGrid(fb: *LogicalFB, cam_x: i32) void {
    if (tiles_for != &A.tileset.raw[0]) indexTiles();
    const g = &A.foreground;
    const t = &A.tileset;
    const tw: i32 = t.tw;
    const c0 = @max(@divFloor(cam_x, tw), 0);
    const c1 = @min(@divFloor(cam_x + @as(i32, fb.fb_w) - 1, tw), @as(i32, @intCast(g.cols)) - 1);
    if (c1 < c0) return;
    for (0..g.rows) |r| {
        const dy: i32 = @intCast(r * t.th);
        var c = c0;
        while (c <= c1) : (c += 1) {
            const v = g.cells[r * g.cols + @as(usize, @intCast(c))];
            if (v < 1) continue;
            gpu.putTile(fb, c * tw - cam_x, dy, t.raw, t.sheet_w, tile_x[v - 1], tile_y[v - 1], t.tw, t.th);
        }
    }
}

/// Charly's current frame, mirrored when he faces left (flipX mirrors inside
/// the 80px frame, so frame i is slot 7-i of the mirrored sheet).
pub fn drawCharly(fb: *LogicalFB, c: *const Charly, cam: i32) void {
    const slot: usize = if (c.flip) 7 - c.frame else c.frame;
    const img = if (c.flip) A.charly_flip else A.charly;
    const part = blit.Rect{ .x = slot * A.CHARLY_W, .y = 0, .w = A.CHARLY_W, .h = A.CHARLY_H };
    const x: i32 = @intFromFloat(@trunc(c.x));
    const y: i32 = @intFromFloat(@trunc(c.y));
    put(fb, img, part, halfCeil(x - cam), halfCeil(y), 0);
}

/// Where a 640-space coordinate lands on the halved screen (see the header).
pub fn halfCeil(v: i32) i32 {
    return @divFloor(v + 1, 2);
}
