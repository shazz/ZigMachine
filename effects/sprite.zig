// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

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
pub const Sprite = struct {
    fb: *LogicalFB = undefined,
    width: u16 = undefined,
    height: u16 = undefined,
    x_offset: u16 = undefined,
    y_offset: u16 = undefined,
    data: []const u8 = undefined,
    table_counter: f16 = undefined,

    pub fn init(fb: *LogicalFB, data: []const u8, width: u16, height: u16, x_offset: u16, y_offset: u16) Sprite {

        // x_offset_table: [255]u16;

        // var f_row: f16 = @intToFloat(f16, row_counter);
        // var f_sin: f16 = (1.0 + @sin(f_row + self.sin_counter)) * 2.0;
        // delta = @floatToInt(u16, f_sin);

        return .{ .fb = fb, .width = width, .height = height, .x_offset = x_offset, .y_offset = y_offset, .data = data, .table_counter = 0.0 };
    }

    pub fn update(self: *Sprite, x_offset: ?u16, y_offset: ?u16) void {
        if (x_offset) |new_offset| {
            self.x_offset = new_offset;
        }
        if (y_offset) |new_offset| {
            self.y_offset = new_offset;
        }

        self.table_counter += 0.2;
    }

    pub fn render(self: *Sprite) void {
        var buffer: *[64000]u8 = &self.fb.fb;
        var offset: u16 = self.x_offset + (self.y_offset * WIDTH);

        // counter for each sprite row
        var row_counter: u16 = 0;

        // counter for each pixel (palette entry) of the sprite
        var data_counter: u16 = 0;
        var delta: u16 = 0;

        while (row_counter < self.height) : (row_counter += 1) {

            // counter for each pixel of the sprite for a given row
            var col_counter: u16 = 0;
            while (col_counter < self.width) : (col_counter += 1) {
                buffer[offset + col_counter] = self.data[data_counter];
                data_counter += 1;
            }

            var f_row: f16 = @intToFloat(f16, row_counter);
            var f_sin: f16 = (1.0 + @sin(f_row + self.table_counter)) * 1.1;
            delta = @floatToInt(u16, f_sin);

            // recompute FB offset
            offset = delta + self.x_offset + (self.y_offset * WIDTH) + (WIDTH * row_counter);
        }
    }
};
