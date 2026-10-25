// --------------------------------------------------------------------------
// Union main -- the scrolling background on plane 0, drawn by CHISEL.
//
// Both halves used to be CPU row copies (parallax strips, 16x16 tiles through
// blit_rows). On the board a CPU store to the plane is a blocking DDR write,
// so the 5 parallax strips and ~390 tiles cost over a megacycle; a CHISEL
// copy reads the strip from cart RAM and writes the plane itself.
// Same pixels as zg.parallax.drawLayer and tilemap.Layer.draw: the strip wraps
// every `w` px (a few contiguous runs), a transparent layer skips colour 0, and
// the tiles are the pre-composited cells of world_cells.zig, 0 transparent.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const gpu = @import("../union_common/gpu.zig");
const cells = @import("world_cells.zig");
const ring = @import("world_ring.zig"); // map rows 3..7: one opaque copy out of a ring

const DST_X: i16 = 8; // tilemap.Layer.dst_x
const VIS_COLS: usize = 25;

/// Every layer of `px` across the first `dst_w` columns of `fb`.
pub fn parallax(px: anytype, fb: *LogicalFB, dst_w: u16) void {
    const cols: usize = @min(@as(usize, dst_w), @as(usize, fb.fb_w));
    for (&px.layers) |*l| {
        const w: usize = l.w;
        const key: ?u8 = if (l.transparent) 0 else null;
        const img = zg.blit.Image.init(l.raw, w);
        var srcx: usize = @as(usize, @intFromFloat(l.pos)) % w;
        var done: usize = 0;
        while (done < cols) {
            const len = @min(cols - done, w - srcx);
            gpu.put(fb, img, .{ .x = srcx, .y = 0, .w = len, .h = l.h }, @intCast(done), l.y, key);
            done += len;
            srcx = 0;
        }
    }
}

/// The columns [x0, x1) of the plane a map row's cells were drawn in (none when x1 <= x0).
pub const Span = struct { x0: i32 = 0, x1: i32 = 0 };
/// The last map row: it lies on main.zig's floor band.
pub const FLOOR_ROW: usize = cells.ROWS - 1;

/// The tile world at `pos_tiles` (clouds, animated rows and world in one pass). Map rows
/// ring.ROW0..ring.ROW1 come from `rows`, which also stands for their erase to 0. Returns
/// where FLOOR_ROW's cells went, the only pixels of the floor band anything draws over.
pub fn world(fb: *LogicalFB, pos_tiles: f32, rows: *ring.Ring) Span {
    const abs: usize = @intFromFloat(pos_tiles);
    const frac: f32 = pos_tiles - @floor(pos_tiles);
    const sub: i16 = @intFromFloat(frac * 16.0);
    rows.draw(fb, abs, @intCast(sub));
    var floor = Span{ .x0 = @intCast(fb.fb_w), .x1 = 0 };
    for (0..cells.ROWS) |r| {
        if (r >= ring.ROW0 and r < ring.ROW1) continue;
        const y: i32 = cells.TOP + @as(i32, @intCast(r)) * 16;
        for (0..VIS_COLS) |vc| {
            const id = cells.idAt(r, vc + abs);
            if (id == cells.NONE) continue;
            const x: i32 = DST_X + @as(i32, @intCast(vc)) * 16 - sub;
            gpu.putTile(fb, x, y, &cells.sheet, 16, 0, @as(u16, id) * 16, 16, 16);
            if (r == FLOOR_ROW) floor = .{ .x0 = @min(floor.x0, @max(x, 0)), .x1 = @max(floor.x1, @min(x + 16, @as(i32, @intCast(fb.fb_w)))) };
        }
    }
    return floor;
}
