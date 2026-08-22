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
            var letter_pos: u32 = initial_position + (@as(u32, @intCast(nb)) * @as(u32, @intCast(self.font_width)));

            // Console.log("Char {c}({} - {} = {}) to display at ({}, {}) offset: {}", .{char, char, self.font_chars[0], letter, x, y, slice_offset_start});
            // Console.log("Char {c} to display at ({}, {}) position in buffer: {}", .{char, x, y, letter_pos});
            
            switch (self.target) {
                .fb => |fb| {
                    const buffer = fb.fb; // [*]u8 view into the shared logical framebuffer

                    for (char_data, 0..) |pixel, idx| {

                        if(transparent_color) |color| {
                            if(pixel != color) buffer[letter_pos] = pixel;
                        } else {
                            buffer[letter_pos] = pixel;
                        }

                        if (idx > 0 and (idx % self.font_width == 0)) {
                            letter_pos += (WIDTH - self.font_width + 1);
                        } else {
                            letter_pos += 1;
                        }
                    }
                },

                .render_buffer => |rbuf| {

                    for (char_data, 0..) |pixel, idx| {
                        rbuf.buffer[letter_pos] = pixel;

                        if (idx > 0 and (idx % self.font_width == 0)) {
                            letter_pos += (@as(u32, @intCast((rbuf.width) - @as(u32, @intCast(self.font_width)) + 1)));
                        } else {
                            letter_pos += 1;
                        }
                    }
                }
            }
        }
    }
};