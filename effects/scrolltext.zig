// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Sprite = @import("sprite.zig").Sprite;
const String = @import("../utils/zig-string.zig").String;

const Console = @import("../utils/debug.zig").Console;

const ArenaAllocator = std.heap.ArenaAllocator;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Scrolltext = struct {
    fb: *LogicalFB = undefined,
    speed: i8 = undefined,
    text: String,
    font_chars: String,
    text_pos: u16,
    font_width: u16,
    font_height: u16,
    fonts: []const Sprite,

    pub fn init(fb: *LogicalFB, font_img: []const u8, font_chars: []const u8, width: u16, height: u16, text: []const u8, speed: i8) !Scrolltext {

        // allocattor
        const alloc: std.mem.Allocator = std.heap.page_allocator;

        // create strings
        Console.log("Allocating string for scroller text", .{});
        var text_str = String.init(alloc);
        // defer text_str.deinit();

        Console.log("Concat string for scroller text", .{});
        try text_str.concat(text);
        Console.log("String created: {s}", .{text_str.str()});

        Console.log("Allocating string for scroller char list", .{});
        var font_chars_str = String.init(alloc);
        // defer font_chars_str.deinit();
        
        try font_chars_str.concat(font_chars);

        // allocate fonts table
        Console.log("Allocating array of {d} Sprites", .{font_chars.len});
        var fonts: []Sprite = try alloc.alloc(Sprite, font_chars.len);

        // create as many Sprites as letters
        for (font_chars) |_, idx| {
            Console.log("slices: {} {}x{} {} {} vs {}", .{ idx, width, height, idx * (width * height), (idx + 1) * (width * height), font_img.len });
            fonts[idx] = Sprite.init(fb, font_img[idx * (width * height) .. (idx + 1) * (width * height)], width, height, 0, 0);
        }

        return .{ .fb = fb, .speed = speed, .text = text_str, .font_chars = font_chars_str, .text_pos = 0, .font_width = width, .font_height = height, .fonts = fonts };
    }

    pub fn update(self: *Scrolltext) void {
        self.text_pos += 1;

        const current_text = self.text[self.text_pos .. self.text_pos + 10];
        for (current_text) |char, idx| {
            const pos: usize = self.font_chars_str.find(char);
            self.fonts[pos].update(idx + self.width);
        }
    }

    pub fn render(self: *Scrolltext) void {
        const current_text = self.text[self.text_pos .. self.text_pos + 10];
        for (current_text) |char| {
            const pos: usize = self.font_chars_str.find(char);
            self.fonts[pos].render();
        }
    }
};
