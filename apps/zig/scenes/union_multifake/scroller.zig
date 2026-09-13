// --------------------------------------------------------------------------
// MULTIFAKE's swinging scroller: CODEF scrolltext_horizontal
// (codef_scrolltext.js:44-174) with one sinparam, drawn into a cleared 640x400
// canvas and composited 'source-in' with rasters.png (screen.js:127-132).
//
// source-in keeps only the rasters' colour where a glyph is opaque, so a glyph
// pixel takes the raster colour of its screen row: blit's `.row` ink.
//
// The ring stays in canvas pixels; drawing halves it. Letters are drawn
// left to right, and each takes the next phase (+0.6): the sine travels along
// the sorted letters, not along the ring.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const halve = @import("layers.zig").halve;

pub const TEXT = @embedFile("../../assets/screens/union_multifake/scrolltext.txt"); // screen.js:45, verbatim

const FIRST_CHAR = 32; // font.initTile(64,64,32)
const GLYPH_C: i32 = 64;
const GLYPH = 32; // halved
const SHEET_COLS = 16; // 1024 / 64
const LETTERS = 12; // wide = ceil(640/64)+1 = 11, letters 0..wide
const START_C: i32 = 11 * GLYPH_C;
const SPEED_C: i32 = 1; // scrolltext.init(scrollcanvas, font, 1, scrollparam)
const AMP: f64 = 120; // scrollparam (screen.js:30)
const INC: f64 = 0.6;
const OFFSET: f64 = -0.04;
const POSY_C: f64 = 240 - 16; // scrolltext.draw(240-16)

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + SHEET_COLS * 4) @compileError("scrolltext character outside font.png");
}

pub const Scroller = struct {
    ring: zg.scrollring.Ring(i32, LETTERS),
    phase: f64, // sinparam[0].myvalue
    first: f64, // the phase the leftmost letter takes this frame

    pub fn init(self: *Scroller) void {
        self.ring = zg.scrollring.Ring(i32, LETTERS).init(TEXT, START_C, GLYPH_C);
        self.phase = 0;
        self.first = 0;
    }

    /// The move and the phase bookkeeping of draw(): +inc per wrapped letter,
    /// then +offset for next frame.
    pub fn update(self: *Scroller) void {
        var old = self.phase;
        for (0..self.ring.stepCount(SPEED_C)) |_| old += INC;
        self.first = old;
        self.phase = old + OFFSET;
    }

    /// Glyphs are mid-handled: a letter at posx is drawn from posx - 32.
    pub fn draw(self: *const Scroller, dst: blit.Dst, font: blit.Image, rasters: []const u8) void {
        var order: [LETTERS]u8 = undefined;
        for (&order, 0..) |*o, i| o.* = @intCast(i);
        std.sort.insertion(u8, &order, &self.ring.x, lessX); // stable, as Array.sort
        var phase = self.first;
        for (order) |i| {
            const g: usize = self.ring.c[i] - FIRST_CHAR;
            const part = blit.Rect{ .x = g % SHEET_COLS * GLYPH, .y = g / SHEET_COLS * GLYPH, .w = GLYPH, .h = GLYPH };
            const x = @divFloor(self.ring.x[i] - GLYPH_C / 2, 2);
            const y = halve(@sin(phase) * AMP + POSY_C - GLYPH_C / 2);
            blit.blit(dst, font, part, x, y, 0, .{ .row = rasters });
            phase += INC;
        }
    }

    fn lessX(xs: *const [LETTERS]i32, a: u8, b: u8) bool {
        return xs[a] < xs[b];
    }
};
