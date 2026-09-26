// whichpart 0 -- the MAIN MENU (screen.js do_menu):
//   main.draw(mycanvas, 0, 0)                 the picture, 272 colours, <= 37 a line
//   menuscrolltext.draw(397)                  font7 95x55, speed 10, 9 letters
//   block.draw(mycanvas, 0, 400) and (608, 400)
// The scroller sits at 640-rows 397..449, i.e. ST lines 199..224: IN THE BOTTOM
// BORDER ("IF YOU READ THIS TEN TIMES WE WILL TELL YOU HOW TO REMOVE ALL OF THE
// BORDERS"), which this part opens. main.png is a per-line-palette picture:
// frame.zig's line palette carries its colours, as a Spectrum-512 picture's HBL does.
const frame = @import("frame.zig");
const gen = @import("assets_gen.zig");
const texts = @import("texts.zig");
const image = @import("image.zig");
const sc = @import("scroller.zig");

const FONT_W: f64 = 95;
const FONT_H: i32 = 55;
const SCROLL_Y: i32 = 397;
const FONT_FIRST: u8 = 32;

pub const Menu = struct {
    scroll: sc.Scroller,

    pub fn init(self: *Menu) void {
        self.scroll.init(texts.menu, FONT_W, 640, 10, null); // init(mycanvas, font7, 10)
    }

    pub fn step(self: *Menu) void {
        drawPicture();
        self.scroll.advance();
        self.drawScroller();
        drawBlock(0);
        drawBlock(304); // 608 in the remake
    }

    fn drawPicture() void {
        for (0..200) |y| {
            const row = gen.main_px[y * 320 ..][0..320];
            for (row, 0..) |i, x| frame.put(@intCast(x), @intCast(y), gen.main_lut[y][i]);
        }
    }

    /// A glyph pixel at ST (X, Y) is 640-space (2X, 2Y): cell row 2Y-397 (odd:
    /// font7 keeps only those), cell column 2X - posx.
    fn drawScroller(self: *Menu) void {
        var ord: [sc.MAX]u8 = undefined;
        for (self.scroll.order(&ord)) |k| {
            const nb: i32 = @as(i32, self.scroll.ltr[k]) - FONT_FIRST;
            const party = @divFloor(nb, 10) * FONT_H;
            if (party + FONT_H > 330) continue; // CODEF: parth <= 0, nothing drawn
            const partx = @mod(nb, 10) * 95;
            const posx: i32 = @intFromFloat(self.scroll.posx[k]);
            var y: i32 = 199;
            while (y < 225) : (y += 1) {
                const srow = @divFloor(nb, 10) * 27 + @divFloor(2 * y - SCROLL_Y - 1, 2);
                var x: i32 = @max(0, @divFloor(posx + 1, 2));
                while (x < 320 and 2 * x - posx < 95) : (x += 1) {
                    const g = gen.font7.at(partx + 2 * x - posx, srow);
                    if (g != image.NONE) frame.put(x, y, g);
                }
            }
        }
    }

    fn drawBlock(x0: i32) void {
        for (0..25) |y| for (0..16) |x| {
            const g = gen.block.at(@intCast(x), @intCast(y));
            if (g != image.NONE) frame.put(x0 + @as(i32, @intCast(x)), 200 + @as(i32, @intCast(y)), g);
        };
    }
};
