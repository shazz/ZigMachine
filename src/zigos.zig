const std = @import("std");
const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Enum
// --------------------------------------------------------------------------
pub const Resolution = enum { truecolor, planes };

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
pub const PHYSICAL_WIDTH: u16 = 400;
pub const PHYSICAL_HEIGHT: u16 = 280;
pub const WIDTH: u16 = 320;
pub const HEIGHT: u16 = 200;
pub const NB_PLANES: u8 = 4;
pub const HORIZONTAL_BORDERS_WIDTH: u16 = (PHYSICAL_WIDTH - WIDTH) / 2;
pub const VERTICAL_BORDERS_HEIGHT: u16 = (PHYSICAL_HEIGHT - HEIGHT) / 2;

const SYSTEM_FONT = @embedFile("assets/fonts/system_font_atari_1bit.raw");
const SYSTEM_FONT_WIDTH = 8;
const SYSTEM_FONT_HEIGHT = 8;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Structs
// --------------------------------------------------------------------------
pub const RenderTarget = union(enum) {
    fb: *LogicalFB,
    buffer: []u8,

    pub fn clearFrameBuffer(self: RenderTarget, pal_entry: u8) void {

        switch (self) {
            .fb => |fb| {
                fb.clearFrameBuffer(pal_entry);
            },
            .buffer => |buffer| {
                var i: u16 = 0;
                while (i < buffer.len) : (i += 1) {
                    buffer[i] = pal_entry;
                }
            }
        }

    }      

    pub fn setPixelValue(self: RenderTarget, x: u16, y: u16, pal_entry: u8) void {

        switch (self) {
            .fb => |fb| {
                fb.setPixelValue(x, y, pal_entry);
            },
            .buffer => |buffer| {
                if ((x >= 0) and (x < WIDTH) and (y >= 0) and (y < HEIGHT)) {
                    const index: u32 = @as(u32, y) * @as(u32, WIDTH) + @as(u32, x);
                    buffer[index] = pal_entry;
                }
            }
        } 
    }    
};

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
    fb_hbl_handler: ?*const fn (*LogicalFB, u16) void,
    is_enabled: bool = undefined,

    pub fn init(self: *LogicalFB) void {
        Console.log("Init Logical Framebuffer {d}", .{self.id});

        Console.log("Clear Logical Framebuffer {d} palette", .{self.id});
        for (self.palette) |_, i| {
            self.palette[i] = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
        }

        Console.log("Clear Logical Framebuffer {d}", .{self.id});
        self.clearFrameBuffer(0);

        self.is_enabled = false;
    }

    pub fn getRenderTarget(self: *LogicalFB) RenderTarget {
        return RenderTarget{ .fb = self};
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
        // Console.log("Palette entry {} of FB {d} updated to ({}, {}, {}, {})", .{ entry, self.id, value.r, value.g, value.b, value.a });
    }

    pub fn getPaletteEntry(self: *LogicalFB, entry: u8) Color {
        return self.palette[entry];
    }

    pub fn setFramebufferBackgroundColor(self: *LogicalFB, pal_entry: u8) void {
        self.back_color = pal_entry;
    }

    pub fn setPixelValue(self: *LogicalFB, x: u16, y: u16, pal_entry: u8) void {
        if ((x >= 0) and (x < WIDTH) and (y >= 0) and (y < HEIGHT)) {
            const index: u32 = @as(u32, y) * @as(u32, WIDTH) + @as(u32, x);
            self.fb[index] = pal_entry;
        }
    }

    pub fn drawScanline(self: *LogicalFB, x1: u16, x2: u16, y: u16, pal_entry: u8) void {
        if ((x1 >= 0) and (x1 < WIDTH) and (x2 >= 0) and (x2 < WIDTH) and (y >= 0) and (y < HEIGHT)) {

            // number of pixels to draw on the scanline
            const delta = x2 - x1;

            // address of the first pixel in the framebuffer
            var index: u32 = @as(u32, y) * @as(u32, WIDTH) + @as(u32, x1);

            // linearly set the palette entry along the scanline (at FB possition)] for delta pixels
            var i: u16 = 0;
            while (i < delta) : (i += 1) {
                self.fb[index] = pal_entry;
                index += 1;
            }
        }
    }

    pub fn clearFrameBuffer(self: *LogicalFB, pal_entry: u8) void {
        var i: u16 = 0;
        while (i < 64000) : (i += 1) {
            self.fb[i] = pal_entry;
        }
    }

    pub fn setFrameBufferHBLHandler(self: *LogicalFB, handler: *const fn (*LogicalFB, u16) void) void {
        self.fb_hbl_handler = handler;
    }
};

