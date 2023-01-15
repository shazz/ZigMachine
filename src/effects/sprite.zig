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
const OFFSET_DATA_SIZE = WIDTH*4;

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
    x_position: i32 = undefined,
    y_position: i32 = undefined,
    data: []const u8 = undefined,
    x_offset_index: f16 = undefined,
    apply_x_offset: bool = undefined,
    y_offset_table: ?[OFFSET_DATA_SIZE]i16 = undefined,
    y_offset_index: u16 = undefined,


    pub fn init(self: *Sprite, fb: *LogicalFB, data: []const u8, width: u16, height: u16, x_position: i32, y_position: i32, apply_x_offset: bool, y_offset_table: ?[OFFSET_DATA_SIZE]i16) void {
        self.fb = fb;
        self.width = width;
        self.height = height;
        self.x_position = x_position;
        self.y_position = y_position;
        self.data = data;

        self.x_offset_index = 0.0;
        self.apply_x_offset = apply_x_offset;

        if(y_offset_table) |table| {
            self.y_offset_table = table;
            self.y_offset_index = 0;
        }

        // x_position_table: [255]u16;

        // var f_row: f16 = @intToFloat(f16, row_counter);
        // var f_sin: f16 = (1.0 + @sin(f_row + self.sin_counter)) * 2.0;
        // delta = @floatToInt(u16, f_sin);

    }

    pub fn update(self: *Sprite, x_position: ?i32, y_position: ?i32, y_offset_table_index: ?u16) void {
        if (x_position) |new_offset| {
            self.x_position = new_offset;
        }
        if (y_position) |new_offset| {
            self.y_position = new_offset;
        }

        // Console.log("Apply offset: {}", .{self.apply_x_offset});
        if (self.apply_x_offset == true) {
            self.x_offset_index += 0.2;
            if (self.x_offset_index >= std.math.inf(f16)) {
                Console.log("reset", .{});
                self.x_offset_index = 0.0;
            }
        }

        if (y_offset_table_index) |index| {
            self.y_offset_index = index;
        }
    }

    pub fn render(self: *Sprite) void {
        var buffer: *[64000]u8 = &self.fb.fb;

        var nb_cols = self.width;
        var left_clamp = false;
        var right_clamp = false;
        var clamp_sprite: bool = false;

        var left_x_position: u16 = 0;
        var left_x_clamped: u16 = 0;

        // left clamp
        if (self.x_position < 0) {
            // Console.log("left clamping for x={}", .{self.x_position});
            left_clamp = true;
            left_x_position = 0;

            left_x_clamped = @intCast(u16, -self.x_position);
            nb_cols = self.width - left_x_clamped;
        } else {
            left_x_position = @intCast(u16, self.x_position);
        }

        // right clamp
        if (left_x_position + self.width >= (WIDTH - 1)) {
            right_clamp = true;
            if (left_x_position > WIDTH - 1) {
                clamp_sprite = true;
            } else {
                nb_cols = WIDTH - left_x_position;
            }
        }

        // TODO: top and bottom clamp
        var clamped_y_position: u16 = 0;
        if (self.y_position < 0) {
            clamped_y_position = 0;
        } else {
            clamped_y_position = @intCast(u16, self.y_position);
        }

        // clamped offset in FB
        var offset: u16 = left_x_position + (clamped_y_position * WIDTH);

        // counter for each sprite row
        var row_counter: u16 = 0;

        // counter for each pixel (palette entry) of the sprite
        var data_counter: u16 = left_x_clamped;
        var delta: u16 = 0;

        if (clamp_sprite == false) {

            // Console.log("Plotting sprite at ({}, {}) with {} cols", .{left_x_position, clamped_y_position, nb_cols});

            while (row_counter < self.height) : (row_counter += 1) {

                // counter for each pixel of the sprite for a given row
                var col_counter: u16 = 0;
                while (col_counter < nb_cols) : (col_counter += 1) {

                    // apply y offset
                    var new_offset = offset;
                    if (self.y_offset_table) |table| {
                        var counter: u16 = col_counter + left_x_position + self.y_offset_index;
                        if(counter >= table.len) counter -= @intCast(u16, table.len);

                        var off = table[counter];
                        if (off < 0) {
                            new_offset -= (@intCast(u16, -off) * WIDTH);
                        } else {
                            new_offset += (@intCast(u16, off) * WIDTH);
                        }
                    }

                    // clamp if outside buffer
                    if ((new_offset + col_counter < self.data.len) or (new_offset + col_counter >= 0)) {
                        buffer[new_offset + col_counter] = self.data[data_counter];
                    }
                    data_counter += 1;
                }

                // update pointer if right or left clamp
                if (right_clamp == true) {
                    data_counter += (self.width - nb_cols);
                }
                if (left_clamp == true) {
                    data_counter += left_x_clamped;
                }

                if (self.apply_x_offset == true) {
                    var f_row: f16 = @intToFloat(f16, row_counter);
                    var f_sin: f16 = (1.0 + @sin(f_row + self.x_offset_index)) * 1.1;
                    delta = @floatToInt(u16, f_sin);
                }

                // recompute FB offset
                offset = delta + left_x_position + (clamped_y_position * WIDTH) + (WIDTH * row_counter);
            }
        }
    }
};
