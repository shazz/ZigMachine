// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const RenderTarget = @import("../zigos.zig").RenderTarget;
const text_plot = @import("text_plot.zig");

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Text = struct {
    target: RenderTarget = undefined,
    font_chars: []const u8 = undefined,
    font_width: u16 = undefined,
    font_height: u16 = undefined,
    font_img: []const u8 = undefined,
                
    pub fn init(self: *Text, target: RenderTarget, font_img: []const u8, font_chars: []const u8, width: u16, height: u16) void {

        self.target = target;
        self.font_chars = font_chars;
        self.font_img = font_img;
        self.font_width = width;
        self.font_height = height;
    }

    pub fn update(self: *Text) void {
        _ = self;
    }    

    pub fn render(self: *Text, text: []const u8, x: u16, y: u16, transparent_color: ?u8) void {

        // pointer to logical framebuffer
        const initial_position: u32 = @as(u32, @intCast(y)) * @as(u32, @intCast(WIDTH)) + @as(u32, @intCast(x));

        // get character
        for (text, 0..) |char, nb| {

            // slice offsets
            const letter: u8 = char - self.font_chars[0];
            var delta: u16 = 1;
            if(letter == 0) delta = 0;

            const slice_offset_start: u16 = @as(u16, @intCast(letter)) * (self.font_width * self.font_height) - delta;
            const slice_offset_end: u16 = (@as(u16, @intCast(letter)) + 1) * (self.font_width * self.font_height) - 1;
        
            const char_data = self.font_img[slice_offset_start..slice_offset_end];
            const letter_pos: u32 = initial_position + (@as(u32, @intCast(nb)) * @as(u32, @intCast(self.font_width)));

            // text_plot: the same bytes at the same places, run by run, where the
            // loop took a modulo (a divide) and a byte store per pixel.
            switch (self.target) {
                .fb => |fb| text_plot.plot(fb.fb, letter_pos, WIDTH - self.font_width + 1, char_data, self.font_width, transparent_color),
                .render_buffer => |rbuf| text_plot.plot(rbuf.buffer.ptr, letter_pos, @as(u32, @intCast((rbuf.width) - @as(u32, @intCast(self.font_width)) + 1)), char_data, self.font_width, null),
            }
        }
    }
};