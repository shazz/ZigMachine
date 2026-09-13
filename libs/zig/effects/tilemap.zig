// --------------------------------------------------------------------------
// Tilemap — reusable scrolling tile layer (zigos library). A Layer draws a
// horizontal band of tiles from a TileSheet, indexed by a wide map, at a
// fractional tile scroll position. Palette-agnostic (copies indices; index
// `key` is transparent). CPU blit with edge clipping — no VRAM upload needed.
//
// Faithful to Codef efmain.js: pos in TILES, abs=floor(pos), frac scrolls the
// band by frac*tw pixels; map value v draws sheet tile (v - id_base), v < id_base
// is empty. The map is wider than the visible window and pre-wrapped (a tail of
// columns repeats the head) so `col + abs` never needs a modulo.
// --------------------------------------------------------------------------
const zsrc = @import("../zigos.zig");
const LogicalFB = zsrc.LogicalFB;

pub const TileSheet = struct {
    raw: []const u8, // sheet_w * (rows*th) indexed pixels
    sheet_w: u16, // sheet width in pixels
    tw: u16,
    th: u16,
    cols: u16, // tiles per sheet row
};

pub const Layer = struct {
    sheet: *const TileSheet,
    map: []const u8,
    map_w: usize, // columns per map row (incl. the wrap tail)
    rows: usize,
    id_base: u16 = 1, // map value v -> sheet tile (v - id_base); v < id_base = empty
    vis_cols: u16 = 25,
    dst_x: i16 = 8,
    dst_y: i16 = 0,
    key: u8 = 0, // transparent index

    pub fn draw(self: *const Layer, fb: *LogicalFB, pos_tiles: f32) void {
        const tw: i16 = @intCast(self.sheet.tw);
        const th: i16 = @intCast(self.sheet.th);
        const abs: usize = @intFromFloat(pos_tiles);
        const frac: f32 = pos_tiles - @floor(pos_tiles);
        const sub: i16 = @intFromFloat(frac * @as(f32, @floatFromInt(tw)));
        var r: usize = 0;
        while (r < self.rows) : (r += 1) {
            const base_y = self.dst_y + @as(i16, @intCast(r)) * th;
            var vc: usize = 0;
            while (vc < self.vis_cols) : (vc += 1) {
                const mv = self.map[r * self.map_w + vc + abs];
                if (mv < self.id_base) continue;
                const sx = self.dst_x + @as(i16, @intCast(vc)) * tw - sub;
                blitTile(self.sheet, fb, mv - self.id_base, sx, base_y, self.key);
            }
        }
    }
};

// --------------------------------------------------------------------------
// 2D maps. A Grid is a whole Tiled layer addressed in pixels, for screens
// where a camera roams a map and an entity collides with it (the Union Demo
// menu). The pure parts (cell query, camera follow, ratio scroll) live in
// tilegrid.zig so they test natively; drawing lives here.
// --------------------------------------------------------------------------
const tilegrid = @import("tilegrid.zig");
const blit = @import("blit.zig");
pub const Grid = tilegrid.Grid;
pub const followAxis = tilegrid.followAxis;
pub const deadzone = tilegrid.deadzone;
pub const RatioScroll = tilegrid.RatioScroll;

/// Draw a Grid of tile ids through `sheet`: cell v draws sheet tile v - id_base
/// (v < id_base is empty) and `key` pixels stay clear. The geometry is the
/// SHEET's tile size (the grid's own tw/th may be in other units, e.g. the
/// original map pixels); `cam_x` is the view's left edge in sheet pixels, rows
/// start at `dst_y`. Only the columns the plane can show are visited.
pub fn drawGrid(fb: *LogicalFB, grid: *const Grid, sheet: *const TileSheet, cam_x: i32, dst_y: i32, id_base: u8, key: u8) void {
    const tw: i32 = sheet.tw;
    const th: i32 = sheet.th;
    const cols: i32 = @intCast(grid.cols);
    const c0 = @max(@divFloor(cam_x, tw), 0);
    const c1 = @min(@divFloor(cam_x + @as(i32, fb.fb_w) - 1, tw), cols - 1);
    if (c1 < c0) return;
    const dst = blit.Dst.plane(fb);
    const img = blit.Image.init(sheet.raw, sheet.sheet_w);
    for (0..grid.rows) |r| {
        const dy = dst_y + @as(i32, @intCast(r)) * th;
        var c = c0;
        while (c <= c1) : (c += 1) {
            const v = grid.cells[r * grid.cols + @as(usize, @intCast(c))];
            if (v < id_base) continue;
            const tile: usize = v - id_base;
            const part = blit.Rect{ .x = (tile % sheet.cols) * sheet.tw, .y = (tile / sheet.cols) * sheet.th, .w = sheet.tw, .h = sheet.th };
            blit.blit(dst, img, part, c * tw - cam_x, dy, key, .copy);
        }
    }
}

// Blit one tile with left/right/top/bottom clipping; `key` pixels stay clear.
fn blitTile(sheet: *const TileSheet, fb: *LogicalFB, tile: u16, dx: i16, dy: i16, key: u8) void {
    const tw: i16 = @intCast(sheet.tw);
    const th: i16 = @intCast(sheet.th);
    const pw: i16 = @intCast(fb.fb_w);
    const ph: i16 = @intCast(fb.fb_h);
    const scol: usize = @as(usize, tile % sheet.cols) * sheet.tw;
    const srow: usize = @as(usize, tile / sheet.cols) * sheet.th;
    var ty: i16 = 0;
    while (ty < th) : (ty += 1) {
        const py = dy + ty;
        if (py < 0 or py >= ph) continue;
        const drow = @as(usize, @intCast(py)) * fb.stride;
        const srow_off = (srow + @as(usize, @intCast(ty))) * sheet.sheet_w + scol;
        var tx: i16 = 0;
        while (tx < tw) : (tx += 1) {
            const px = dx + tx;
            if (px < 0 or px >= pw) continue;
            const idx = sheet.raw[srow_off + @as(usize, @intCast(tx))];
            if (idx == key) continue;
            fb.fb[drow + @as(usize, @intCast(px))] = idx;
        }
    }
}
