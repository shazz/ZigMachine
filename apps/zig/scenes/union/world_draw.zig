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

/// The tile world at `pos_tiles` (clouds, animated rows and world in one pass).
pub fn world(fb: *LogicalFB, pos_tiles: f32) void {
    const abs: usize = @intFromFloat(pos_tiles);
    const frac: f32 = pos_tiles - @floor(pos_tiles);
    const sub: i16 = @intFromFloat(frac * 16.0);
    for (0..cells.ROWS) |r| {
        const y: i32 = cells.TOP + @as(i32, @intCast(r)) * 16;
        for (0..VIS_COLS) |vc| {
            const id = cells.idAt(r, vc + abs);
            if (id == cells.NONE) continue;
            const x: i32 = DST_X + @as(i32, @intCast(vc)) * 16 - sub;
            gpu.putTile(fb, x, y, &cells.sheet, 16, 0, @as(u16, id) * 16, 16, 16);
        }
    }
}
