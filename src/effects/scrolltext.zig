// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const RenderTarget = @import("../zigos.zig").RenderTarget;

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

        target: RenderTarget = undefined,
        speed: u16 = undefined,
        text: []const u8 = undefined,
        font_chars: []const u8 = undefined,
        text_pos: u16 = undefined,
        font_width: u16 = undefined,
        font_height: u16 = undefined,
        font_img: []const u8 = undefined,
        pos_y: u16 = undefined,
        fonts: [nb_fonts]FontLetter = undefined,
        offset_table: ?[]const u16,
        apply_offset_table: bool = false,
        y_offset_table: ?[]const i16,
        y_offset_table_index: u16 = undefined,
        y_offset_table_index_dir: bool = undefined,
        const Self = @This();

        pub fn init(target: RenderTarget, font_img: []const u8, font_chars: []const u8, width: u16, height: u16, text: []const u8, speed: u16, pos_y: u16, offset_table: ?[]const u16, y_offset_table: ?[]const i16, y_offset_table_direction: ?bool) Self {
            
            var scroller = Self{ 
                .offset_table = offset_table, 
                .y_offset_table=y_offset_table,
                .font_img = font_img,
                .font_chars = font_chars,
                .font_width = width,
                .font_height = height,
                .text = text,
                .speed = speed,
                .target = target,
                .pos_y = pos_y
            };
            if (offset_table) |table| {
                scroller.offset_table = table;
                scroller.apply_offset_table = true;
            }

            if (y_offset_table) |table| {
                scroller.y_offset_table = table;
                scroller.y_offset_table_index = 0;
                if (y_offset_table_direction) |dir| {
                    scroller.y_offset_table_index_dir = dir;
                } else {
                     scroller.y_offset_table_index_dir = true;
                }
            }        

            // create as many Sprites as letters shown on screen
            const current_text: *const [nb_fonts]u8 = scroller.text[0..nb_fonts];
            for (current_text) |char, idx| {
                const letter: u8 = char - scroller.font_chars[0];
                const pos_x: u16 = @intCast(u16, idx) * scroller.font_width;

                Console.log("Creating FontLetter {c} {} for ASCII {} => index {} at ({}, {}). Starting value: {}", .{ char, idx, char, letter, pos_x, pos_y, scroller.font_chars[0] });

                scroller.fonts[idx] = FontLetter{ .char = char, .sprite = Sprite{ .x_offset_table=null, .y_offset_table=y_offset_table }, .pos_x = pos_x, .pos_y = pos_y };

                var char_pos_y: u16 = undefined;
                if (scroller.apply_offset_table) {  
                    Console.log("Applying position offset", .{});
                    if (scroller.offset_table) |table| {
                        char_pos_y = table[pos_x];
                    }
                } else {
                    char_pos_y = scroller.pos_y + pos_y;
                }

                const offset_start: u32 = @intCast(u32, letter) * (@intCast(u32, scroller.font_width) * @intCast(u32, scroller.font_height));
                const offset_end: u32 = @intCast(u32, letter + 1) * (@intCast(u32, scroller.font_width) * @intCast(u32, scroller.font_height));
                // Console.log("Position for letter {c} in fonts is : {}-{}", .{char, offset_start, offset_end});

                scroller.fonts[idx].sprite.init(scroller.target, 
                                                scroller.font_img[offset_start .. offset_end], 
                                                scroller.font_width, 
                                                scroller.font_height, 
                                                pos_x, 
                                                char_pos_y, 
                                                null, 
                                                y_offset_table);
                scroller.text_pos = nb_fonts;
            }

            Console.log("Scrolltext inited!", .{});
            
            return scroller;    
        }

        pub fn update(self: *Self) void {

            // apply y_offset table if set
            if (self.y_offset_table) |table| {

                if(self.y_offset_table_index_dir) {
                    if(self.y_offset_table_index > self.speed*2) {
                        self.y_offset_table_index -= self.speed*2;
                    } else {
                        self.y_offset_table_index = @intCast(u16, table.len);
                    }
                } else {
                    if(self.y_offset_table_index < @intCast(u16, table.len)) {
                        self.y_offset_table_index += self.speed*2;
                    } else {
                        self.y_offset_table_index = 0;
                    }
                }

            }

            for (self.fonts) |*font, idx| {
                var is_out: i32 = @intCast(i32, font.pos_x) - @intCast(i32, self.speed);
                if (is_out < -@intCast(i8, self.font_width)) {
                    
                    // set new sprite at the right of the previous one
                    if(idx > 0) {
                        font.pos_x = self.fonts[idx-1].pos_x + self.font_width;  //WIDTH - 1;
                    } else {
                        font.pos_x = self.fonts[self.fonts.len-1].pos_x + self.font_width; 
                    }

                    // show new letter
                    if (self.text_pos >= self.text.len) self.text_pos = 0;

                    const next_letter = self.text[self.text_pos] - self.font_chars[0];

                    const offset_start: u32 = @intCast(u32, next_letter) * (@intCast(u32, self.font_width) * @intCast(u32, self.font_height));
                    const offset_end: u32 = @intCast(u32, next_letter + 1) * (@intCast(u32, self.font_width) * @intCast(u32, self.font_height));

                    // font.*.sprite.data = self.font_img[next_letter * (self.font_width * self.font_height) .. (next_letter + 1)];
                    font.*.sprite.data = self.font_img[offset_start .. offset_end];
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

                font.*.sprite.update(font.pos_x, font.pos_y, null, self.y_offset_table_index);
            }
        }

        pub fn render(self: *Self) void {
            for (self.fonts) |*font| {
                font.sprite.render(null);
            }
        }
    };
}