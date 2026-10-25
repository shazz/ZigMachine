// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const RenderTarget = @import("../zigos.zig").RenderTarget;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Console = @import("../utils/debug.zig").Console;
const draw = @import("sprite_draw.zig");

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
    x_offset_table: ?[] const i16,
    x_offset_index: u16 = undefined,
    y_offset_table: ?[] const i16,
    y_offset_index: u16 = undefined,


    pub fn init(self: *Sprite, target: RenderTarget, data: []const u8, width: u16, height: u16, x_position: i32, y_position: i32, x_offset_table: ?[] const i16, y_offset_table: ?[] const i16) void {
        self.target = target;
        self.width = width;
        self.height = height;
        self.x_position = x_position;
        self.y_position = y_position;
        self.data = data;

        if(y_offset_table) |table| {
            self.y_offset_table = table;
            self.y_offset_index = 0;
        } else {
            self.y_offset_table = null;
        }

        if(x_offset_table) |table| {
            self.x_offset_table = table;
            self.x_offset_index = 0;
        } else {
            self.x_offset_table = null;
        }        

    }

    pub fn update(self: *Sprite, x_position: ?i32, y_position: ?i32, x_offset_table_index: ?u16, y_offset_table_index: ?u16) void {
        if (x_position) |new_offset| {
            self.x_position = new_offset;
        }
        if (y_position) |new_offset| {
            self.y_position = new_offset;
        }

        if (x_offset_table_index) |index| {
            self.x_offset_index = index;
        }

        if (y_offset_table_index) |index| {
            self.y_offset_index = index;
        }        
    }

    pub fn render(self: *Sprite, except_color: ?u8) void {

        var first_color: Color = undefined;
        var is_tranparent: bool = undefined;
        var screen_width: u16 = 0;
        var screen_height: u16 = 0;
        var transparent_color: u8 = undefined;

        if(except_color) |entry| {
            transparent_color = entry;
        } else {
            transparent_color = 0;
        }

        switch (self.target) {
            .fb => |fb| {
                first_color = fb.getPaletteEntry(0);
                is_tranparent = (first_color.a == 0);
                screen_width = WIDTH;
                screen_height = HEIGHT;
            },
            .render_buffer => |rbuf| {
                first_color = Color{ .r=0, .g=0, .b=0, .a=0};
                is_tranparent = true;
                screen_width = rbuf.width;
                screen_height = rbuf.height;
            }
        }        

        var nb_cols = self.width;
        var left_clamp: bool = false;
        var right_clamp: bool = false;
        var clamp_sprite: bool = false;

        var left_x_position: u16 = 0;
        var left_x_clamped: u16 = 0;

        // checking is fully offscreen
        if( (self.x_position >= screen_width) or (self.y_position >= screen_height) or (self.x_position + self.width < 0) or (self.y_position + self.height < 0) ) clamp_sprite = true;

        // left clamp
        if (self.x_position < 0) {
            // Console.log("left clamping for x={}", .{self.x_position});
            left_clamp = true;
            left_x_position = 0;

            left_x_clamped = @as(u16, @intCast(-self.x_position));
            nb_cols = self.width - left_x_clamped;
        } else {
            left_x_position = @as(u16, @intCast(self.x_position));
        }

        // right clamp
        if (left_x_position + self.width > screen_width) {
            right_clamp = true;
            nb_cols = screen_width - left_x_position;
            // Console.log("right clamping for x={} / {} => {}", .{left_x_position, left_x_position + self.width, nb_cols});            
        }

        // top and bottom clamp
        var clamped_y_top_position: u16 = 0;
        if (self.y_position < 0) {
            clamped_y_top_position =  @as(u16, @intCast(-self.y_position));
            // Console.log("top clamping for y={} => {}", .{self.y_position, clamped_y_top_position});  
        } 

        var clamped_y_bottom_position: u16 = 0;
        if (self.y_position + self.height > screen_height) {
            clamped_y_bottom_position =  @as(u16, @intCast(self.height + self.y_position - screen_height));
            // Console.log("bottom clamping for y={} h={} => {}", .{self.y_position, self.height, clamped_y_bottom_position});  
        } 

        // offset in Framebuffer
        const offset: u16 = left_x_position + ( (@as(u16, @intCast(self.y_position)) + clamped_y_top_position) * screen_width );
        // Console.log("offset in FB left: {} y: {} clamp y: {} => {}", .{left_x_position, @as(u16, @intCast(self.y_position)), clamped_y_top_position, offset});  

        // counter for each pixel (palette entry) of the sprite
        const data_counter: u32 = left_x_clamped + (clamped_y_top_position * self.width);

        if (clamp_sprite == false) {
            const out: []u8 = switch (self.target) {
                .fb => |fb| fb.fb[0 .. @as(usize, screen_width) * screen_height],
                .render_buffer => |rbuf| rbuf.buffer,
            };
            draw.plot(.{
                .out = out,
                .data = self.data,
                .data_counter = data_counter,
                .offset = offset,
                .rows = self.height - clamped_y_top_position - clamped_y_bottom_position,
                .nb_cols = nb_cols,
                .width = self.width,
                .screen_width = screen_width,
                .left_x_position = left_x_position,
                .left_x_clamped = left_x_clamped,
                .left_clamp = left_clamp,
                .right_clamp = right_clamp,
                .skip = if (is_tranparent) transparent_color else draw.NO_SKIP,
                .y_table = self.y_offset_table,
                .y_index = if (self.y_offset_table != null) self.y_offset_index else 0,
                .x_table = self.x_offset_table,
                .x_index = if (self.x_offset_table != null) self.x_offset_index else 0,
            });
        }
    }
};
