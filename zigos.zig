const std = @import("std");
const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Enum
// --------------------------------------------------------------------------
pub const Resolution = enum { truecolor, planes };

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
pub const WIDTH: u16 = 320;
pub const HEIGHT: u16 = 200;
pub const NB_PLANES: u8 = 4;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Structs
// --------------------------------------------------------------------------
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn toRGBA(self: Color) u32 {
        const col: u32 = (@intCast(u32, self.a) << 24) | (@intCast(u32, self.b) << 16) | (@intCast(u32, self.g) << 8) | (@intCast(u32, self.r));
        return col;
    }
};

pub const LogicalFB = struct {
    fb: [WIDTH * HEIGHT]u8 = undefined,
    palette: [256]Color = undefined,
    back_color: u8 = 0,
    id: u8 = 0,

    pub fn init(self: *LogicalFB) void {
        Console.log("Init Logical Framebuffer {d}", .{self.id});

        Console.log("Clear Logical Framebuffer {d} palette", .{self.id});
        for (self.palette) |_, i| {
            self.palette[i] = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
        }

        Console.log("Clear Logical Framebuffer {d}", .{self.id});
        self.clearFrameBuffer(0);
    }

    // --------------------------------------------------------------------------
    // Palette management
    // --------------------------------------------------------------------------
    pub fn setPalette(self: *LogicalFB, entries: [256]Color) void {
        self.palette = entries;

        Console.log("Palette of FB {d} updated", .{self.id});
    }

    pub fn setPaletteEntry(self: *LogicalFB, entry: u8, value: Color) void {
        self.palette[entry] = value;
    }

    pub fn getPaletteEntry(self: *LogicalFB, entry: u8) Color {
        return self.palette[entry];
    }

    pub fn setFramebufferBackgroundColor(self: *LogicalFB, pal_entry: u8) void {
        self.back_color = pal_entry;
    }

    pub fn setPixelValue(self: *LogicalFB, x: u16, y: u16, pal_entry: u8) void {

        if( (x >= 0) and (x < WIDTH) and (y >= 0) and (y < HEIGHT) )
        {
            const index: u32 = @as(u32, y) * @as(u32, WIDTH) + @as(u32, x);
            self.fb[index] = pal_entry;
        }
    }

    pub fn clearFrameBuffer(self: *LogicalFB, pal_entry: u8) void {
        var i: u16 = 0;
        while (i < 64000) : (i += 1) {
            self.fb[i] = pal_entry;
        }
    }
};

// --------------------------------------------------------------------------
// Zig OS
// --------------------------------------------------------------------------
pub const ZigOS = struct {
    resolution: Resolution = Resolution.planes,
    physical_framebuffer: [WIDTH][HEIGHT]u32 = undefined,
    lfbs: [NB_PLANES]LogicalFB = undefined,

    pub fn init(self: *ZigOS) void {
        self.physical_framebuffer = std.mem.zeroes([WIDTH][HEIGHT]u32);
        self.resolution = Resolution.planes;

        for (self.lfbs) |*lfb, idx| {
            lfb.*.id = @intCast(u8, idx);
            lfb.init();
        }
    }

    // --------------------------------------------------------------------------
    // Features
    // --------------------------------------------------------------------------
    pub fn nop(self: *ZigOS) void {
        _ = self;
    }

    // --------------------------------------------------------------------------
    // Framebuffer management
    // --------------------------------------------------------------------------
    pub fn setResolution(self: *ZigOS, res: Resolution) void {
        self.resolution = res;
    }
};
