// --------------------------------------------------------------------------
// Mandelbrot — the fractal channel from the original gh-page.
//
// It used to switch the machine to "truecolor" and write RGBA straight into the
// physical framebuffer. The sealed machine has no such mode (RES_TRUECOLOR is
// never read by machine/video.zig): the physical framebuffer is cleared and
// composited by the machine every frame, and a cart draws into its planes. So
// the same picture is drawn the ST way — one 400x280 overscan plane, palette
// index = escape-time iteration count, palette entry i = grey i (the original's
// Color{ i, i, i, i }). The fractal maths is untouched (libs/zig/effects/
// mandelbrot.zig); only where the pixels go changed.
//
// The image is static, but the old scene recomputed all 112,000 pixels (up to
// 255 iterations each) every frame. It is now computed once, ROWS_PER_FRAME rows
// a frame, so the picture draws itself in top to bottom over the first second
// or so and then costs nothing.
// --------------------------------------------------------------------------
const zg = @import("zigos");

const ZigOS = zg.ZigOS;
const Color = zg.Color;
const Mandelbrot = zg.Mandelbrot;

const PW: usize = zg.PHYSICAL_WIDTH;
const PH: usize = zg.PHYSICAL_HEIGHT;
const PLANE: usize = 0;
const ROWS_PER_FRAME: usize = 4;

pub const Demo = struct {
    next_row: usize,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // The Demo arrives as stale bytes on a re-entry from the menu: assign all.
        self.next_row = 0;

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all); // the fractal fills the whole 400x280 physical frame
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            const v: u8 = @intCast(i);
            fb.setPaletteEntry(v, Color{ .r = v, .g = v, .b = v, .a = v });
        }
        fb.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = self;
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        if (self.next_row >= PH) return;
        const screen = zigos.lfbs[PLANE].fb[0 .. PW * PH];
        const last = @min(PH, self.next_row + ROWS_PER_FRAME);
        var y = self.next_row;
        while (y < last) : (y += 1) {
            const row = screen[y * PW ..][0..PW];
            for (row, 0..) |*px, x| px.* = Mandelbrot.escapeTime(@intCast(x), @intCast(y));
        }
        self.next_row = last;
    }
};
