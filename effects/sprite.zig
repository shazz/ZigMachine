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
    x_offset: i32 = undefined,
    y_offset: i32 = undefined,
    data: []const u8 = undefined,
    table_counter: f16 = undefined,
    apply_offset: bool = undefined,

    pub fn init(self: *Sprite, fb: *LogicalFB, data: []const u8, width: u16, height: u16, x_offset: i32, y_offset: i32, apply_offset: bool) void {
        self.fb = fb;
        self.width = width;
        self.height = height;
        self.x_offset = x_offset;
        self.y_offset = y_offset;
        self.data = data;
        self.table_counter = 0.0;
        self.apply_offset = apply_offset;

        // x_offset_table: [255]u16;

        // var f_row: f16 = @intToFloat(f16, row_counter);
        // var f_sin: f16 = (1.0 + @sin(f_row + self.sin_counter)) * 2.0;
        // delta = @floatToInt(u16, f_sin);

    }

    pub fn update(self: *Sprite, x_offset: ?i32, y_offset: ?i32) void {
        if (x_offset) |new_offset| {
            self.x_offset = new_offset;
        }
        if (y_offset) |new_offset| {
            self.y_offset = new_offset;
        }

        // Console.log("Apply offset: {}", .{self.apply_offset});
        if (self.apply_offset == true) {
            self.table_counter += 0.2;
            if (self.table_counter >= std.math.inf(f16)) {
                Console.log("reset", .{});
                self.table_counter = 0.0;
            }
        }
    }

    pub fn render(self: *Sprite) void {
        var buffer: *[64000]u8 = &self.fb.fb;

        var nb_cols = self.width;
        var left_clamp = false;
        var right_clamp = false;
        var clamp_sprite: bool = false;

        var left_x_offset: u16 = 0;
        var left_x_clamped: u16 = 0;

        // left clamp
        if (self.x_offset < 0) {
            // Console.log("left clamping for x={}", .{self.x_offset});
            left_clamp = true;
            left_x_offset = 0;

            left_x_clamped = @intCast(u16, -self.x_offset);
            nb_cols = self.width - left_x_clamped;
        } else {
            left_x_offset = @intCast(u16, self.x_offset);
        }

        // right clamp
        if (left_x_offset + self.width >= (WIDTH - 1)) {
            right_clamp = true;
            if (left_x_offset >= 320) {
                clamp_sprite = true;
            } else {
                nb_cols = (WIDTH - 1) - left_x_offset;
            }
        }

        // TODO: top and bottom clamp
        var clamped_y_offset: u16 = 0;
        if (self.y_offset < 0) {
            clamped_y_offset = 0;
        } else {
            clamped_y_offset = @intCast(u16, self.y_offset);
        }

        // clamped offset in FB
        var offset: u16 = left_x_offset + (clamped_y_offset * WIDTH);

        // counter for each sprite row
        var row_counter: u16 = 0;

        // counter for each pixel (palette entry) of the sprite
        var data_counter: u16 = left_x_clamped;
        var delta: u16 = 0;

        if (clamp_sprite == false) {

            // Console.log("Plotting sprite at ({}, {}) with {} cols", .{left_x_offset, clamped_y_offset, nb_cols});

            while (row_counter < self.height) : (row_counter += 1) {

                // counter for each pixel of the sprite for a given row
                var col_counter: u16 = 0;
                while (col_counter < nb_cols) : (col_counter += 1) {
                    buffer[offset + col_counter] = self.data[data_counter];
                    data_counter += 1;
                }

                // update pointer if right or left clamp
                if (right_clamp == true) {
                    data_counter += (self.width - nb_cols);
                }
                if (left_clamp == true) {
                    data_counter += left_x_clamped;
                }

                if (self.apply_offset == true) {
                    var f_row: f16 = @intToFloat(f16, row_counter);
                    var f_sin: f16 = (1.0 + @sin(f_row + self.table_counter)) * 1.1;
                    delta = @floatToInt(u16, f_sin);
                }

                // recompute FB offset
                offset = delta + left_x_offset + (clamped_y_offset * WIDTH) + (WIDTH * row_counter);
            }
        }
    }
};
