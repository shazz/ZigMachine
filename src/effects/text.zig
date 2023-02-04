// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const RenderTarget = @import("../zigos.zig").RenderTarget;

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

    pub fn render(self: *Text, text: []const u8, x: u16, y: u16) void {

        // pointer to logical framebuffer
        const initial_position: u32 = @intCast(u32, y) * @intCast(u32, WIDTH) + @intCast(u32, x);

        // get character
        for (text) |char, nb| {

            // slice offsets
            const letter: u8 = char - self.font_chars[0];
            var delta: u16 = 1;
            if(letter == 0) delta = 0;

            var slice_offset_start: u16 = @intCast(u16, letter) * (self.font_width * self.font_height) - delta;
            var slice_offset_end: u16 = (@intCast(u16, letter) + 1) * (self.font_width * self.font_height) - 1;
        
            const char_data = self.font_img[slice_offset_start..slice_offset_end];
            var letter_pos: u32 = initial_position + (@intCast(u32, nb) * @intCast(u32,self.font_width));

            // Console.log("Char {c}({} - {} = {}) to display at ({}, {}) offset: {}", .{char, char, self.font_chars[0], letter, x, y, slice_offset_start});
            // Console.log("Char {c} to display at ({}, {}) position in buffer: {}", .{char, x, y, letter_pos});
            
            switch (self.target) {
                .fb => |fb| {
                    var buffer: *[64000]u8 = &fb.fb;

                    for (char_data) |pixel, idx| {
                        buffer[letter_pos] = pixel;

                        if (idx > 0 and (idx % self.font_width == 0)) {
                            letter_pos += (WIDTH - self.font_width + 1);
                        } else {
                            letter_pos += 1;
                        }
                    }
                },

                .render_buffer => |rbuf| {

                    for (char_data) |pixel, idx| {
                        rbuf.buffer[letter_pos] = pixel;

                        if (idx > 0 and (idx % self.font_width == 0)) {
                            letter_pos += (@intCast(u32, (rbuf.width) - @intCast(u32, self.font_width) + 1));
                        } else {
                            letter_pos += 1;
                        }
                    }
                }
            }
        }
    }
};