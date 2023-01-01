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

const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("zigos.zig").HEIGHT;
const WIDTH: usize = @import("zigos.zig").WIDTH;

const logo_b = @embedFile("assets/logo.raw");

const logo_pal: [256]Color = blk: {
    const contents: []const u8 = @embedFile("assets/logo.pal");
    if (contents.len != 4 * 256)
        @compileError(std.fmt.comptimePrint("Expected 'colors.txt' to be {d} bytes, but it's {d} bytes.", .{ 4 * 256, contents.len }));
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

    const Star = struct {
        x: u16 = undefined,
        y: u16 = undefined,
        speed: i8 = undefined,
    };

    name: u8 = 0,
    frame_counter: u32 = 0,
    rnd: std.rand.DefaultPrng = undefined,
    low_starfield: [100]Star = undefined,
    starfield: Starfield = undefined,
    fade: Fade = undefined,

    pub fn init(zigos: *ZigOS) !Demo { 

        Console.log("Demo init", .{});

        // -------------
        // Starfied init
        // -------------

        // Get lower plance
        var fb: *LogicalFB = &zigos.lfbs[0];
        var starfield: Starfield = Starfield.init(fb, WIDTH, HEIGHT, 3);

        // -------------
        // Logo init
        // -------------

        // get next plane
        fb = &zigos.lfbs[1];
        
        // Set palette
        fb.setPalette(logo_pal);

        // fade out palette by alpha
        var fade: Fade = Fade.init(fb, true, 1, 16, true);

        // Copy bitmap data
        var buffer: *[64000]u8 = &fb.fb;
        for (logo_b) |value, index| {
            buffer[index] = value;
        }

        Console.log("demo init done!", .{});

        return .{ .starfield = starfield, .fade=fade };
    }

    pub fn update(self: *Demo, zigos: *ZigOS) void { 

        // ---------------
        // Starfied update
        // ---------------
        self.starfield.update();

        // ---------------
        // Logo update
        // ---------------
        var fb: *LogicalFB = &zigos.lfbs[1];
    
        // Copy bitmap data
        var buffer: *[64000]u8 = &fb.fb;

        for (logo_b) |value, index| {
            buffer[index] = value;
        }

        // fade in then out then in...
        if (self.frame_counter < 50*10) {
            self.fade.update(true);
        } else {
            self.fade.update(false);
        }

        self.frame_counter += 1;

    }

    pub fn render(self: *Demo) void {
        self.starfield.render();
    }

    pub fn deinit() void {

    }
};