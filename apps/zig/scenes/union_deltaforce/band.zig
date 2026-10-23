// --------------------------------------------------------------------------
// A text band: the canvas chain both of DELTA FORCE's texts go through
// (screen.js:330-337, 353-432), at half resolution:
//
//   text canvas   32 rows: letters printed with font.drawTile, cleared first
//   merge canvas  110 rows: FX.siny of the text canvas, then the gold backdrop
//                 drawn 'source-atop', which keeps the letters' alpha and takes
//                 the gold texture's colour under each of them
//   main canvas   the merge canvas drawn mid-handled with a vertical scale
//
// The text canvas is kept halved twice (see wave.sinyHalved) as alpha levels;
// the merge canvas holds final palette indices, 0 where no letter landed.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const stretch = @import("../union_common/stretch.zig");
const sintab = @import("../union_common/sintab.zig");

pub const STRIP_ROWS = A.GLYPH_ROWS[1];
pub const MERGE_ROWS = 55; // new canvas(..., 110)

pub const Band = struct {
    w: usize,
    strips: [2][]u8, // the text canvas, halved at parity 0 and 1
    merge: []u8,
    text: ?usize = null, // which text the strips hold, for a caller that redraws it only on change

    pub fn bytes(w: usize) usize {
        return w * (2 * STRIP_ROWS + MERGE_ROWS);
    }

    /// `buf` must be bytes(w) long.
    pub fn init(buf: []u8, w: usize) Band {
        @memset(buf, 0); // once: the intro never clears its text canvas again (intro.zig)
        const s = w * STRIP_ROWS;
        return .{ .w = w, .strips = .{ buf[0..s], buf[s .. 2 * s] }, .merge = buf[2 * s ..][0 .. w * MERGE_ROWS] };
    }

    /// canvas.clear() of the text canvas.
    pub fn clear(self: *Band) void {
        for (self.strips) |s| @memset(s, 0);
    }

    /// font.drawTile(text canvas, ch - 32, canvas_x, 0). Letters sit 64 canvas
    /// pixels apart, so they never overlap and a plain copy is the composite.
    pub fn letter(self: *Band, font: *const [2]blit.Image, ch: u8, canvas_x: i32) void {
        for (self.strips, font, [2]u1{ 0, 1 }) |strip, sheet, parity| {
            const rect = A.glyph(ch, parity) orelse return;
            blit.blit(blit.Dst.buffer(strip, self.w), sheet, rect, @divFloor(canvas_x, 2), 0, null, .copy);
        }
    }

    /// Columns [c0, c1) of the merge canvas, the only ones `draw` will show: clear them,
    /// FX.siny the text into them with `sweep` (canvas y per canvas column, already at
    /// column c0: wave.sinyHalved's walk from there), then recolour them with the gold
    /// backdrop, which sits in the raster canvas at goldY - 118, goldY, goldY + 118 (and
    /// repeats every 640 canvas columns: the intro draws it twice). The columns outside
    /// are never read (the plane clips them), so they are left as they are.
    pub fn compose(self: *Band, sweep: anytype, gold: blit.Image, gold_y: u32, c0: usize, c1: usize) void {
        if (c1 <= c0) return;
        for (0..MERGE_ROWS) |row| @memset(self.merge[row * self.w ..][c0..c1], 0);
        const halves = [2]blit.Image{ blit.Image.init(self.strips[0], self.w), blit.Image.init(self.strips[1], self.w) };
        const dst = blit.Dst.buffer(self.merge, self.w);
        if (@TypeOf(sweep.*) == sintab.Flat) {
            // One y for every column: the 1-wide column copies are one copy of the whole span.
            const y = sweep.next();
            const half = halves[@intCast(y & 1)];
            blit.blit(dst, half, .{ .x = c0, .y = 0, .w = c1 - c0, .h = half.h }, @intCast(c0), @divFloor(y, 2), null, .copy);
        } else for (c0..c1) |i| {
            const y = sweep.next();
            _ = sweep.next(); // canvas column 2i+1: under the same ST column
            const half = halves[@intCast(y & 1)];
            blit.blit(dst, half, .{ .x = i, .y = 0, .w = 1, .h = half.h }, @intCast(i), @divFloor(y, 2), null, .copy);
        }
        const shift = gold_y / 2; // goldY is even: the texture stays on its 2x grid
        for (0..MERGE_ROWS) |row| {
            const tex = gold.data[((row + gold.h - shift) % gold.h) * gold.w ..][0..gold.w];
            const line = self.merge[row * self.w ..][0..self.w];
            var tx = c0 % gold.w; // the texture column under merge column x, walked (no divide a pixel)
            for (line[c0..c1]) |*m| {
                if (m.* != 0) m.* = A.textColour(tex[tx], m.*);
                tx += 1;
                if (tx == gold.w) tx = 0;
            }
        }
    }

    /// mergecanvas.drawPart(main, x, y, 0, 0, w, 110, 1, 0, 1, scale) on a
    /// mid-handled canvas: left edge at `dx`, stretched about `centre_y`.
    pub fn draw(self: *const Band, dst: blit.Dst, dx: i32, centre_q16: i32, scale: f64) void {
        stretch.stretchY(dst, blit.Image.init(self.merge, self.w), dx, centre_q16, scale, 0, .copy);
    }
};
