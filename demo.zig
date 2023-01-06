// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Color = @import("zigos.zig").Color;

const Starfield = @import("effects/starfield.zig").Starfield;
const StarfieldDirection = @import("effects/starfield.zig").StarfieldDirection;

const Fade = @import("effects/fade.zig").Fade;
const Sprite = @import("effects/sprite.zig").Sprite;
const Background = @import("effects/background.zig").Background;
const Scrolltext = @import("effects/scrolltext.zig").Scrolltext;

const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("zigos.zig").HEIGHT;
const WIDTH: u16 = @import("zigos.zig").WIDTH;

// scrolltext
const fonts_b = @embedFile("assets/blade_font_interlaced.raw");

// background
const back_b = @embedFile("assets/back.raw");

// big sprite
const logo_b = @embedFile("assets/logo.raw");
const sprite_b = @embedFile("assets/logo_283x124.raw");
const sprite_width: u16 = 283;
const sprite_height: u16 = 124;
const sprite_xoffset: u16 = 26;
const sprite_yoffset: u16 = 10;

const sprite_pal: [256]Color = blk: {
    const contents: []const u8 = @embedFile("assets/sprite.pal");
    if (contents.len != 4 * 256)
        @compileError(std.fmt.comptimePrint("Expected file to be {d} bytes, but it's {d} bytes.", .{ 4 * 256, contents.len }));
    @setEvalBranchQuota(contents.len);
    const arrays: *const [256][4]u8 = std.mem.bytesAsValue([256][4]u8, contents[0..]);
    var colors: [256]Color = undefined;
    for (arrays) |arr, i| colors[i] = .{
        .r = arr[0],
        .g = arr[1],
        .b = arr[2],
        .a = arr[3],
    };
    break :blk colors;
};

const back_pal: [256]Color = blk: {
    const contents: []const u8 = @embedFile("assets/back.pal");
    if (contents.len != 4 * 256)
        @compileError(std.fmt.comptimePrint("Expected file to be {d} bytes, but it's {d} bytes.", .{ 4 * 256, contents.len }));
    @setEvalBranchQuota(contents.len);
    const arrays: *const [256][4]u8 = std.mem.bytesAsValue([256][4]u8, contents[0..]);
    var colors: [256]Color = undefined;
    for (arrays) |arr, i| colors[i] = .{
        .r = arr[0],
        .g = arr[1],
        .b = arr[2],
        .a = arr[3],
    };
    break :blk colors;
};

const font_pal: [256]Color = blk: {
    const contents: []const u8 = @embedFile("assets/blade_font.pal");
    if (contents.len != 4 * 256)
        @compileError(std.fmt.comptimePrint("Expected file to be {d} bytes, but it's {d} bytes.", .{ 4 * 256, contents.len }));
    @setEvalBranchQuota(contents.len);
    const arrays: *const [256][4]u8 = std.mem.bytesAsValue([256][4]u8, contents[0..]);
    var colors: [256]Color = undefined;
    for (arrays) |arr, i| colors[i] = .{
        .r = arr[0],
        .g = arr[1],
        .b = arr[2],
        .a = arr[3],
    };
    break :blk colors;
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

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
            self.sprite.update(null, self.sprite_y_offset);

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
    starfield: Starfield = undefined,
    big_sprite: SpriteEffect = undefined,
    back: Background = undefined,
    scrolltext: Scrolltext = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.setPalette(back_pal);
        self.back.init(fb, back_b);

        // second plane
        fb = &zigos.lfbs[1];
        self.starfield.init(fb, WIDTH, HEIGHT, 3, StarfieldDirection.RIGHT, 0);

        // third plane
        fb = &zigos.lfbs[2];
        fb.setPalette(sprite_pal);

        // fade out palette by alpha
        self.big_sprite.sprite_y_offset = sprite_yoffset;
        self.big_sprite.sprite_y_dir = true;
        self.big_sprite.fade.init(fb, true, 1, 16, true);
        self.big_sprite.sprite.init(fb, sprite_b, sprite_width, sprite_height, sprite_xoffset, sprite_yoffset, true);

        // 4th plane
        fb = &zigos.lfbs[3];
        fb.setPalette(font_pal);
        self.scrolltext.init(fb, fonts_b, " ABCDEFGHIJKLMNOPQRSTUVWXYZ", 40, 34, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 3, 160);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void {
        self.starfield.update();
        self.big_sprite.update();
        self.scrolltext.update();

        _ = zigos;
    }

    pub fn render(self: *Demo, zigos: *ZigOS) void {
        self.back.render();
        self.starfield.render();
        self.big_sprite.render();
        self.scrolltext.fb.clearFrameBuffer(0);
        self.scrolltext.render();

        _ = zigos;
    }
};
