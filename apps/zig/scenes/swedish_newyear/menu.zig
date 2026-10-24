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
const assets = @import("assets.zig");
const texts = @import("texts.zig");
const image = @import("image.zig");
const sc = @import("scroller.zig");
const ram = @import("ram.zig");

const FONT_W: i32 = 95;
const FONT_H: i32 = 55;
const SCROLL_Y: i32 = 397;
const FONT_FIRST: u8 = 32;

pub const Menu = struct {
    scroll: sc.Scroller,

    pub fn init(self: *Menu) void {
        self.scroll.init(texts.menu, FONT_W, 640, 10); // init(mycanvas, font7, 10)
    }

    /// The picture is the same every frame and only physical rows PIC_END_ROW..
    /// change (the scroller and the blocks, ST lines 199..224), so a frame after
    /// the first (`full` false) clears and redraws just those rows.
    pub const FIRST_ROW: usize = @intCast(frame.OY + 199);
    pub const END_ROW: usize = @intCast(frame.OY + 225);
    /// ... and only the ST window's columns: nothing here draws outside x 0..319.
    pub const FIRST_COL: usize = @intCast(frame.OX);
    pub const END_COL: usize = @intCast(frame.OX + 320);

    pub fn step(self: *Menu, full: bool) void {
        if (full) {
            frame.clear();
            drawPicture(0, 200);
        } else {
            frame.clearRows(FIRST_ROW, END_ROW);
            drawPicture(199, 200); // the picture's last line shares ST line 199 with the scroller
        }
        self.scroll.advance();
        self.drawScroller();
        drawBlock(0);
        drawBlock(304); // 608 in the remake
    }

    fn drawPicture(y0: usize, y1: usize) void {
        for (y0..y1) |y| {
            const row = assets.main_px[y * 320 ..][0..320];
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
            const posx: i32 = self.scroll.posx[k];
            var y: i32 = 199;
            while (y < 225) : (y += 1) {
                const srow = @divFloor(nb, 10) * 27 + @divFloor(2 * y - SCROLL_Y - 1, 2);
                if (srow < 0 or srow >= FONT.h) continue;
                glyphRow(partx, posx, @intCast(srow), y);
            }
        }
    }

    // font7 is 4 bits a pixel (assets_gen.zig). Source column sx = partx + 2x - posx
    // steps by 2 with x, so a row reads one nibble of every byte, the same nibble
    // throughout: the byte index steps by 1 and the shift is fixed for the row.
    const FONT = gen.font7;
    comptime {
        if (FONT.bits != 4) @compileError("menu.zig: glyphRow reads font7 as 4 bits a pixel");
    }

    /// One glyph row of the scroller at ST line `y` (199..224), for x in 0..319:
    /// written straight into the picture (frame.put's clip never bites here).
    fn glyphRow(partx: i32, posx: i32, srow: usize, y: i32) void {
        const pitch: usize = (@as(usize, @intCast(FONT.w)) + 1) / 2;
        const data = assets.font7.data[srow * pitch ..][0..pitch];
        const lut = assets.font7.lut;
        const out = &ram.buf.px[@intCast(y + frame.OY)];
        var x: i32 = @max(0, @divFloor(posx + 1, 2)); // 2x - posx >= 0, so sx >= partx >= 0
        var sx: i32 = partx + 2 * x - posx;
        const shift: u3 = if (sx & 1 == 0) 0 else 4;
        var p: usize = @intCast(sx >> 1);
        while (x < 320 and sx - partx < 95 and sx < FONT.w) : ({
            x += 1;
            sx += 2;
            p += 1;
        }) {
            const i = (data[p] >> shift) & 0x0F;
            if (i != 0) out[@intCast(x + frame.OX)] = lut[i];
        }
    }

    fn drawBlock(x0: i32) void {
        for (0..25) |y| for (0..16) |x| {
            const g = assets.block.at(@intCast(x), @intCast(y));
            if (g != image.NONE) frame.put(x0 + @as(i32, @intCast(x)), 200 + @as(i32, @intCast(y)), g);
        };
    }
};