// --------------------------------------------------------------------------
// Zig OS
// --------------------------------------------------------------------------
pub const ZigOS = struct {
    resolution: Resolution = Resolution.planes,
    background_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
    physical_framebuffer: [PHYSICAL_HEIGHT][PHYSICAL_WIDTH]u32 = undefined,
    lfbs: [NB_PLANES]LogicalFB = undefined,
    hbl_handler: ?*const fn (*ZigOS, u16) void = undefined,
    system_font: []const u8 = undefined,

    pub fn init(self: *ZigOS) void {
        self.physical_framebuffer = std.mem.zeroes([PHYSICAL_HEIGHT][PHYSICAL_WIDTH]u32);
        self.resolution = Resolution.planes;
        self.background_color = Color{ .r = 20, .g = 20, .b = 20, .a = 255 };
        self.system_font = SYSTEM_FONT;

        for (self.lfbs) |*lfb, idx| {
            lfb.*.id = @intCast(u8, idx);
            lfb.init();
        }

        Console.log("fb zigos: {}", .{@ptrToInt(&self.physical_framebuffer)});
    }

    // --------------------------------------------------------------------------
    // Features
    // --------------------------------------------------------------------------
    pub fn nop(self: *ZigOS) void {
        _ = self;
    }

    pub fn printText(self: *ZigOS, lfb: *LogicalFB, text: []const u8, x: u16, y: u16, fg_color_index: u8, bg_color_index: u8) void {

        // pointer to logical framebuffer
        var buffer: *[64000]u8 = &lfb.fb;

        const initial_position: u16 = y * WIDTH + x;

        // get character
        for (text) |char, nb| {

            // slice offsets
            var slice_offset_start: u16 = @intCast(u16, char) * (SYSTEM_FONT_WIDTH * SYSTEM_FONT_HEIGHT) - 1;
            var slice_offset_end: u16 = (@intCast(u16, char) + 1) * (SYSTEM_FONT_WIDTH * SYSTEM_FONT_HEIGHT);

            const char_data = self.system_font[slice_offset_start..slice_offset_end];
            var letter_pos = initial_position + (@intCast(u16, nb) * SYSTEM_FONT_WIDTH);

            for (char_data) |pixel, idx| {
                buffer[letter_pos] = if (pixel == 1) fg_color_index else bg_color_index;

                if (idx > 0 and (idx % SYSTEM_FONT_WIDTH == 0)) {
                    letter_pos += (WIDTH - SYSTEM_FONT_WIDTH + 1);
                } else {
                    letter_pos += 1;
                }
            }
        }
    }

    // --------------------------------------------------------------------------
    // Framebuffer management
    // --------------------------------------------------------------------------
    pub fn setResolution(self: *ZigOS, res: Resolution) void {
        self.resolution = res;
    }

    pub fn setBackgroundColor(self: *ZigOS, color: Color) void {
        self.background_color = color;
    }

    pub fn getBackgroundColor(self: *ZigOS) Color {
        return self.background_color;
    }

    pub fn setHBLHandler(self: *ZigOS, handler: *const fn (*ZigOS, u16) void) void {
        self.hbl_handler = handler;
    }
};
