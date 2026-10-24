// --------------------------------------------------------------------------
// REPS bands: what does not move, drawn ONCE (Matt: "only modify what needs to
// be modified"), and the moving parts on CHISEL.
//
// Only three plane bands ever change (union_reps.zig DYNAMIC_ROWS): the two
// scrollers' rows and the rows of the mask and the sprites. What a frame used
// to redraw there from scratch is fixed except the letters and the sprites:
//
//   still     colour 0, overlay.png, the mask in MASK_INK (its shape never moves,
//             only that ink's register does), theunion.png over both scrollers'
//             rows. One 320x200 picture in cart RAM; a frame copies a band of
//             it back onto the plane, ONE CHISEL copy a band (cart RAM -> plane,
//             no in-plane copy), and draws the sprites and the letters on it.
//   letters   the font pre-inked red and blue, so a letter is a keyed CHISEL
//             copy, not a CPU flat-ink loop (scroller.zig).
//   union     theunion.png over the letters, as before: its OPAQUE pixels are
//             one keyed CHISEL copy a band (where no letter is, they already
//             hold that value), and its SOFT pixels (1,379 a band) are a list
//             with the value each takes over the band's ink. A soft pixel under
//             a letter's ink gets it; one that is not keeps the still picture's
//             blend over the overlay. "Under the ink" is read from the FONT, not
//             from the plane: no CPU read of a row the blitter just wrote.
//
// Byte for byte the old frame (restore, letters in flat ink, drawUnion over
// them): a pixel no letter inks is the still picture's, drawUnion over the
// overlay; a pixel a letter inks is drawUnion over the ink.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const layers = @import("layers.zig");
const scroller = @import("scroller.zig");

const UNION_TOP_Y = 0; // scrollOverlay.draw(maincanvas, 0, 0)
const UNION_BOTTOM_Y = 156; // scrollOverlay.draw(maincanvas, 0, 312)
const BAND_H = scroller.GLYPH;

/// A soft union pixel in a scroller band: column, band row, its value over the ink.
const Soft = struct { x: u16, r: u16, v: u8 };

/// One scroller band: its first plane row, the union's row there, its soft pixels.
const Band = struct {
    y: usize,
    union_row: usize,
    soft: []const Soft,

    fn build(theunion: blit.Image, y: usize, ink: u8) ?Band {
        const y0: usize = if (y >= UNION_BOTTOM_Y) UNION_BOTTOM_Y else UNION_TOP_Y;
        if (y < y0 or y - y0 + BAND_H > theunion.h) return null; // the union covers the band
        const rows = theunion.data[(y - y0) * A.W ..][0 .. BAND_H * A.W];
        var n: usize = 0;
        for (rows) |s| n += @intFromBool(isSoft(s));
        const soft = zg.mem.alloc(Soft, n) orelse return null;
        var k: usize = 0;
        for (rows, 0..) |s, i| if (isSoft(s)) {
            soft[k] = .{ .x = @intCast(i % A.W), .r = @intCast(i / A.W), .v = layers.unionOver(s, ink) };
            k += 1;
        };
        return .{ .y = y, .union_row = y - y0, .soft = soft };
    }
};

fn isSoft(s: u8) bool {
    return s >= A.BLEND_BASE and s < A.BLEND_END;
}

pub const Bands = struct {
    still: blit.Image, // the plane as it is with no letter and no sprite on it
    red_font: blit.Image, // the font, its ink RED_INK
    blue_font: blit.Image,
    opaque_union: blit.Image, // theunion.png without its soft pixels
    red: Band,
    blue: Band,

    /// All of it on zg.mem, from the depacked images, once.
    pub fn build(img: *const A.Images) ?Bands {
        const still = zg.mem.alloc(u8, A.W * A.OVERLAY_H) orelse return null;
        const dst = blit.Dst.buffer(still, A.W);
        @memset(still, 0); // colour 0 under the picture
        blit.blit(dst, img.overlay, null, 0, 0, 0, .copy);
        blit.blit(dst, img.mask, null, 0, layers.Rasters.Y, 0, .{ .flat = A.MASK_INK });
        layers.drawUnion(dst, img.theunion, UNION_TOP_Y);
        layers.drawUnion(dst, img.theunion, UNION_BOTTOM_Y);
        const op = zg.mem.alloc(u8, img.theunion.data.len) orelse return null;
        for (img.theunion.data, op) |s, *d| d.* = if (isSoft(s)) 0 else s;
        return .{
            .still = blit.Image.init(still, A.W),
            .red_font = inked(img.font, A.RED_INK) orelse return null,
            .blue_font = inked(img.font, A.BLUE_INK) orelse return null,
            .opaque_union = blit.Image.init(op, A.W),
            .red = Band.build(img.theunion, scroller.RED_Y, A.RED_INK) orelse return null,
            .blue = Band.build(img.theunion, scroller.BLUE_Y, A.BLUE_INK) orelse return null,
        };
    }

    /// The still picture's rows a..b back onto the plane: one copy from cart RAM.
    pub fn restore(self: *const Bands, dst: blit.Dst, a: usize, b: usize) void {
        blit.blit(dst, self.still, .{ .x = 0, .y = a, .w = A.W, .h = b - a }, 0, @intCast(a), null, .copy);
    }

    /// The letters, then the union over them, in both bands.
    pub fn letters(self: *const Bands, dst: blit.Dst, s: *const scroller.Scroller) void {
        s.draw(dst, self.red_font, self.blue_font);
        var cols: [A.W]u32 = undefined;
        s.columns(&cols);
        self.unionOver(dst, self.red, &cols);
        self.unionOver(dst, self.blue, &cols);
    }

    fn unionOver(self: *const Bands, dst: blit.Dst, band: Band, cols: *const [A.W]u32) void {
        const part = blit.Rect{ .x = 0, .y = band.union_row, .w = A.W, .h = BAND_H };
        blit.blit(dst, self.opaque_union, part, 0, @intCast(band.y), 0, .copy);
        const font = self.red_font.data; // either font: the same shape
        for (band.soft) |e| {
            const at = cols[e.x];
            if (at == scroller.NO_LETTER or font[at + @as(usize, e.r) * A.FONT_W] == 0) continue;
            dst.buf[(band.y + e.r) * dst.stride + e.x] = e.v;
        }
    }
};

/// The 0/1 font with its ones in `ink`.
fn inked(font: blit.Image, ink: u8) ?blit.Image {
    const out = zg.mem.alloc(u8, font.data.len) orelse return null;
    for (font.data, out) |p, *d| d.* = if (p != 0) ink else 0;
    return blit.Image.init(out, font.w);
}
