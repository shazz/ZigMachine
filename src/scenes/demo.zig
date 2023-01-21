// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const readU16Array = @import("../utils/loaders.zig").readU16Array;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Starfield = @import("../effects/starfield.zig").Starfield;
const StarfieldDirection = @import("../effects/starfield.zig").StarfieldDirection;

const Fade = @import("../effects/fade.zig").Fade;
const Sprite = @import("../effects/sprite.zig").Sprite;
const Background = @import("../effects/background.zig").Background;
const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Dots3D = @import("../effects/dots3d.zig").Dots3D;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext
const fonts_b = @embedFile("../assets/fonts/ancool_font_interlaced.raw");
const offset_table_b = readU16Array(@embedFile("../assets/screens/scrolltext/scroll_sin.dat"));
const SCROLL_TEXT = "         0123456789 .-'? ABCDEFGHIJKLMNOPQRSTUVWXYZ"; //"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const SCROLL_CHAR_WIDTH = 32; // 40
const SCROLL_CHAR_HEIGHT = 16; // 34
const SCROLL_SPEED = 3; //
const SCROLL_CHARS = " !   '   -. 0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ"; //" ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// background
const back_b = @embedFile("../assets/screens/background/back.raw");

// big sprite
const logo_b = @embedFile("../assets/screens/logo_distort/logo.raw");
const sprite_b = @embedFile("../assets/screens/logo_distort/logo_283x124.raw");
const sprite_width: u16 = 283;
const sprite_height: u16 = 124;
const sprite_xoffset: u16 = 26;
const sprite_yoffset: u16 = 10;

const sprite_pal = convertU8ArraytoColors(@embedFile("../assets/screens/logo_distort/sprite.pal"));
const back_pal = convertU8ArraytoColors(@embedFile("../assets/screens/background/back.pal"));
const font_pal = convertU8ArraytoColors(@embedFile("../assets/fonts/ancool_font.pal"));
const NB_FONTS = 11;
// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

fn handler(zigos: *ZigOS, line: u16) void {
    zigos.setBackgroundColor(Color{ .r = @intCast(u8, line / 2), .g = @intCast(u8, line / 8), .b = 0, .a = 255 });
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    const SpriteEffect = struct {
        sprite: Sprite = undefined,
        sprite_y_offset: u16 = undefined,
        sprite_y_dir: bool = undefined,
        fade: Fade = undefined,
        counter: u32 = 0,

        fn update(self: *SpriteEffect) void {
            if (self.sprite_y_dir) {
                self.sprite_y_offset += 1;
            } else {
                self.sprite_y_offset -= 1;
            }

            if (self.sprite_y_offset >= sprite_yoffset + 20) {
                self.sprite_y_dir = false;
            }
            if (self.sprite_y_offset <= sprite_yoffset) {
                self.sprite_y_dir = true;
            }
            self.sprite.update(null, self.sprite_y_offset, null);

            // fade in then out then in...
            if (self.counter < 50 * 10) {
                self.fade.update(true);
            } else {
                self.fade.update(false);
            }

            if (self.counter > 50 * 15) self.counter = 0;

            self.counter += 1;
        }

        fn render(self: *SpriteEffect) void {
            self.sprite.render();
            self.fade.render();
        }
    };

    name: u8 = 0,
    frame_counter: u32 = 0,
    rnd: std.rand.DefaultPrng = undefined,
    starfield: Starfield(200) = undefined,
    big_sprite: SpriteEffect = undefined,
    back: Background = undefined,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    dots3D: Dots3D = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // HBL Handler
        zigos.setHBLHandler(handler);

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(back_pal);
        self.back.init(fb, back_b);

        // second plane
        fb = &zigos.lfbs[1];
        fb.is_enabled = true;
        self.starfield = Starfield(200).init(fb, WIDTH, 120, 0, 1, 3, StarfieldDirection.RIGHT);
        self.dots3D.init(fb);

        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.setPaletteEntry(4, Color{ .r = 0xF0, .g = 0xF0, .b = 0xF0, .a = 255 });
        fb.setPaletteEntry(3, Color{ .r = 0xA0, .g = 0xA0, .b = 0xA0, .a = 255 });
        fb.setPaletteEntry(2, Color{ .r = 0x60, .g = 0x60, .b = 0x60, .a = 255 });
        fb.setPaletteEntry(1, Color{ .r = 0x40, .g = 0x40, .b = 0x40, .a = 255 });
        
        // third plane
        fb = &zigos.lfbs[2];
        fb.is_enabled = true;
        fb.setPalette(sprite_pal);

        // fade out palette by alpha
        self.big_sprite.sprite_y_offset = sprite_yoffset;
        self.big_sprite.sprite_y_dir = true;
        self.big_sprite.fade.init(fb, true, 1, 16, true);
        self.big_sprite.sprite.init(fb, sprite_b, sprite_width, sprite_height, sprite_xoffset, sprite_yoffset, true, null);

        // 4th plane
        fb = &zigos.lfbs[3];
        fb.is_enabled = true;
        fb.setPalette(font_pal);


        self.scrolltext = Scrolltext(NB_FONTS).init(fb, fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 100, &offset_table_b, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        self.starfield.update();
        self.dots3D.update();

        self.big_sprite.update();
        self.scrolltext.update();

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        self.back.render();

        self.dots3D.fb.clearFrameBuffer(0);
        self.starfield.render();
        self.dots3D.render();

        self.big_sprite.sprite.fb.clearFrameBuffer(0);
        self.big_sprite.render();

        self.scrolltext.fb.clearFrameBuffer(1);
        self.scrolltext.render();

        _ = zigos;
        _ = elapsed_time;
    }
};
