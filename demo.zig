// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Color = @import("zigos.zig").Color;

const Starfield = @import("effects/starfield.zig").Starfield;
const Fade = @import("effects/fade.zig").Fade;
const Sprite = @import("effects/sprite.zig").Sprite;
const Background = @import("effects/background.zig").Background;

const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("zigos.zig").HEIGHT;
const WIDTH: u16 = @import("zigos.zig").WIDTH;

const back_b = @embedFile("assets/back.raw");

const logo_b = @embedFile("assets/logo.raw");
const sprite_b = @embedFile("assets/logo_283x124.raw");
const sprite_width: u16 = 283;
const sprite_height: u16 = 124;
const sprite_xoffset: u16 = 26;
const sprite_yoffset: u16 = 40;

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

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var logo_bitmap: []u8 = undefined;
var fade_dir: bool = true;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    name: u8 = 0,
    frame_counter: u32 = 0,
    rnd: std.rand.DefaultPrng = undefined,
    starfield: Starfield = undefined,
    fade: Fade = undefined,
    big_sprite: Sprite = undefined,
    back: Background = undefined,
    sprite_y_offset: u16 = undefined,
    sprite_y_dir: bool = undefined,

    pub fn init(zigos: *ZigOS) !Demo {
        Console.log("Demo init", .{});

        var u_row: u16 = 10;
        var f_row: f16 = @intToFloat(f16, u_row);
        var f_sin: f16 = (1.0 + @sin(f_row)) * 100.0;
        var u_sin: u16 = @floatToInt(u16, f_sin);

        Console.log("u_row: {d} -> f_row: {} -> sin: {} -> u_sin: {}", .{ u_row, f_row, f_sin, u_sin });

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.setPalette(back_pal);
        var back: Background = Background.init(fb, back_b);

        // second plane
        fb = &zigos.lfbs[1];
        var starfield: Starfield = Starfield.init(fb, WIDTH, HEIGHT, 3, 0);

        // third plane
        fb = &zigos.lfbs[2];
        // Set palette
        fb.setPalette(sprite_pal);

        // fade out palette by alpha
        var fade: Fade = Fade.init(fb, true, 1, 16, true);
        var big_sprite: Sprite = Sprite.init(fb, sprite_b, sprite_width, sprite_height, sprite_xoffset, sprite_yoffset);

        Console.log("demo init done!", .{});

        return .{ .starfield = starfield, .fade = fade, .back = back, .big_sprite = big_sprite, .sprite_y_offset = sprite_yoffset, .sprite_y_dir = true };
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void {
        _ = zigos;

        self.starfield.update();

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
        self.big_sprite.update(null, self.sprite_y_offset);

        // fade in then out then in...
        if (self.frame_counter < 50 * 10) {
            self.fade.update(true);
        } else {
            self.fade.update(false);
        }

        if (self.frame_counter > 50 * 15) self.frame_counter = 0;

        self.frame_counter += 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS) void {
        self.back.render();
        self.starfield.render();
        self.big_sprite.render();

        _ = zigos;
    }

    pub fn deinit() void {}
};
