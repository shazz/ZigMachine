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
const wave = zg.wave;
const A = @import("assets.zig");

pub const STRIP_ROWS = A.GLYPH_ROWS[1];
pub const MERGE_ROWS = 55; // new canvas(..., 110)

pub const Band = struct {
    w: usize,
    strips: [2][]u8, // the text canvas, halved at parity 0 and 1
    merge: []u8,

    pub fn bytes(w: usize) usize {
        return w * (2 * STRIP_ROWS + MERGE_ROWS);
    }

    /// `buf` must be bytes(w) long.
    pub fn init(buf: []u8, w: usize) Band {
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

    /// Clear the merge canvas, FX.siny the text into it with `sweep` (canvas y
    /// per canvas column), then recolour it with the gold backdrop, which sits
    /// in the raster canvas at goldY - 118, goldY, goldY + 118 (and repeats every
    /// 640 canvas columns: the intro draws it twice).
    pub fn compose(self: *Band, sweep: anytype, gold: blit.Image, gold_y: u32) void {
        @memset(self.merge, 0);
        const halves = [2]blit.Image{ blit.Image.init(self.strips[0], self.w), blit.Image.init(self.strips[1], self.w) };
        wave.sinyHalved(blit.Dst.buffer(self.merge, self.w), &halves, 0, sweep, null, .copy);
        const shift = gold_y / 2; // goldY is even: the texture stays on its 2x grid
        for (0..MERGE_ROWS) |row| {
            const tex = gold.data[((row + gold.h - shift) % gold.h) * gold.w ..][0..gold.w];
            const line = self.merge[row * self.w ..][0..self.w];
            var x: usize = 0;
            while (x < self.w) : (x += gold.w) {
                const n = @min(gold.w, self.w - x);
                for (line[x..][0..n], tex[0..n]) |*m, g| {
                    if (m.* != 0) m.* = A.textColour(g, m.*);
                }
            }
        }
    }

    /// mergecanvas.drawPart(main, x, y, 0, 0, w, 110, 1, 0, 1, scale) on a
    /// mid-handled canvas: left edge at `dx`, stretched about `centre_y`.
    pub fn draw(self: *const Band, dst: blit.Dst, dx: i32, centre_y: f64, scale: f64) void {
        blit.stretchY(dst, blit.Image.init(self.merge, self.w), dx, centre_y, scale, 0, .copy);
    }
};
