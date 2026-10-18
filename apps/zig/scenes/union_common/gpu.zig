// --------------------------------------------------------------------------
// The Union carts' CHISEL helpers: the plane copies, keyed copies and fills the
// hub, BEAT DIS and TNT2 used to do with the CPU's per-pixel loops
// (zg.blit / clearFrameBuffer), as one blitter op each.
//
// Same pixels as the soft blit: the machine clips to the destination plane
// (stride x plane height) exactly as zg.blit.Dst.plane clipped to fb_w x fb_h,
// a `key` pixel is skipped, and ops run in program order. A zg.blit.Dst.window
// is not a machine feature, so putIn() crops the rectangle itself.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const LogicalFB = zg.LogicalFB;

/// A clip rectangle in plane pixels (zg.blit.Dst.window's x, y, w, h).
pub const Win = struct { x: i32, y: i32, w: i32, h: i32 };

var blitter: zg.Blitter = .{};

/// Call from the cart's init (the blitter needs the video region's base).
pub fn init() void {
    blitter.init();
}

/// Fill the w x h rectangle at (x, y) with `idx`.
pub fn fill(fb: *LogicalFB, x: i32, y: i32, w: i32, h: i32, idx: u8) void {
    blitter.fill(fb, @intCast(x), @intCast(y), @intCast(w), @intCast(h), idx);
}

/// Fill the whole plane.
pub fn clear(fb: *LogicalFB, idx: u8) void {
    blitter.clear(fb, idx);
}

/// `img` (or its `part`) with its top-left at (dx, dy); `key` pixels stay clear.
pub fn put(fb: *LogicalFB, img: blit.Image, part: ?blit.Rect, dx: i32, dy: i32, key: ?u8) void {
    const r = part orelse blit.Rect{ .x = 0, .y = 0, .w = img.w, .h = img.h };
    blitter.blitImage(fb, @intCast(dx), @intCast(dy), img.data, @intCast(img.w), @intCast(r.x), @intCast(r.y), @intCast(r.w), @intCast(r.h), key);
}

/// put() clipped to `win`, with (dx, dy) relative to the window's top-left.
pub fn putIn(fb: *LogicalFB, win: Win, img: blit.Image, part: ?blit.Rect, dx: i32, dy: i32, key: ?u8) void {
    const r = part orelse blit.Rect{ .x = 0, .y = 0, .w = img.w, .h = img.h };
    const x = win.x + dx;
    const y = win.y + dy;
    const x0 = @max(x, win.x);
    const y0 = @max(y, win.y);
    const x1 = @min(x + @as(i32, @intCast(r.w)), win.x + win.w);
    const y1 = @min(y + @as(i32, @intCast(r.h)), win.y + win.h);
    if (x1 <= x0 or y1 <= y0) return;
    const cut = blit.Rect{
        .x = r.x + @as(usize, @intCast(x0 - x)),
        .y = r.y + @as(usize, @intCast(y0 - y)),
        .w = @intCast(x1 - x0),
        .h = @intCast(y1 - y0),
    };
    put(fb, img, cut, x0, y0, key);
}

/// One keyed tile (colour 0 clear) from a sheet held as a raw slice: put()
/// without building an Image per tile.
pub fn putTile(fb: *LogicalFB, dx: i32, dy: i32, raw: []const u8, sheet_w: u16, sx: u16, sy: u16, w: u16, h: u16) void {
    blitter.blitImage(fb, @intCast(dx), @intCast(dy), raw, sheet_w, sx, sy, w, h, 0);
}
