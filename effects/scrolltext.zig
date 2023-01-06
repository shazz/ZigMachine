// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Sprite = @import("sprite.zig").Sprite;

const Console = @import("../utils/debug.zig").Console;

const ArenaAllocator = std.heap.ArenaAllocator;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;
const NB_FONTS: u8 = 9;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Scrolltext = struct {

    const FontLetter = struct {
        char: u8 = undefined,
        sprite: Sprite = undefined,
        pos_x: i32 = undefined,
        pos_y: i32 = undefined
    };

    fb: *LogicalFB = undefined,
    speed: u16 = undefined,
    text: []const u8= undefined,
    font_chars: []const u8= undefined,
    text_pos: u16= undefined,
    font_width: u16= undefined,
    font_height: u16= undefined,
    font_img: []const u8= undefined,
    pos_y: u16= undefined,
    fonts: [9]FontLetter = undefined,
    is_set: bool = false,

    pub fn init(fb: *LogicalFB, font_img: []const u8, font_chars: []const u8, width: u16, height: u16, text: []const u8, speed: u16, pos_y: u16) !Scrolltext {

        return .{ .fb = fb, .speed = speed, .text = text, .font_chars = font_chars, .font_img = font_img, .text_pos = 0, .font_width = width, .font_height = height, .pos_y = pos_y };
    }

    pub fn update(self: *Scrolltext) void {

        if (self.is_set == false) {
            // create as many Sprites as letters
            const current_text: *const[9]u8 = self.text[0 .. 9];
            for (current_text) | char, idx | {
                
                const letter: u8 = char - 65;
                const pos_x: u16 = @intCast(u16, idx)*self.font_width;
                const pos_y: u16 = self.pos_y;

                Console.log("Creating FontLetter {c} {} for ASCII {} at ({}, {})", .{char, idx, letter, pos_x, pos_y});

                self.fonts[idx] = FontLetter{
                    .char = char,
                    .sprite = Sprite.init(self.fb, self.font_img[letter * (self.font_width * self.font_height) .. (letter + 1) * (self.font_width * self.font_height)], self.font_width, self.font_height, pos_x, pos_y, false),
                    .pos_x = pos_x,
                    .pos_y = pos_y
                };
                self.text_pos = 9;
                self.is_set = true;
            }
            Console.log("Scrolltext inited!", .{});    

        } else {
            
            var counter: u8 = 0;
            while (counter < self.fonts.len) : (counter += 1) {
                var font: *FontLetter = &self.fonts[counter];
                var sprite: *Sprite = &font.sprite;

                var is_out: i32 = @intCast(i32, font.pos_x) - @intCast(i32, self.speed);
                if(is_out < -@intCast(i8, self.font_width)) {
                    font.pos_x = WIDTH-1; 

                    // show new letter
                    self.text_pos += 1;
                    if(self.text_pos >= self.text.len) self.text_pos = 0;

                    const next_letter = self.text[self.text_pos] - 65;
                    sprite.data = self.font_img[next_letter * (self.font_width * self.font_height) .. (next_letter + 1)];

                } else {
                    font.pos_x -= self.speed;
                }

                sprite.update(font.pos_x , self.pos_y);
            }
        }

        // self.text_pos += 1;

        // const current_text = self.text[self.text_pos .. self.text_pos + 10];
        // for (current_text) |char, idx| {

        //     const pos: u8 = char - 65;
        //     var sprite = self.fonts[pos].sprite;
        //     sprite.update(@intCast(u16, idx) - self.font_width, null);
        // }
    }

    pub fn render(self: *Scrolltext) void {
        for (self.fonts) |font| {
            var sprite = font.sprite;
            // Console.log("render font {c} at ({}, {}) -> ({}, {})", .{font.char, font.pos_x, font.pos_y, sprite.x_offset, sprite.y_offset});

            sprite.render();
        }
    }
};
