// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Sprite = @import("sprite.zig").Sprite;

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
pub fn Scrolltext(
    comptime nb_fonts: comptime_int,
) type {
    return struct {

        const FontLetter = struct { 
            char: u8 = undefined, 
            sprite: Sprite = undefined, 
            pos_x: i32 = undefined, 
            pos_y: i32 = undefined 
        };

        fb: *LogicalFB = undefined,
        speed: u16 = undefined,
        text: []const u8 = undefined,
        font_chars: []const u8 = undefined,
        text_pos: u16 = undefined,
        font_width: u16 = undefined,
        font_height: u16 = undefined,
        font_img: []const u8 = undefined,
        pos_y: u16 = undefined,
        fonts: [nb_fonts]FontLetter = undefined,
        offset_table: ?[]const u16 = undefined,
        apply_offset_table: bool = false,
        y_offset_table: ?[]const i16 = undefined,
        y_offset_table_index: u16 = undefined,
        const Self = @This();

        pub fn init(fb: *LogicalFB, font_img: []const u8, font_chars: []const u8, width: u16, height: u16, text: []const u8, speed: u16, pos_y: u16, offset_table: ?[]const u16, y_offset_table: ?[]const i16) Self {
            
            var scroller = Self{};
            scroller.font_img = font_img;
            scroller.font_chars = font_chars;
            scroller.font_width = width;
            scroller.font_height = height;
            scroller.text = text;
            scroller.speed = speed;
            scroller.fb = fb;
            scroller.pos_y = pos_y;
            if (offset_table) |table| {
                scroller.offset_table = table;
                scroller.apply_offset_table = true;
            }

            if (y_offset_table) |table| {
                scroller.y_offset_table = table;
                scroller.y_offset_table_index = 0;
            }        

            // create as many Sprites as letters shown on screen
            const current_text: *const [nb_fonts]u8 = scroller.text[0..nb_fonts];
            for (current_text) |char, idx| {
                const letter: u8 = char - scroller.font_chars[0];
                const pos_x: u16 = @intCast(u16, idx) * scroller.font_width;

                Console.log("Creating FontLetter {c} {} for ASCII {} at ({}, {}). Staring value: {}", .{ char, idx, letter, pos_x, pos_y, scroller.font_chars[0] });

                scroller.fonts[idx] = FontLetter{ .char = char, .sprite = Sprite{}, .pos_x = pos_x, .pos_y = pos_y };

                var char_pos_y: u16 = undefined;
                if (scroller.apply_offset_table) {  
                    if (scroller.offset_table) |table| {
                        char_pos_y = table[pos_x];
                    }
                } else {
                    char_pos_y = scroller.pos_y + pos_y;
                }

                scroller.fonts[idx].sprite.init(scroller.fb, 
                                                scroller.font_img[letter * (scroller.font_width * scroller.font_height) .. (letter + 1) * (scroller.font_width * scroller.font_height)], 
                                                scroller.font_width, 
                                                scroller.font_height, 
                                                pos_x, 
                                                char_pos_y, 
                                                false, 
                                                y_offset_table);
                scroller.text_pos = nb_fonts;
            }

            Console.log("Scrolltext inited!", .{});
            
            return scroller;    
        }

        pub fn update(self: *Self) void {

            // apply y_offset table if set
            if (self.y_offset_table) |table| {
                if(self.y_offset_table_index > self.speed*2) {
                    self.y_offset_table_index -= self.speed*2;
                } else {
                    // Console.log("Reset y offset index: {}", .{self.y_offset_table_index});
                    self.y_offset_table_index = @intCast(u16, table.len);
                }
            }

            for (self.fonts) |*font| {
                var is_out: i32 = @intCast(i32, font.pos_x) - @intCast(i32, self.speed);
                if (is_out < -@intCast(i8, self.font_width)) {
                    font.pos_x = WIDTH - 1;

                    // show new letter
                    if (self.text_pos >= self.text.len) self.text_pos = 0;

                    const next_letter = self.text[self.text_pos] - self.font_chars[0];
                    font.*.sprite.data = self.font_img[next_letter * (self.font_width * self.font_height) .. (next_letter + 1)];
                    // Console.log("Creating FontLetter {c} {} for ASCII {}.", .{ self.text[self.text_pos], idx, next_letter + self.font_chars[0] });
                    self.text_pos += 1;
                } else {
                    font.*.pos_x -= self.speed;
                }

                // apply y offset if set
                if (self.offset_table) |table| {
                    if (font.pos_x < 0) {
                        const pos: u16 = @intCast(u16, WIDTH + font.pos_x);
                        font.*.pos_y = self.pos_y + table[@intCast(u16, pos)];
                    } else {
                        font.*.pos_y = self.pos_y + table[@intCast(u16, font.pos_x)];
                    }
                }

                font.*.sprite.update(font.pos_x, font.pos_y, self.y_offset_table_index);
            }
        }

        pub fn render(self: *Self) void {
            for (self.fonts) |*font| {
                font.sprite.render();
            }
        }
    };
}