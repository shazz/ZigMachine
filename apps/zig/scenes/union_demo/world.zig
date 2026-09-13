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

pub const RASTER_ROWS: usize = 60; // ScrollingBackgroundLayer: 640x120 at the top (main.js:426-427)
pub const RASTER_STEP: u32 = 12; // pos.y += 12 per update (main.js:436)
pub const RASTER_WRAP: u32 = 2400; // doorrasters.png height

/// Fill one whole row with a colour (drawScanline cannot end on the right edge).
pub fn fillRow(fb: *LogicalFB, y: usize, idx: u8) void {
    const start = y * fb.stride;
    @memset(fb.fb[start .. start + fb.fb_w], idx);
}

/// doorrasters.png scrolled `pos_y` rows (640 space). Halved row i pairs the
/// image's rows (2i+1, 2i+2), so screen row k shows row k + pos_y/2 - 1.
pub fn drawRasters(fb: *LogicalFB, pos_y: u32) void {
    const base = pos_y / 2 + A.door_rows.len - 1;
    for (0..RASTER_ROWS) |k| fillRow(fb, k, A.door_rows[(k + base) % A.door_rows.len]);
}

/// plx_banner (repeat-x, ratio 0.5) with `scroll` its layer pos.x. banner.raw
/// pairs columns from 1, so image column c lands in halved column (c-1)/2.
pub fn drawBanner(fb: *LogicalFB, scroll: f32) void {
    const sx: i32 = @intFromFloat(@trunc(scroll));
    const off = @mod(@divFloor(sx - 1, 2), @as(i32, @intCast(A.banner.w)));
    const dst = blit.Dst.plane(fb);
    blit.blit(dst, A.banner, null, -off, 0, null, .copy);
    blit.blit(dst, A.banner, null, @as(i32, @intCast(A.banner.w)) - off, 0, null, .copy);
}

/// The Foreground layer with the viewport at `cam` (640 space): a tile at x
/// lands at ceil((x - cam) / 2) = x/2 - floor(cam/2). The street wraps, so a
/// view across the seam draws the map twice, one street-length apart.
pub fn drawForeground(fb: *LogicalFB, cam: i32) void {
    const span: i32 = @intCast(A.foreground.cols * A.tileset.tw);
    const sx = @mod(@divFloor(cam, 2), span);
    zg.tilemap.drawGrid(fb, &A.foreground, &A.tileset, sx, 0, 1, 0);
    if (sx + @as(i32, fb.fb_w) > span) zg.tilemap.drawGrid(fb, &A.foreground, &A.tileset, sx - span, 0, 1, 0);
}

/// Charly's current frame, mirrored when he faces left (flipX mirrors inside
/// the 80px frame, so frame i is slot 7-i of the mirrored sheet).
pub fn drawCharly(fb: *LogicalFB, c: *const Charly, cam: i32) void {
    const slot: usize = if (c.flip) 7 - c.frame else c.frame;
    const img = if (c.flip) A.charly_flip else A.charly;
    const part = blit.Rect{ .x = slot * A.CHARLY_W, .y = 0, .w = A.CHARLY_W, .h = A.CHARLY_H };
    const x: i32 = @intFromFloat(@trunc(c.x));
    const y: i32 = @intFromFloat(@trunc(c.y));
    blit.blit(blit.Dst.plane(fb), img, part, halfCeil(x - cam), halfCeil(y), 0, .copy);
}

/// Where a 640-space coordinate lands on the halved screen (see the header).
pub fn halfCeil(v: i32) i32 {
    return @divFloor(v + 1, 2);
}
