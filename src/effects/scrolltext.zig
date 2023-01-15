// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Sprite = @import("sprite.zig").Sprite;

const Console = @import("../utils/debug.zig").Console;

const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;
// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// TODO: replace this constant by comptime font WIDTH//width
const NB_FONTS: u8 = 11;
const OFFSET_DATA_SIZE = WIDTH*4;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------



// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Scrolltext = struct {
    const FontLetter = struct { char: u8 = undefined, sprite: Sprite = undefined, pos_x: i32 = undefined, pos_y: i32 = undefined };

    fb: *LogicalFB = undefined,
    speed: u16 = undefined,
    text: []const u8 = undefined,
    font_chars: []const u8 = undefined,
    text_pos: u16 = undefined,
    font_width: u16 = undefined,
    font_height: u16 = undefined,
    font_img: []const u8 = undefined,
    pos_y: u16 = undefined,
    fonts: [NB_FONTS]FontLetter = undefined,
    offset_table: ?[WIDTH]u16 = undefined,
    apply_offset_table: bool = false,
    y_offset_table: ?[OFFSET_DATA_SIZE]i16 = undefined,
    y_offset_table_index: u16 = undefined,

    pub fn init(self: *Scrolltext, fb: *LogicalFB, font_img: []const u8, font_chars: []const u8, width: u16, height: u16, text: []const u8, speed: u16, pos_y: u16, offset_table: ?[WIDTH]u16, y_offset_table: ?[OFFSET_DATA_SIZE]i16) void {
        self.font_img = font_img;
        self.font_chars = font_chars;
        self.font_width = width;
        self.font_height = height;
        self.text = text;
        self.speed = speed;
        self.fb = fb;
        self.pos_y = pos_y;
        if (offset_table) |table| {
            self.offset_table = table;
            self.apply_offset_table = true;
        }

        if (y_offset_table) |table| {
            self.y_offset_table = table;
            self.y_offset_table_index = 0;
        }        

        // create as many Sprites as letters shown on screen
        const current_text: *const [NB_FONTS]u8 = self.text[0..NB_FONTS];
        for (current_text) |char, idx| {
            const letter: u8 = char - self.font_chars[0];
            const pos_x: u16 = @intCast(u16, idx) * self.font_width;

            Console.log("Creating FontLetter {c} {} for ASCII {} at ({}, {}). Staring value: {}", .{ char, idx, letter, pos_x, pos_y, self.font_chars[0] });

            self.fonts[idx] = FontLetter{ .char = char, .sprite = Sprite{}, .pos_x = pos_x, .pos_y = pos_y };

            var char_pos_y: u16 = undefined;
            if (self.apply_offset_table) {  
                if (self.offset_table) |table| {
                    char_pos_y = table[pos_x];
                }
            } else {
                char_pos_y = self.pos_y + pos_y;
            }

            self.fonts[idx].sprite.init(self.fb, self.font_img[letter * (self.font_width * self.font_height) .. (letter + 1) * (self.font_width * self.font_height)], self.font_width, self.font_height, pos_x, char_pos_y, false, y_offset_table);
            self.text_pos = NB_FONTS;
        }

        Console.log("Scrolltext inited!", .{});
    }

    pub fn update(self: *Scrolltext) void {

        // apply y_offset table if set
        if (self.y_offset_table) |table| {
            if(self.y_offset_table_index > self.speed*2) {
                self.y_offset_table_index -= self.speed*2;
            } else {
                // Console.log("Reset y offset index: {}", .{self.y_offset_table_index});
                self.y_offset_table_index = table.len;
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

    pub fn render(self: *Scrolltext) void {
        for (self.fonts) |*font| {
            font.sprite.render();
        }
    }
};
