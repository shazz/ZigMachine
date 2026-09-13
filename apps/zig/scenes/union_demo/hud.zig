// --------------------------------------------------------------------------
// The HUD (main.js TopBannerObject + BottomBannerObject): the UNION DEMO logo,
// the scroll-rasters band and the big scroller.
//
// The scroller is CODEF scrolltext_horizontal drawn twice into a 640x34
// merge canvas: fontsTexIn, then 'source-in' with the panorama strip, then
// fontsTexOut2 over it. fontsTexOut2 is an opaque field with transparent glyph
// HOLES, and fontsTexIn's ink is exactly those holes (checked by the asset
// script), so once the canvas is full the composite is simply: the field, and
// the panorama inside the holes. The strip is 32 rows on a 34-row canvas, so a
// hole's last halved row stays transparent and the rasters show through.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const world = @import("world.zig");

const LOGO_X: i32 = 194 / 2; // me.SpriteObject(194, 0) (main.js:414)
const RASTERS_Y: usize = 318 / 2; // scrollrasters drawn at y 318 (main.js:499)
const SCROLL_Y: i32 = 344 / 2; // merge canvas drawn at y 344 (main.js:508)
const SPEED: i32 = 5; // scrolltext init speed 5 (main.js:467)
const PANO_STEP: f32 = -2.5; // updateItemValue("scroller", -2.5) (main.js:553)
const PANO_WRAP: f32 = -832; // posScroller <= -832 -> 0 (main.js:486)
const FONT_W: i32 = 64; // initTile(32*2, 17*2, 32)
const FIRST_CHAR: u8 = 32;
const GLYPHS_PER_ROW: usize = 10; // 640 / 64
const WIDE: usize = 11; // ceil(640 / 64) + 1; letters 0..WIDE

const Letter = struct { posx: i32, ltr: u8 };

pub const Hud = struct {
    letters: [WIDE + 1]Letter,
    offset: usize, // scroffset: the next character to enter
    pano: f32, // posScroller

    pub fn init(self: *Hud) void {
        self.offset = 0; // jsApp.mainscrollerPos starts at 0
        for (&self.letters, 0..) |*l, i| {
            l.posx = @as(i32, WIDE) * FONT_W + @as(i32, @intCast(i)) * FONT_W;
            l.ltr = A.scrolltext[self.offset];
            self.offset += 1;
        }
        self.pano = 0;
    }

    /// BottomBannerObject.update, then the letter walk scrolltext.draw does.
    pub fn update(self: *Hud) void {
        self.pano += PANO_STEP;
        if (self.pano <= PANO_WRAP) self.pano = 0;
        for (&self.letters) |*l| {
            l.posx -= SPEED;
            if (l.posx > -FONT_W) continue;
            l.posx = @as(i32, WIDE) * FONT_W + (l.posx + FONT_W);
            l.ltr = A.scrolltext[self.offset];
            self.offset += 1;
            if (self.offset > A.scrolltext.len - 1) self.offset = 0;
        }
    }

    pub fn draw(self: *const Hud, fb: *LogicalFB) void {
        world.fillRow(fb, RASTERS_Y, A.colors.BLACK); // scrollrasters rows 0-1
        for (RASTERS_Y + 1..fb.fb_h) |y| world.fillRow(fb, y, A.scroll_rows[y - RASTERS_Y - 1]);
        const dst = blit.Dst.plane(fb);
        const pano = blit.Pattern{ .img = A.panorama, .ox = @intFromFloat(@ceil(self.pano / 2)), .oy = SCROLL_Y };
        for (self.letters) |l| {
            const nb: usize = l.ltr - FIRST_CHAR;
            const part = blit.Rect{
                .x = (nb % GLYPHS_PER_ROW) * A.GLYPH_W,
                .y = (nb / GLYPHS_PER_ROW) * A.GLYPH_H,
                .w = A.GLYPH_W,
                .h = A.GLYPH_H,
            };
            const x = world.halfCeil(l.posx);
            blit.blit(dst, A.font, part, x, SCROLL_Y, 0, .copy); // the field
            var holes = part;
            holes.h = A.panorama.h; // the strip's 16 rows; row 17 stays clear
            blit.blit(dst, A.font, holes, x, SCROLL_Y, A.colors.FONT_FIELD, .{ .pattern = pano });
        }
        blit.blit(dst, A.logo, null, LOGO_X, 0, 0, .copy);
    }
};
