// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const RenderTarget = @import("../zigos.zig").RenderTarget;
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
    target: RenderTarget = undefined,
    width: u16 = undefined,
    height: u16 = undefined,
    x_position: i32 = undefined,
    y_position: i32 = undefined,
    data: []const u8 = undefined,
    x_offset_index: f16 = undefined,
    apply_x_offset: bool = undefined,
    y_offset_table: ?[] const i16,
    y_offset_index: u16 = undefined,


    pub fn init(self: *Sprite, target: RenderTarget, data: []const u8, width: u16, height: u16, x_position: i32, y_position: i32, apply_x_offset: bool, y_offset_table: ?[] const i16) void {
        self.target = target;
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
        } else {
            self.y_offset_table = null;
        }

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
                // Console.log("reset", .{});
                self.x_offset_index = 0.0;
            }
        }

        if (y_offset_table_index) |index| {
            self.y_offset_index = index;
        }
    }

    pub fn render(self: *Sprite) void {

        var first_color: Color = undefined;
        var is_tranparent: bool = undefined;
         switch (self.target) {
            .fb => |fb| {
                first_color = fb.getPaletteEntry(0);
                is_tranparent = (first_color.a == 0);
            },
            .buffer => |_| {
                first_color = Color{ .r=0, .g=0, .b=0, .a=0};
                is_tranparent = true;
            }
        }        

        var nb_cols = self.width;
        var left_clamp: bool = false;
        var right_clamp: bool = false;
        var clamp_sprite: bool = false;

        var left_x_position: u16 = 0;
        var left_x_clamped: u16 = 0;

        // checking is fully offscreen
        if( (self.x_position >= WIDTH) or (self.y_position >= HEIGHT) or (self.x_position + self.width < 0) or (self.y_position + self.height < 0) ) clamp_sprite = true;

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
        if (left_x_position + self.width > WIDTH) {
            right_clamp = true;
            nb_cols = WIDTH - left_x_position;
            // Console.log("right clamping for x={} / {} => {}", .{left_x_position, left_x_position + self.width, nb_cols});            
        }

        // top and bottom clamp
        var clamped_y_top_position: u16 = 0;
        if (self.y_position < 0) {
            clamped_y_top_position =  @intCast(u16, -self.y_position);
            // Console.log("top clamping for y={} => {}", .{self.y_position, clamped_y_top_position});  
        } 

        var clamped_y_bottom_position: u16 = 0;
        if (self.y_position + self.height > HEIGHT) {
            clamped_y_bottom_position =  @intCast(u16, self.height + self.y_position - HEIGHT);
            // Console.log("bottom clamping for y={} h={} => {}", .{self.y_position, self.height, clamped_y_bottom_position});  
        } 

        // offset in Framebuffer
        var offset: u16 = left_x_position + ( (@intCast(u16, self.y_position) + clamped_y_top_position) * WIDTH );
        // Console.log("offset in FB left: {} y: {} clamp y: {} => {}", .{left_x_position, @intCast(u16, self.y_position), clamped_y_top_position, offset});  

        // counter for each sprite row
        var row_counter: u16 = 0;

        // counter for each pixel (palette entry) of the sprite
        var data_counter: u32 = left_x_clamped + (clamped_y_top_position * self.width);
        var delta: u16 = 0;

        if (clamp_sprite == false) {

            // Console.log("Plotting sprite at ({}, {}) with {} cols", .{left_x_position, clamped_y_position, nb_cols});

            while (row_counter < self.height - clamped_y_top_position - clamped_y_bottom_position) : (row_counter += 1) {

                // counter for each pixel of the sprite for a given row
                var col_counter: u16 = 0;
                while (col_counter < nb_cols) : (col_counter += 1) {

                    // apply y offset
                    var new_offset = offset;

                    if (self.y_offset_table) |y_table| {
     
                        var counter: u16 = col_counter + left_x_position + self.y_offset_index;
                        if(counter >= y_table.len) counter -= @intCast(u16, y_table.len);

                        var off = y_table[counter];
                        if (off < 0) {
                            new_offset -= (@intCast(u16, -off) * WIDTH);
                        } else {
                            new_offset += (@intCast(u16, off) * WIDTH);
                        }
                    }

                    // clamp if outside buffer
                    const pal_entry = self.data[data_counter];
                    if(!is_tranparent or pal_entry != 0) { 

                        if ((new_offset + col_counter < self.data.len) or (new_offset + col_counter >= 0)) {

                            switch (self.target) {
                                .fb => |fb| {
                                    fb.fb[new_offset + col_counter] = self.data[data_counter];
                                },
                                .buffer => |buffer| {
                                    buffer[new_offset + col_counter] = self.data[data_counter];
                                }
                            }
                        }
                    }
                    data_counter += 1;
                }

                // update pointer if right or left clamp
                if (right_clamp == true) {
                    data_counter += (self.width - nb_cols - left_x_clamped);
                }

                if (left_clamp == true) {
                    data_counter += left_x_clamped;
                }
                // Console.log("Left/Right clamp: advance pointer of {} + {} pixels", .{left_x_clamped, self.width - nb_cols - left_x_clamped});

                if (self.apply_x_offset == true) {
                    var f_row: f16 = @intToFloat(f16, row_counter);
                    var f_sin: f16 = (1.0 + @sin(f_row + self.x_offset_index)) * 1.1;
                    delta = @floatToInt(u16, f_sin);
                }

                // recompute FB offset
                offset += delta + WIDTH;
            }
        }
    }
};
