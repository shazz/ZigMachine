// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Color = @import("zigos.zig").Color;


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
const demo_name = "starfield";

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var logo_bitmap: []u8 = undefined;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {

    name: u8 = 0,

    pub fn init(zigos: *ZigOS) !Demo { 

        Console.log("demo init", .{});

        // get FB
        var fb0: *LogicalFB = &zigos.lfbs[0];
        
        // Set palette
        fb0.setPalette(logo_pal);

        // Check
        const pal0: Color = fb0.getPaletteEntry(0);
        const pal1: Color = fb0.getPaletteEntry(1);
        const pal2: Color = fb0.getPaletteEntry(2);

        Console.log("Pal 0: {d} {d} {d}", .{pal0.r, pal0.g, pal0.b});
        Console.log("Pal 1: {d} {d} {d}", .{pal1.r, pal1.g, pal1.b});
        Console.log("Pal 2: {d} {d} {d}", .{pal2.r, pal2.g, pal2.b});

        // Copy bitmap data
        var buffer: *[64000]u8 = &fb0.fb;
        for (logo_b) |value, index| {
            buffer[index] = value;
        }

        Console.log("Pixel 0: {d} {d} {d}", .{buffer[9080], buffer[9081], buffer[9082]});
        Console.log("demo init done!", .{});

        return .{ };
    }

    pub fn run(self: *Demo, zigos: *ZigOS) void { 

        _ = self;
        
        // get FB
        var fb0: *LogicalFB = &zigos.lfbs[0];
    
        // Copy bitmap data
        var buffer: *[64000]u8 = &fb0.fb;

        for (logo_b) |value, index| {
            buffer[index] = value;
        }
    }

    pub fn deinit() void {

    }
};